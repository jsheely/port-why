import 'dart:io';

import 'package:path/path.dart' as p;

import '../../detect/project_detector.dart';
import '../../detect/tech_detector.dart';
import '../../models.dart';
import 'win32.dart' as win32;

/// What the scan should cover. Sent to the scanning isolate.
class ScanRequest {
  const ScanRequest({this.includeUdp = false, this.knownProcesses = const {}});

  final bool includeUdp;

  /// Keys of processes the caller already holds an insight for. Working out a
  /// project and framework touches the disk, so it is done once per process
  /// rather than on every poll.
  final Set<String> knownProcesses;
}

/// The inferred, cacheable half of a row.
class ProcessInsight {
  const ProcessInsight({required this.tech, required this.category, this.project});

  final TechInfo tech;
  final ProjectInfo? project;
  final PortCategory category;
}

class ScannedProcess {
  const ScannedProcess({required this.key, required this.details, this.insight});

  /// Identifies this process instance in this working directory.
  final String key;
  final ProcessDetails details;

  /// Null when the caller said it already knows this process.
  final ProcessInsight? insight;
}

class ScannedPort {
  const ScannedPort({
    required this.protocol,
    required this.port,
    required this.addresses,
    required this.process,
    this.openedAt,
  });

  final Protocol protocol;
  final int port;
  final List<String> addresses;
  final DateTime? openedAt;
  final ScannedProcess process;
}

/// Reads every open port and everything knowable about its owner.
///
/// Top-level and free of shared state so it can run on a background isolate.
List<ScannedPort> scanWindows(ScanRequest request) {
  final endpoints = [
    ...win32.tcpListeners(),
    if (request.includeUdp) ...win32.udpEndpoints(),
  ];

  // A process listening on both 0.0.0.0 and :: is one row, not two.
  final rows = <(Protocol, int, int), List<win32.Endpoint>>{};
  for (final endpoint in endpoints) {
    rows
        .putIfAbsent((endpoint.protocol, endpoint.port, endpoint.pid), () => [])
        .add(endpoint);
  }

  final inspector = _ProcessInspector(request.knownProcesses);
  return [
    for (final MapEntry(key: (protocol, port, pid), value: bound) in rows.entries)
      ScannedPort(
        protocol: protocol,
        port: port,
        addresses: _sortedAddresses(bound),
        openedAt: _earliest(bound),
        process: inspector.inspect(pid),
      ),
  ];
}

List<String> _sortedAddresses(List<win32.Endpoint> bound) {
  final addresses = {for (final endpoint in bound) endpoint.address}.toList();
  int rank(String address) => address.contains(':') ? 1 : 0;
  addresses.sort((a, b) {
    final byFamily = rank(a).compareTo(rank(b));
    return byFamily != 0 ? byFamily : a.compareTo(b);
  });
  return addresses;
}

DateTime? _earliest(List<win32.Endpoint> bound) {
  DateTime? earliest;
  for (final endpoint in bound) {
    final created = endpoint.createdAt;
    if (created != null && (earliest == null || created.isBefore(earliest))) {
      earliest = created;
    }
  }
  return earliest;
}

class _ProcessInspector {
  _ProcessInspector(this._known);

  final Set<String> _known;
  final _snapshot = win32.snapshotProcesses();
  final _services = win32.servicesByPid();
  final _probes = <int, win32.ProcessProbe>{};
  final _inspected = <int, ScannedProcess>{};
  final _projects = ProjectDetector();
  static const _techs = TechDetector();

  late final String? _windowsDirectory = Platform.environment['SystemRoot']
      ?.toLowerCase();

  ScannedProcess inspect(int pid) => _inspected[pid] ??= _inspect(pid);

  // The kernel and idle "processes" are not real processes to open.
  win32.ProcessProbe _probe(int pid) => _probes[pid] ??= pid <= 4
      ? win32.ProcessProbe.denied
      : win32.probeProcess(pid);

  ScannedProcess _inspect(int pid) {
    final probe = _probe(pid);
    final summary = _snapshot[pid];
    final name = switch (pid) {
      0 => 'System Idle Process',
      4 => 'System',
      _ =>
        summary?.name ??
            (probe.exePath == null
                ? 'PID $pid'
                : p.windows.basename(probe.exePath!)),
    };
    final parent = _parentOf(pid, probe);

    final details = ProcessDetails(
      pid: pid,
      name: name,
      exePath: probe.exePath,
      commandLine: probe.commandLine,
      cwd: _tidy(probe.cwd),
      startStamp: probe.startStamp,
      startedAt: probe.startStamp == null
          ? null
          : win32.fileTimeToDateTime(probe.startStamp!),
      parentPid: parent?.pid,
      parentName: parent?.name,
      parentCommandLine: parent?.commandLine,
      services: _services[pid] ?? const [],
      restricted: probe.restricted,
    );

    final key = '$pid:${details.startStamp}:$name:${details.cwd ?? ''}';
    return ScannedProcess(
      key: key,
      details: details,
      insight: _known.contains(key) ? null : _insightFor(details),
    );
  }

  ({int pid, String name, String? commandLine})? _parentOf(
    int pid,
    win32.ProcessProbe probe,
  ) {
    final summary = _snapshot[pid];
    if (summary == null || summary.parentPid == 0) return null;
    final parentSummary = _snapshot[summary.parentPid];
    if (parentSummary == null) return null;
    final parentProbe = _probe(summary.parentPid);

    // Windows records the creator's pid and never updates it, so once the real
    // parent exits that pid can be handed to an unrelated, younger process.
    final childStart = probe.startStamp;
    final parentStart = parentProbe.startStamp;
    if (childStart != null && parentStart != null && parentStart > childStart) {
      return null;
    }
    return (
      pid: summary.parentPid,
      name: parentSummary.name,
      commandLine: parentProbe.commandLine,
    );
  }

  ProcessInsight _insightFor(ProcessDetails details) {
    final exePath = details.exePath;
    final isWindowsOwn =
        details.pid <= 4 || exePath == null || _isWindowsComponent(details);

    final project = isWindowsOwn
        ? null
        : _projects.detect(
            cwd: details.cwd,
            commandLine: details.commandLine,
            exePath: exePath,
            // With no manifest, the working directory's name only means
            // something if the process was pointed at that folder. A program
            // sitting in its own install folder (a game launcher in
            // C:\Games\Launcher) was not; an interpreter always was.
            allowFolderName:
                TechDetector.isRuntime(details.name) ||
                !_runsFromOwnFolder(exePath, details.cwd),
          );

    // A child of the same runtime (a reloader's worker, a cluster worker)
    // inherits its meaning from the parent's command line.
    final sameRuntimeParent =
        details.parentName?.toLowerCase() == details.name.toLowerCase();

    final tech = _techs.detect(
      pid: details.pid,
      processName: details.name,
      exePath: exePath,
      commandLine: details.commandLine,
      parentCommandLine: sameRuntimeParent ? details.parentCommandLine : null,
      cwd: details.cwd,
      project: project,
      services: details.services,
      description: exePath == null ? null : win32.fileDescription(exePath),
    );

    return ProcessInsight(
      tech: tech,
      project: project?.info,
      category: isWindowsOwn
          ? PortCategory.system
          : project != null
          ? PortCategory.project
          : PortCategory.app,
    );
  }

  /// True for the parts of Windows that run on their own: service hosts and
  /// the like. Living under C:\Windows is not enough, because so do
  /// powershell.exe, cmd.exe and ssh.exe, which a developer may well have
  /// started in a project folder. Those are told apart by where they run.
  bool _isWindowsComponent(ProcessDetails details) {
    final windows = _windowsDirectory;
    final exePath = details.exePath;
    if (windows == null || exePath == null) return false;
    if (!p.windows.isWithin(windows, exePath.toLowerCase())) return false;
    if (details.services.isNotEmpty) return true;
    final cwd = details.cwd?.toLowerCase();
    return cwd == null || cwd == windows || p.windows.isWithin(windows, cwd);
  }

  static bool _runsFromOwnFolder(String exePath, String? cwd) {
    if (cwd == null) return false;
    final exe = exePath.toLowerCase();
    final directory = cwd.toLowerCase();
    return p.windows.dirname(exe) == directory || p.windows.isWithin(directory, exe);
  }

  /// `C:\work\app\` becomes `C:\work\app`; a drive root keeps its separator.
  static String? _tidy(String? directory) {
    if (directory == null || directory.isEmpty) return null;
    return directory.length > 3 && directory.endsWith(r'\')
        ? directory.substring(0, directory.length - 1)
        : directory;
  }
}
