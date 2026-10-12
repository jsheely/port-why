/// Reads open ports and their owners straight out of `/proc` on Linux.
///
/// Nothing here runs another program. The kernel lists every bound socket in
/// `/proc/net`, by inode; which process holds an inode is found by reading
/// the `fd` folder of each process. That folder is only readable for our own
/// processes (or all of them, as root), so a socket belonging to another user
/// is seen but cannot be put to a process.
library;

import 'dart:io';
import 'dart:typed_data';

import '../../models.dart';
import 'posix_scan.dart';

/// Parses `/proc/net/tcp`, `tcp6`, `udp` or `udp6`: listening sockets for TCP,
/// bound ones for UDP.
List<BoundSocket> parseProcNet(String text, Protocol protocol) {
  final sockets = <BoundSocket>[];
  // The first line is the column headings.
  for (final line in text.split('\n').skip(1)) {
    //  sl local_address rem_address st tx:rx tr:when retrnsmt uid timeout inode
    //  0: 0100007F:1F90 00000000:0000 0A ...                 1000       0 12345
    final columns = line.trim().split(RegExp(r'\s+'));
    if (columns.length < 10) continue;
    if (protocol == Protocol.tcp && columns[3] != '0A') continue; // LISTEN
    final local = columns[1];
    final colon = local.lastIndexOf(':');
    final port = int.tryParse(local.substring(colon + 1), radix: 16);
    final address = _address(local.substring(0, colon));
    final inode = int.tryParse(columns[9]);
    if (port == null || port == 0 || address == null || inode == null) continue;
    sockets.add(
      BoundSocket(
        protocol: protocol,
        address: address,
        port: port,
        uid: int.tryParse(columns[7]),
        inode: inode,
      ),
    );
  }
  return sockets;
}

/// The kernel prints an address as 32-bit words in its own byte order, so
/// each word is put back into the order it has on the wire.
String? _address(String hex) {
  if (hex.length != 8 && hex.length != 32) return null;
  final bytes = ByteData(hex.length ~/ 2);
  for (var word = 0; word < hex.length ~/ 8; word++) {
    final value = int.tryParse(hex.substring(word * 8, word * 8 + 8), radix: 16);
    if (value == null) return null;
    bytes.setUint32(word * 4, value, Endian.host);
  }
  var raw = bytes.buffer.asUint8List();
  // ::ffff:127.0.0.1 is an IPv4 address reached through an IPv6 socket.
  if (raw.length == 16 &&
      raw.take(10).every((byte) => byte == 0) &&
      raw[10] == 0xff &&
      raw[11] == 0xff) {
    raw = raw.sublist(12);
  }
  return InternetAddress.fromRawAddress(raw).address;
}

/// Every bound socket the kernel lists for this network namespace.
List<BoundSocket> boundSockets({required bool includeUdp}) => [
  for (final (file, protocol) in [
    ('tcp', Protocol.tcp),
    ('tcp6', Protocol.tcp),
    if (includeUdp) ...[('udp', Protocol.udp), ('udp6', Protocol.udp)],
  ])
    ...parseProcNet(_read('/proc/net/$file') ?? '', protocol),
];

/// The pids holding each of [inodes] open, for those we are allowed to see.
Map<int, List<int>> socketHolders(Set<int> inodes) {
  final holders = <int, List<int>>{};
  if (inodes.isEmpty) return holders;
  for (final pid in _pids()) {
    try {
      for (final fd in Directory('/proc/$pid/fd').listSync(followLinks: false)) {
        // socket:[12345]
        final target = Link(fd.path).targetSync();
        if (!target.startsWith('socket:[')) continue;
        final inode = int.tryParse(target.substring(8, target.length - 1));
        if (inodes.contains(inode)) holders.putIfAbsent(inode!, () => []).add(pid);
      }
    } on FileSystemException {
      // Someone else's process, or one that exited while we were looking.
    }
  }
  return holders;
}

Iterable<int> _pids() sync* {
  try {
    for (final entry in Directory('/proc').listSync(followLinks: false)) {
      final pid = int.tryParse(entry.path.substring(6));
      if (pid != null) yield pid;
    }
  } on FileSystemException {
    // No /proc: nothing can be attributed.
  }
}

/// Everything `/proc` says about [pid], or null if it is gone.
PosixProcess? readProcess(int pid) {
  final stat = _Stat.read(pid);
  if (stat == null) return null;

  final exe = _link('/proc/$pid/exe')?.replaceFirst(RegExp(r' \(deleted\)$'), '');
  final arguments = (_read('/proc/$pid/cmdline') ?? '').split('\x00')
    ..removeWhere((argument) => argument.isEmpty);
  final uid = RegExp(
    r'^Uid:\s+(\d+)',
    multiLine: true,
  ).firstMatch(_read('/proc/$pid/status') ?? '')?[1];

  return PosixProcess(
    pid: pid,
    // The kernel's own name for a process stops at fifteen characters.
    name: exe != null
        ? exe.substring(exe.lastIndexOf('/') + 1)
        : arguments.isNotEmpty && arguments.first.startsWith('/')
        ? arguments.first.substring(arguments.first.lastIndexOf('/') + 1)
        : stat.name,
    parentPid: stat.parentPid,
    uid: uid == null ? null : int.parse(uid),
    exePath: exe,
    commandLine: arguments.isEmpty ? null : joinArguments(arguments),
    cwd: _link('/proc/$pid/cwd'),
    startStamp: stat.startTicks,
    startedAt: _bootTime?.add(
      Duration(milliseconds: stat.startTicks * 1000 ~/ _ticksPerSecond),
    ),
  );
}

/// When [pid] started, in clock ticks since boot, or null if it is gone (or
/// has exited and is only waiting to be reaped).
int? startTicksOf(int pid) {
  final stat = _Stat.read(pid);
  return stat == null || stat.isZombie ? null : stat.startTicks;
}

/// The uid this app runs as.
final int? ownUid = () {
  final uid = RegExp(
    r'^Uid:\s+(\d+)',
    multiLine: true,
  ).firstMatch(_read('/proc/self/status') ?? '')?[1];
  return uid == null ? null : int.parse(uid);
}();

/// Login names by uid, from `/etc/passwd`.
final Map<int, String> userNames = () {
  final names = <int, String>{};
  for (final line in (_read('/etc/passwd') ?? '').split('\n')) {
    final fields = line.split(':');
    if (fields.length < 3) continue;
    final uid = int.tryParse(fields[2]);
    if (uid != null) names.putIfAbsent(uid, () => fields[0]);
  }
  return names;
}();

/// USER_HZ, which the kernel fixes at 100 on every architecture Flutter
/// builds for.
const _ticksPerSecond = 100;

final DateTime? _bootTime = () {
  final seconds = RegExp(
    r'^btime\s+(\d+)',
    multiLine: true,
  ).firstMatch(_read('/proc/stat') ?? '')?[1];
  return seconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(int.parse(seconds) * 1000);
}();

class _Stat {
  const _Stat(this.name, this.isZombie, this.parentPid, this.startTicks);

  final String name;
  final bool isZombie;
  final int parentPid;
  final int startTicks;

  /// `1234 (some name) S 1 ...`: the name may itself hold spaces and
  /// brackets, so the fields are counted from the last closing one.
  static _Stat? read(int pid) {
    final text = _read('/proc/$pid/stat');
    if (text == null) return null;
    final open = text.indexOf('(');
    final close = text.lastIndexOf(')');
    if (open < 0 || close < open) return null;
    final fields = text.substring(close + 1).trim().split(' ');
    if (fields.length < 20) return null;
    final parent = int.tryParse(fields[1]);
    final start = int.tryParse(fields[19]);
    if (parent == null || start == null) return null;
    return _Stat(text.substring(open + 1, close), fields[0] == 'Z', parent, start);
  }
}

String? _read(String path) {
  try {
    return File(path).readAsStringSync();
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

String? _link(String path) {
  try {
    return Link(path).targetSync();
  } on FileSystemException {
    return null;
  }
}
