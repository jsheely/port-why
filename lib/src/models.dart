/// Plain data types shared by the scanner, the detectors and the UI.
///
/// Nothing in here may import Flutter: these objects are built on a background
/// isolate and sent back to the UI isolate.
library;

import 'package:path/path.dart' as p;

enum Protocol {
  tcp('TCP'),
  udp('UDP');

  const Protocol(this.label);
  final String label;
}

/// Coarse grouping used by the scope filter.
enum PortCategory {
  /// The owning process could be tied to a project folder.
  project,

  /// A user application with no recognisable project.
  app,

  /// Windows itself: the kernel, service hosts, and anything we cannot inspect.
  system,
}

/// Everything we could learn about the process that owns a port.
class ProcessDetails {
  const ProcessDetails({
    required this.pid,
    required this.name,
    this.exePath,
    this.commandLine,
    this.cwd,
    this.startStamp,
    this.startedAt,
    this.parentPid,
    this.parentName,
    this.parentCommandLine,
    this.services = const [],
    this.restricted = false,
  });

  final int pid;

  /// Image name, e.g. `node.exe`.
  final String name;
  final String? exePath;
  final String? commandLine;

  /// The process's current working directory.
  final String? cwd;

  /// Opaque OS creation stamp. Together with [pid] it identifies one process
  /// instance, which guards against acting on a recycled pid.
  final int? startStamp;
  final DateTime? startedAt;

  final int? parentPid;
  final String? parentName;
  final String? parentCommandLine;

  /// Display names of the Windows services hosted by this process.
  final List<String> services;

  /// True when the OS refused to let us inspect the process (it belongs to
  /// another user or to the system and we are not elevated).
  final bool restricted;

  String? get exeDirectory => exePath == null ? null : p.windows.dirname(exePath!);
}

/// The project a process appears to belong to.
class ProjectInfo {
  const ProjectInfo({
    required this.name,
    required this.root,
    required this.marker,
  });

  final String name;

  /// Directory the project was recognised in.
  final String root;

  /// What identified it, e.g. `package.json`, or `folder` when the name is
  /// just the working directory's name.
  final String marker;

  /// False when the name is only a folder name rather than a declared one.
  bool get isDeclared => marker != folderMarker;

  static const folderMarker = 'folder';
}

/// What opened the port: the framework if we can tell, else the runtime or
/// program.
class TechInfo {
  const TechInfo({required this.name, this.via, this.runtime, this.icon});

  /// Headline, e.g. `Vue`, `Django`, `PostgreSQL`, `Node.js`.
  final String name;

  /// The server or tool actually listening when it differs from [name],
  /// e.g. `Vite` for a Vue app.
  final String? via;

  /// Language runtime, e.g. `Node.js`, when it differs from [name].
  final String? runtime;

  /// Key into the UI's icon table.
  final String? icon;

  /// Secondary line: `Vite · Node.js`.
  String get stack => [?via, ?runtime].join(' · ');
}

/// One row in the list: a port, the process that holds it open, and what we
/// inferred about that process.
class PortEntry {
  PortEntry({
    required this.protocol,
    required this.port,
    required this.addresses,
    required this.process,
    required this.tech,
    required this.category,
    this.openedAt,
    this.project,
  });

  final Protocol protocol;
  final int port;

  /// Local addresses the port is bound on, e.g. `0.0.0.0` and `::`.
  final List<String> addresses;

  /// When the socket was bound.
  final DateTime? openedAt;

  final ProcessDetails process;
  final TechInfo tech;
  final ProjectInfo? project;
  final PortCategory category;

  String get id => '${protocol.name}:$port:${process.pid}';

  /// The folder the process is running in, falling back to the project root
  /// and then to where the executable lives.
  String? get folder => process.cwd ?? project?.root ?? process.exeDirectory;

  /// True when [folder] is only the executable's location.
  bool get folderIsExeDirectory => process.cwd == null && project == null;

  /// True when every bound address is a loopback address.
  bool get isLocalOnly =>
      addresses.isNotEmpty &&
      addresses.every((a) => a.startsWith('127.') || a == '::1');

  /// True when bound on a wildcard address, i.e. reachable from the network.
  bool get isAllInterfaces => addresses.any((a) => a == '0.0.0.0' || a == '::');

  /// Lower-cased text the filter box matches against.
  late final String searchText = [
    '$port',
    ':$port',
    protocol.label,
    ...addresses,
    process.name,
    'pid:${process.pid}',
    '${process.pid}',
    tech.name,
    ?tech.via,
    ?tech.runtime,
    ?project?.name,
    ?folder,
    ?process.commandLine,
    ...process.services,
  ].join('\n').toLowerCase();
}

enum KillResult {
  killed,

  /// The process had already exited (or its pid now belongs to another one).
  notFound,
  accessDenied,
  failed,
}
