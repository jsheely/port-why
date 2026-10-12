/// Reads open ports and their owners on macOS by asking `lsof` and `ps`.
///
/// macOS has no `/proc`, and the calls behind these two tools are private
/// enough that running them is the dependable way in. `lsof` only reports the
/// sockets of processes we are allowed to inspect: our own, or everybody's
/// when run as root.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models.dart';
import 'posix_scan.dart';

const _lsof = '/usr/sbin/lsof';
const _ps = '/bin/ps';

/// One line of `ps`: what is known about every process without asking twice.
class PsRow {
  const PsRow({
    required this.pid,
    required this.parentPid,
    required this.uid,
    required this.startedAt,
    required this.executable,
  });

  final int pid;
  final int parentPid;
  final int uid;
  final DateTime startedAt;

  /// The executable's full path, as macOS reports `comm`.
  final String executable;

  String get name => executable.substring(executable.lastIndexOf('/') + 1);

  /// Whole seconds are as fine as `ps` goes.
  int get startStamp => startedAt.millisecondsSinceEpoch ~/ 1000;
}

/// Parses `lsof -nP -F pcftPn` restricted to internet sockets.
///
/// The output is one field to a line, led by a letter: `p` opens a process,
/// `f` opens one of its files, and `t`, `P` and `n` describe that file.
List<BoundSocket> parseLsofSockets(String output) {
  final sockets = <BoundSocket>[];
  int? pid;
  String? type;
  Protocol? protocol;
  for (final line in const LineSplitter().convert(output)) {
    if (line.isEmpty) continue;
    final value = line.substring(1);
    switch (line[0]) {
      case 'p':
        pid = int.tryParse(value);
      case 'f':
        type = null;
        protocol = null;
      case 't':
        type = value;
      case 'P':
        protocol = switch (value) {
          'TCP' => Protocol.tcp,
          'UDP' => Protocol.udp,
          _ => null,
        };
      case 'n' when pid != null && protocol != null:
        // 127.0.0.1:3000, *:8080, [::1]:3000, or local->remote once connected.
        final local = value.split('->').first;
        final colon = local.lastIndexOf(':');
        if (colon < 0) continue;
        final port = int.tryParse(local.substring(colon + 1));
        if (port == null || port == 0) continue;
        var address = local.substring(0, colon);
        if (address.startsWith('[') && address.endsWith(']')) {
          address = address.substring(1, address.length - 1);
        }
        if (address == '*') address = type == 'IPv6' ? '::' : '0.0.0.0';
        sockets.add(
          BoundSocket(protocol: protocol, address: address, port: port, pid: pid),
        );
    }
  }
  return sockets;
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

//   501     1   501 Sun Oct 11 14:03:22 2026 /Applications/Some App.app/...
final _psLine = RegExp(
  r'^\s*(\d+)\s+(\d+)\s+(\d+)\s+\w+\s+(\w+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\d+)\s+(.+)$',
);

/// Parses `ps -axo pid=,ppid=,uid=,lstart=,comm=` as printed in the C locale.
Map<int, PsRow> parsePs(String output) {
  final rows = <int, PsRow>{};
  for (final line in const LineSplitter().convert(output)) {
    final match = _psLine.firstMatch(line);
    if (match == null) continue;
    final month = _months.indexOf(match[4]!) + 1;
    if (month == 0) continue;
    final pid = int.parse(match[1]!);
    rows[pid] = PsRow(
      pid: pid,
      parentPid: int.parse(match[2]!),
      uid: int.parse(match[3]!),
      startedAt: DateTime(
        int.parse(match[9]!),
        month,
        int.parse(match[5]!),
        int.parse(match[6]!),
        int.parse(match[7]!),
        int.parse(match[8]!),
      ),
      executable: match[10]!.trimRight(),
    );
  }
  return rows;
}

/// Parses `ps -ww -o pid=,args=` into command lines by pid.
Map<int, String> parsePsArguments(String output) => {
  for (final line in const LineSplitter().convert(output))
    if (RegExp(r'^\s*(\d+)\s+(.+)$').firstMatch(line) case final match?)
      int.parse(match[1]!): match[2]!.trimRight(),
};

/// Parses `lsof -a -d cwd -F n` into working directories by pid.
Map<int, String> parseLsofFolders(String output) {
  final folders = <int, String>{};
  int? pid;
  for (final line in const LineSplitter().convert(output)) {
    if (line.startsWith('p')) pid = int.tryParse(line.substring(1));
    if (line.startsWith('n/') && pid != null) folders[pid] = line.substring(1);
  }
  return folders;
}

/// Every listening TCP socket, and with [includeUdp] every bound UDP one,
/// among the processes `lsof` may look at. Null if it could not be run.
Future<List<BoundSocket>?> boundSockets({required bool includeUdp}) async {
  final outputs = await Future.wait([
    _run(_lsof, const ['-nP', '-iTCP', '-sTCP:LISTEN', '-F', 'pcftPn']),
    if (includeUdp) _run(_lsof, const ['-nP', '-iUDP', '-F', 'pcftPn']),
  ]);
  if (outputs.first == null) return null;
  return [for (final output in outputs.nonNulls) ...parseLsofSockets(output)];
}

/// Every process on the machine.
Future<Map<int, PsRow>> processTable() async =>
    parsePs(await _run(_ps, const ['-axo', 'pid=,ppid=,uid=,lstart=,comm=']) ?? '');

/// The command lines of [pids].
Future<Map<int, String>> commandLines(Iterable<int> pids) async => pids.isEmpty
    ? const {}
    : parsePsArguments(
        await _run(_ps, ['-ww', '-o', 'pid=,args=', '-p', pids.join(',')]) ?? '',
      );

/// The working directories of [pids].
Future<Map<int, String>> workingFolders(Iterable<int> pids) async => pids.isEmpty
    ? const {}
    : parseLsofFolders(
        await _run(_lsof, ['-a', '-d', 'cwd', '-F', 'n', '-p', pids.join(',')]) ??
            '',
      );

/// When [pid] started, in seconds since the epoch, or null if it is gone (or
/// has exited and is only waiting to be reaped).
Future<int?> startStampOf(int pid) async {
  final output = await _run(_ps, ['-o', 'pid=,ppid=,uid=,lstart=,comm=', '-p', '$pid']);
  final row = parsePs(output ?? '')[pid];
  if (row == null) return null;
  final state = await _run(_ps, ['-o', 'stat=', '-p', '$pid']);
  return state == null || state.trim().startsWith('Z') ? null : row.startStamp;
}

/// The name of the app bundle [executable] sits in: `Visual Studio Code` for
/// anything under `/Applications/Visual Studio Code.app`.
String? bundleName(String executable) =>
    RegExp(r'/([^/]+)\.app/').firstMatch(executable)?[1];

/// Standard output, whatever the exit code: `lsof` exits with 1 when any of
/// the pids it was asked about has gone. Null if the tool will not start or
/// does not finish.
Future<String?> _run(String executable, List<String> arguments) async {
  final Process process;
  try {
    process = await Process.start(
      executable,
      arguments,
      // Dates are parsed, so they must not be localised.
      environment: const {'LC_ALL': 'C'},
    );
  } on ProcessException {
    return null;
  }
  final output = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .join();
  unawaited(process.stderr.drain<void>());

  const timedOut = -0x7fffffff;
  final exitCode = await process.exitCode.timeout(
    const Duration(seconds: 8),
    onTimeout: () {
      process.kill();
      return timedOut;
    },
  );
  return exitCode == timedOut ? null : await output;
}
