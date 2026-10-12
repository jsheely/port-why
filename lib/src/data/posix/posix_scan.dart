/// The scan on macOS and Linux. Each has its own way of listing sockets and
/// processes (macos_tools.dart, linux_proc.dart); what is made of them is
/// shared here.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../detect/project_detector.dart';
import '../../detect/tech_detector.dart';
import '../../models.dart';
import '../docker.dart' as docker;
import '../scan.dart';
import 'linux_proc.dart' as linux;
import 'macos_tools.dart' as macos;

/// A socket bound to a local port.
class BoundSocket {
  const BoundSocket({
    required this.protocol,
    required this.address,
    required this.port,
    this.pid,
    this.uid,
    this.inode,
  });

  final Protocol protocol;
  final String address;
  final int port;

  /// The process holding it, when the system said (macOS does).
  final int? pid;

  /// Who owns it and which socket it is, when the system said (Linux does).
  final int? uid;
  final int? inode;
}

/// A process as the system describes it, before anything is inferred.
class PosixProcess {
  const PosixProcess({
    required this.pid,
    required this.name,
    this.parentPid,
    this.uid,
    this.exePath,
    this.commandLine,
    this.cwd,
    this.startStamp,
    this.startedAt,
    this.description,
  });

  final int pid;
  final String name;
  final int? parentPid;
  final int? uid;
  final String? exePath;
  final String? commandLine;
  final String? cwd;

  /// Opaque: with [pid], identifies one process instance.
  final int? startStamp;
  final DateTime? startedAt;

  /// A friendlier name than the executable's, where the system has one.
  final String? description;
}

/// Arguments as one command line, quoting any that hold a space so it splits
/// back into the same arguments.
String joinArguments(List<String> arguments) => [
  for (final argument in arguments)
    argument.contains(RegExp(r'\s')) ? '"$argument"' : argument,
].join(' ');

/// What a scan found before it was made into rows.
class PosixSnapshot {
  const PosixSnapshot({
    required this.sockets,
    required this.processes,
    this.ownUid,
    this.userNames = const {},
    this.keepDetails = false,
  });

  final List<BoundSocket> sockets;

  /// The processes holding [sockets], and their parents. One that the caller
  /// already knows may be missing its folder and command line.
  final Map<int, PosixProcess> processes;
  final int? ownUid;
  final Map<int, String> userNames;

  /// True when a process's folder and command line cost a round trip to
  /// read, so they are only read once and the caller holds on to them.
  final bool keepDetails;
}

/// Processes that hold ports on behalf of containers: Docker's forwarder on
/// Linux, Docker Desktop's on macOS, and the rootless ones.
const _relays = {
  'docker-proxy',
  'com.docker.backend',
  'rootlesskit',
  'rootlessport',
};

/// Every open port and what could be learned about its owner, with ports
/// held by Docker traced to the container that publishes them.
///
/// Top-level and free of shared state so it can run on a background isolate.
Future<List<ScannedPort>> scanPosix(ScanRequest request, HostOs os) async {
  final snapshot = os == HostOs.macos
      ? await _snapshotMacos(request)
      : _snapshotLinux(request);
  final ports = assemblePorts(request, snapshot, os);
  return traceContainers(request, ports, docker.runningContainers);
}

PosixSnapshot _snapshotLinux(ScanRequest request) {
  final sockets = linux.boundSockets(includeUdp: request.includeUdp);
  final holders = linux.socketHolders({for (final socket in sockets) ?socket.inode});

  final processes = <int, PosixProcess>{};
  PosixProcess? process(int pid) {
    final read = processes[pid] ?? linux.readProcess(pid);
    if (read != null) processes[pid] = read;
    return read;
  }

  final owned = <BoundSocket>[];
  for (final socket in sockets) {
    final pid = _eldest(holders[socket.inode] ?? const [], process);
    final parent = pid == null ? null : process(pid)?.parentPid;
    if (parent != null && parent > 0) process(parent);
    owned.add(
      BoundSocket(
        protocol: socket.protocol,
        address: socket.address,
        port: socket.port,
        pid: pid,
        uid: socket.uid,
        inode: socket.inode,
      ),
    );
  }
  return PosixSnapshot(
    sockets: owned,
    processes: processes,
    ownUid: linux.ownUid,
    userNames: linux.userNames,
  );
}

/// A listening socket is shared by a server and the workers it forks. The
/// one to name, and to kill, is the one the others descend from.
int? _eldest(List<int> holders, PosixProcess? Function(int pid) process) {
  if (holders.isEmpty) return null;
  final all = holders.toSet();
  final sorted = holders.toList()..sort();
  for (final pid in sorted) {
    if (!all.contains(process(pid)?.parentPid)) return pid;
  }
  return sorted.first;
}

Future<PosixSnapshot> _snapshotMacos(ScanRequest request) async {
  final sockets = await macos.boundSockets(includeUdp: request.includeUdp);
  if (sockets == null) throw const ScanFailure('lsof could not be run');
  final table = await macos.processTable();

  final owners = {for (final socket in sockets) ?socket.pid};
  final unknown = {
    for (final pid in owners)
      if (table[pid] case final row?)
        if (!request.knownProcesses.contains(_stableKey(pid, row.startStamp, row.name)))
          pid,
  };
  final parents = {
    for (final pid in unknown)
      if (table[pid]!.parentPid > 1) table[pid]!.parentPid,
  };
  final (commands, folders) = await (
    macos.commandLines({...unknown, ...parents}),
    macos.workingFolders(unknown),
  ).wait;

  return PosixSnapshot(
    sockets: sockets,
    keepDetails: true,
    // This app's own row: `pid` here is dart:io's.
    ownUid: table[pid]?.uid,
    processes: {
      for (final pid in {...owners, ...parents})
        if (table[pid] case final row?)
          pid: PosixProcess(
            pid: pid,
            name: row.name,
            parentPid: row.parentPid,
            uid: row.uid,
            exePath: row.executable.startsWith('/') ? row.executable : null,
            commandLine: commands[pid],
            cwd: folders[pid],
            startStamp: row.startStamp,
            startedAt: row.startedAt,
            description: macos.bundleName(row.executable),
          ),
    },
  );
}

/// The scan could not be made at all, as opposed to finding nothing.
class ScanFailure implements Exception {
  const ScanFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

String _stableKey(int pid, int? startStamp, String name) => '$pid:$startStamp:$name';

/// Turns [snapshot] into one row per port and owner, with each owner's
/// project and framework worked out unless [request] says the caller has it.
List<ScannedPort> assemblePorts(
  ScanRequest request,
  PosixSnapshot snapshot,
  HostOs os, {
  ProjectDetector? projects,
}) {
  // A process listening on both 0.0.0.0 and :: is one row, not two. Sockets
  // nobody could be found for are told apart by who owns them.
  final rows = <(Protocol, int, int?, int?), List<BoundSocket>>{};
  for (final socket in snapshot.sockets) {
    final pid = snapshot.processes.containsKey(socket.pid) ? socket.pid : null;
    rows
        .putIfAbsent(
          (socket.protocol, socket.port, pid, pid == null ? socket.uid : null),
          () => [],
        )
        .add(socket);
  }

  final inspector = _Inspector(request, snapshot, os, projects ?? ProjectDetector());
  return [
    for (final MapEntry(key: (protocol, port, pid, uid), value: bound) in rows.entries)
      ScannedPort(
        protocol: protocol,
        port: port,
        addresses: sortedAddresses(bound.map((socket) => socket.address)),
        process: pid == null ? inspector.hidden(uid, bound) : inspector.inspect(pid),
      ),
  ];
}

class _Inspector {
  _Inspector(this._request, this._snapshot, this._os, this._projects);

  final ScanRequest _request;
  final PosixSnapshot _snapshot;
  final HostOs _os;
  final ProjectDetector _projects;
  final _inspected = <int, ScannedProcess>{};
  static const _techs = TechDetector();

  String get _osIcon => _os == HostOs.macos ? 'apple' : 'linux';

  ScannedProcess inspect(int pid) => _inspected[pid] ??= _inspect(pid);

  ScannedProcess _inspect(int pid) {
    final process = _snapshot.processes[pid]!;
    final parent = _snapshot.processes[process.parentPid];
    final key = _snapshot.keepDetails
        ? _stableKey(pid, process.startStamp, process.name)
        : '${_stableKey(pid, process.startStamp, process.name)}:${process.cwd ?? ''}';

    final details = ProcessDetails(
      pid: pid,
      name: process.name,
      exePath: process.exePath,
      commandLine: process.commandLine,
      cwd: process.cwd,
      startStamp: process.startStamp,
      startedAt: process.startedAt,
      parentPid: parent?.pid,
      parentName: parent?.name,
      parentCommandLine: parent?.commandLine,
      // Somebody else's process, which only root may look inside.
      restricted:
          process.cwd == null &&
          process.uid != null &&
          process.uid != _snapshot.ownUid,
    );
    final isKnown = _request.knownProcesses.contains(key);
    return ScannedProcess(
      key: key,
      details: details,
      insight: isKnown ? null : _insightFor(process, parent),
      keepDetails: _snapshot.keepDetails,
    );
  }

  /// A socket whose process we are not allowed to see. All that is known is
  /// who owns it.
  ScannedProcess hidden(int? uid, List<BoundSocket> bound) {
    final user = uid == null ? null : _snapshot.userNames[uid] ?? 'uid $uid';
    final inodes = [for (final socket in bound) ?socket.inode]..sort();
    return ScannedProcess(
      // A socket is made anew whenever its listener restarts, so the key
      // changes exactly when the answer might.
      key: 'socket:${bound.first.protocol.name}:${bound.first.port}:${inodes.join(',')}',
      details: ProcessDetails(
        pid: 0,
        name: user == null ? 'unknown process' : 'owned by $user',
        restricted: true,
      ),
      insight: ProcessInsight(
        tech: TechInfo(name: 'Hidden process', icon: _osIcon),
        category: uid == null || _isSystemUser(uid)
            ? PortCategory.system
            : PortCategory.app,
      ),
    );
  }

  ProcessInsight _insightFor(PosixProcess process, PosixProcess? parent) {
    final exePath = process.exePath;
    final project = _projects.detect(
      cwd: process.cwd,
      commandLine: process.commandLine,
      exePath: exePath,
      // With no manifest, the working directory's name only means something
      // if the process was pointed at that folder. A program sitting in its
      // own install folder was not; an interpreter always was.
      allowFolderName:
          TechDetector.isRuntime(process.name) ||
          exePath == null ||
          !_runsFromOwnFolder(exePath, process.cwd),
    );

    // A child of the same runtime (a reloader's worker, a cluster worker)
    // inherits its meaning from the parent's command line.
    final tech = _techs.detect(
      pid: process.pid,
      processName: process.name,
      exePath: exePath,
      commandLine: process.commandLine,
      parentCommandLine: parent?.name == process.name ? parent?.commandLine : null,
      cwd: process.cwd,
      project: project,
      description: process.description,
    );

    final isSystem = project == null && _isSystemOwn(process);
    return ProcessInsight(
      tech: isSystem ? withFallbackIcon(tech, _osIcon) : tech,
      project: project?.info,
      category: isSystem
          ? PortCategory.system
          : project != null
          ? PortCategory.project
          : PortCategory.app,
    );
  }

  /// True for the daemons the system runs for itself. Being started by root
  /// is not enough once a project is involved (`sudo npm start`), which is
  /// why the caller looks for a project first.
  bool _isSystemOwn(PosixProcess process) {
    final uid = process.uid;
    if (uid != null && _isSystemUser(uid)) return true;
    final exePath = process.exePath;
    return exePath != null && _systemFolders.any(exePath.startsWith);
  }

  static const _systemFolders = [
    '/System/',
    '/usr/libexec/',
    '/usr/lib/systemd/',
    '/lib/systemd/',
  ];

  /// Accounts for people start at 1000 on Linux and 501 on macOS.
  bool _isSystemUser(int uid) => uid < (_os == HostOs.macos ? 500 : 1000);

  static bool _runsFromOwnFolder(String exePath, String? cwd) =>
      cwd != null && (p.posix.dirname(exePath) == cwd || p.posix.isWithin(cwd, exePath));
}

/// Replaces rows that Docker's forwarders hold, or that might be theirs but
/// cannot be seen, with the container publishing the port.
///
/// [containers] is only called when such a row has appeared or changed, so
/// ordinary polling never starts a Docker command.
Future<List<ScannedPort>> traceContainers(
  ScanRequest request,
  List<ScannedPort> ports,
  Future<List<docker.PublishedContainer>?> Function() containers,
) async {
  final unknown = <int>[];
  for (final (index, port) in ports.indexed) {
    if (port.protocol != Protocol.tcp) continue;
    final holder = port.process;
    final isHidden = holder.details.pid == 0;
    if (!isHidden && !_relays.contains(holder.details.name)) continue;
    // A forwarder is one process fronting many unrelated ports, so each of
    // its ports is looked up, and remembered, on its own.
    final key = isHidden ? holder.key : 'relay:${holder.key}:${port.port}';
    final isKnown = request.knownProcesses.contains(key);
    ports[index] = port.withProcess(
      ScannedProcess(
        key: key,
        details: holder.details,
        insight: isKnown ? null : holder.insight,
      ),
    );
    if (!isKnown) unknown.add(index);
  }
  if (unknown.isEmpty) return ports;

  final running = await containers();
  for (final index in unknown) {
    final port = ports[index];
    final holder = port.process;
    final container = running
        ?.where((container) => container.publishedPorts.contains(port.port))
        .firstOrNull;
    ports[index] = port.withProcess(
      container == null
          ? ScannedProcess(
              key: holder.key,
              details: holder.details,
              insight: holder.insight,
              // If Docker did not answer, do not let that stick.
              remember: running != null,
            )
          : ScannedProcess(
              key: holder.key,
              details: ProcessDetails(
                pid: 0,
                name: container.info.name,
                container: container.info,
              ),
              insight: docker.containerInsight(container.info),
              keepDetails: true,
            ),
    );
  }
  return ports;
}

/// Ends [pid]: politely first, then by force. With [expectedStartStamp], only
/// if it is still the same process, so a recycled pid is never hit by
/// mistake. Returns once it has gone, so its ports are free by then.
Future<KillResult> terminateProcess(
  int pid,
  HostOs os, {
  int? expectedStartStamp,
}) async {
  Future<int?> startStamp() async =>
      os == HostOs.macos ? macos.startStampOf(pid) : linux.startTicksOf(pid);
  Future<bool> hasGone(int attempts, Duration pause) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (await startStamp() == null) return true;
      await Future<void>.delayed(pause);
    }
    return false;
  }

  final stamp = await startStamp();
  if (stamp == null) return KillResult.notFound;
  if (expectedStartStamp != null && stamp != expectedStartStamp) {
    return KillResult.notFound;
  }
  if (!Process.killPid(pid, ProcessSignal.sigterm)) {
    return await startStamp() == null
        ? KillResult.notFound
        : KillResult.accessDenied;
  }
  if (await hasGone(15, const Duration(milliseconds: 200))) return KillResult.killed;
  Process.killPid(pid, ProcessSignal.sigkill);
  return await hasGone(10, const Duration(milliseconds: 100))
      ? KillResult.killed
      : KillResult.failed;
}
