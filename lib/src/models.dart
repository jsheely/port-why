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
    this.distro,
    this.hostCwd,
    this.container,
  });

  /// The process id, in its own pid namespace: a Linux pid when [distro] is
  /// set. Zero when a container is known to own the port but its process is
  /// not visible to us.
  final int pid;

  /// Image name, e.g. `node.exe`.
  final String name;

  /// Executable, command line and working directory as the process itself
  /// sees them. For a process in WSL these are Linux paths.
  final String? exePath;
  final String? commandLine;

  /// The process's current working directory.
  final String? cwd;

  /// The WSL distribution the process runs in, or null for a Windows process.
  final String? distro;

  /// [cwd] as a path Windows can open (`\\wsl.localhost\Ubuntu\home\me\app`).
  /// Null when it has no such path, as inside a container's own filesystem.
  final String? hostCwd;

  /// The container the process belongs to, if any.
  final ContainerInfo? container;

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

  bool get isInWsl => distro != null;

  String? get exeDirectory => exePath == null ? null : p.windows.dirname(exePath!);
}

/// A container that owns a port, as reported by the Docker engine.
class ContainerInfo {
  const ContainerInfo({
    required this.id,
    required this.name,
    required this.image,
    this.composeProject,
    this.directory,
  });

  final String id;
  final String name;
  final String image;

  /// The Docker Compose project the container was started as part of.
  final String? composeProject;

  /// The Compose project's folder, as a path Windows can open.
  final String? directory;
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

  /// The project is a Docker Compose project, named by the container's labels.
  static const composeMarker = 'docker compose';
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

  String get id => '${protocol.name}:$port:$ownerKey';

  /// Identifies what would be stopped by killing this row: a container, a
  /// process inside a WSL distribution, or a Windows process.
  String get ownerKey {
    final container = process.container;
    if (container != null) return 'container:${container.id}';
    final distro = process.distro;
    return distro == null ? '${process.pid}' : 'wsl:$distro:${process.pid}';
  }

  /// A folder Windows can open: where the process is running, falling back to
  /// the project root and then to where the executable lives.
  String? get folder {
    final candidate = process.isInWsl
        // Linux paths mean nothing to Explorer; only the translated ones do.
        ? process.hostCwd ?? project?.root
        : process.cwd ?? project?.root ?? process.exeDirectory;
    return candidate == null || candidate.isEmpty ? null : candidate;
  }

  /// True when [folder] is only the executable's location.
  bool get folderIsExeDirectory =>
      !process.isInWsl && process.cwd == null && project == null;

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
    ?process.cwd,
    ?process.commandLine,
    ...process.services,
    if (process.distro case final distro?) ...['wsl', distro],
    if (process.container case final container?) ...[
      'docker',
      container.name,
      container.image,
    ],
  ].join('\n').toLowerCase();
}

enum KillResult {
  killed,

  /// The process had already exited (or its pid now belongs to another one).
  notFound,
  accessDenied,
  failed,
}
