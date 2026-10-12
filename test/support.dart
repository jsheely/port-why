import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:port_why/src/data/port_repository.dart';
import 'package:port_why/src/models.dart';

PortEntry entry({
  int port = 3000,
  Protocol protocol = Protocol.tcp,
  List<String> addresses = const ['127.0.0.1'],
  int pid = 100,
  String name = 'node.exe',
  String? project,
  String tech = 'Node.js',
  String? via,
  String? icon,
  String? cwd,
  String? commandLine,
  DateTime? openedAt,
  PortCategory? category,
  bool restricted = false,
  String? distro,
  String? hostCwd,
  ContainerInfo? container,
}) => PortEntry(
  protocol: protocol,
  port: port,
  addresses: addresses,
  openedAt: openedAt,
  process: ProcessDetails(
    pid: pid,
    name: name,
    cwd: cwd,
    commandLine: commandLine,
    startStamp: pid * 1000,
    restricted: restricted,
    distro: distro,
    hostCwd: hostCwd,
    container: container,
  ),
  tech: TechInfo(name: tech, via: via, icon: icon),
  project: project == null
      ? null
      : ProjectInfo(name: project, root: cwd ?? r'C:\work', marker: 'package.json'),
  category:
      category ?? (project == null ? PortCategory.app : PortCategory.project),
);

class FakePortRepository implements PortRepository {
  FakePortRepository(this.entries);

  List<PortEntry> entries;

  /// The samples in these tests are Windows processes unless a test says
  /// otherwise.
  @override
  HostOs os = HostOs.windows;
  KillResult killResult = KillResult.killed;
  bool folderExists = true;

  final killed = <PortEntry>[];
  final openedFolders = <String>[];
  final scans = <({bool includeUdp, bool fresh})>[];

  @override
  bool get isSupported => true;

  @override
  Future<List<PortEntry>> scan({bool includeUdp = false, bool fresh = false}) async {
    scans.add((includeUdp: includeUdp, fresh: fresh));
    return [
      for (final entry in entries)
        if (includeUdp || entry.protocol == Protocol.tcp) entry,
    ];
  }

  @override
  Future<KillResult> kill(PortEntry entry) async {
    killed.add(entry);
    if (killResult == KillResult.killed) {
      entries = [
        for (final other in entries)
          if (other.ownerKey != entry.ownerKey) other,
      ];
    }
    return killResult;
  }

  @override
  Future<bool> openFolder(String directory) async {
    openedFolders.add(directory);
    return folderExists;
  }
}

/// A scratch directory tree for detector tests, removed on [dispose].
class Sandbox {
  Sandbox() : root = Directory.systemTemp.createTempSync('port_why_test_').path;

  final String root;

  /// Stands in for the user's home directory.
  String get home => p.join(root, 'home');

  /// Environment that makes [home] the home directory, so the sandbox itself
  /// (which lives under the real AppData) is not off limits.
  Map<String, String> get environment => {
    'USERPROFILE': home,
    'SystemRoot': p.join(root, 'Windows'),
    'ProgramFiles': p.join(root, 'Program Files'),
    'LOCALAPPDATA': p.join(home, 'AppData', 'Local'),
    'APPDATA': p.join(home, 'AppData', 'Roaming'),
  };

  /// Creates a directory (and parents) under the sandbox and returns its path.
  String dir(String relative) {
    final path = p.normalize(p.join(root, relative));
    Directory(path).createSync(recursive: true);
    return path;
  }

  /// Writes a file under the sandbox and returns its path.
  String file(String relative, [String content = '']) {
    final path = p.normalize(p.join(root, relative));
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
    return path;
  }

  void dispose() {
    try {
      Directory(root).deleteSync(recursive: true);
    } on FileSystemException {
      // A straggling handle on Windows; the OS temp cleaner will get it.
    }
  }
}
