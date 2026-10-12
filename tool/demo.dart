// Port Why with made-up ports, for screenshots and for trying the UI out
// without showing what is running on this machine:
//
//   flutter run -t tool/demo.dart
//
// Nothing here scans, kills or opens anything real.
import 'package:flutter/material.dart';
import 'package:port_why/src/app.dart';
import 'package:port_why/src/data/favorites_store.dart';
import 'package:port_why/src/data/port_repository.dart';
import 'package:port_why/src/models.dart';

void main() {
  runApp(
    PortWhyApp(
      repository: DemoPortRepository(),
      favorites: MemoryFavoritesStore(),
    ),
  );
}

class DemoPortRepository implements PortRepository {
  final _started = DateTime.now();
  final _stopped = <String>{};

  @override
  bool get isSupported => true;

  // The made-up machine is a Windows one, whatever this is run on.
  @override
  HostOs get os => HostOs.windows;

  @override
  Future<List<PortEntry>> scan({bool includeUdp = false, bool fresh = false}) async => [
    for (final entry in _entries(_started))
      if ((includeUdp || entry.protocol == Protocol.tcp) &&
          !_stopped.contains(entry.ownerKey))
        entry,
  ];

  @override
  Future<KillResult> kill(PortEntry entry) async {
    _stopped.add(entry.ownerKey);
    return KillResult.killed;
  }

  @override
  Future<bool> openFolder(String directory) async => true;
}

const _local = ['127.0.0.1'];
const _localBoth = ['127.0.0.1', '::1'];
const _all = ['0.0.0.0', '::'];

List<PortEntry> _entries(DateTime now) {
  DateTime ago({int days = 0, int hours = 0, int minutes = 0}) =>
      now.subtract(Duration(days: days, hours: hours, minutes: minutes));

  PortEntry project({
    required int port,
    required int pid,
    required String exe,
    required String commandLine,
    required String name,
    required String root,
    required String marker,
    required TechInfo tech,
    required DateTime openedAt,
    List<String> addresses = _local,
    String parent = 'pwsh.exe',
  }) => PortEntry(
    protocol: Protocol.tcp,
    port: port,
    addresses: addresses,
    openedAt: openedAt,
    process: ProcessDetails(
      pid: pid,
      name: exe.split(r'\').last,
      exePath: exe,
      commandLine: commandLine,
      cwd: root,
      startedAt: openedAt.subtract(const Duration(seconds: 3)),
      parentPid: pid - 212,
      parentName: parent,
    ),
    tech: tech,
    project: ProjectInfo(name: name, root: root, marker: marker),
    category: PortCategory.project,
  );

  PortEntry app({
    required int port,
    required int pid,
    required String exe,
    required TechInfo tech,
    required DateTime openedAt,
    String? commandLine,
    List<String> addresses = _local,
    Protocol protocol = Protocol.tcp,
  }) => PortEntry(
    protocol: protocol,
    port: port,
    addresses: addresses,
    openedAt: openedAt,
    process: ProcessDetails(
      pid: pid,
      name: exe.split(r'\').last,
      exePath: exe,
      commandLine: commandLine ?? '"$exe"',
      startedAt: openedAt.subtract(const Duration(seconds: 8)),
      parentPid: 9120,
      parentName: 'explorer.exe',
    ),
    tech: tech,
    category: PortCategory.app,
  );

  PortEntry system({
    required int port,
    required int pid,
    required String name,
    required TechInfo tech,
    List<String> services = const [],
    List<String> addresses = _all,
    Protocol protocol = Protocol.tcp,
  }) => PortEntry(
    protocol: protocol,
    port: port,
    addresses: addresses,
    openedAt: ago(days: 3, hours: 4),
    process: ProcessDetails(
      pid: pid,
      name: name,
      services: services,
      restricted: true,
    ),
    tech: tech,
    category: PortCategory.system,
  );

  const node = r'C:\Program Files\nodejs\node.exe';

  return [
    project(
      port: 5173,
      pid: 18244,
      exe: node,
      commandLine:
          r'node C:\dev\storefront\node_modules\vite\bin\vite.js --port 5173',
      name: 'storefront',
      root: r'C:\dev\storefront',
      marker: 'package.json',
      tech: const TechInfo(
        name: 'Vue',
        via: 'Vite',
        runtime: 'Node.js',
        icon: 'vuedotjs',
      ),
      openedAt: ago(minutes: 12),
      addresses: _localBoth,
    ),
    project(
      port: 3000,
      pid: 22916,
      exe: node,
      commandLine:
          r'node C:\dev\marketing-site\node_modules\next\dist\bin\next dev',
      name: 'marketing-site',
      root: r'C:\dev\marketing-site',
      marker: 'package.json',
      tech: const TechInfo(name: 'Next.js', runtime: 'Node.js', icon: 'nextdotjs'),
      openedAt: ago(hours: 2, minutes: 5),
      addresses: _all,
    ),
    project(
      port: 8000,
      pid: 14088,
      exe: r'C:\dev\orders-api\.venv\Scripts\python.exe',
      commandLine: 'python -m uvicorn app.main:app --reload --port 8000',
      name: 'orders-api',
      root: r'C:\dev\orders-api',
      marker: 'pyproject.toml',
      tech: const TechInfo(
        name: 'FastAPI',
        via: 'Uvicorn',
        runtime: 'Python',
        icon: 'fastapi',
      ),
      openedAt: ago(minutes: 47),
    ),
    project(
      port: 5080,
      pid: 9764,
      exe: r'C:\dev\billing\src\Billing.Api\bin\Debug\net10.0\Billing.Api.exe',
      commandLine: 'dotnet run --project src/Billing.Api',
      name: 'Billing.Api',
      root: r'C:\dev\billing\src\Billing.Api',
      marker: 'Billing.Api.csproj',
      tech: const TechInfo(name: 'ASP.NET Core', runtime: '.NET', icon: 'dotnet'),
      openedAt: ago(hours: 5, minutes: 31),
      parent: 'dotnet.exe',
    ),
    project(
      port: 8080,
      pid: 20352,
      exe: r'C:\dev\gateway\gateway.exe',
      commandLine: r'C:\dev\gateway\gateway.exe serve --config dev.yaml',
      name: 'gateway',
      root: r'C:\dev\gateway',
      marker: 'go.mod',
      tech: const TechInfo(name: 'Gin', runtime: 'Go', icon: 'gin'),
      openedAt: ago(days: 1, hours: 3),
      addresses: _all,
    ),
    project(
      port: 6006,
      pid: 25108,
      exe: node,
      commandLine:
          r'node C:\dev\design-system\node_modules\storybook\bin\index.cjs dev -p 6006',
      name: 'design-system',
      root: r'C:\dev\design-system',
      marker: 'package.json',
      tech: const TechInfo(
        name: 'Storybook',
        runtime: 'Node.js',
        icon: 'storybook',
      ),
      openedAt: ago(minutes: 3),
    ),
    project(
      port: 4000,
      pid: 11872,
      exe: r'C:\dev\search-indexer\target\debug\search-indexer.exe',
      commandLine: 'cargo run -- --listen 127.0.0.1:4000',
      name: 'search-indexer',
      root: r'C:\dev\search-indexer',
      marker: 'Cargo.toml',
      tech: const TechInfo(name: 'Actix Web', runtime: 'Rust', icon: 'actix'),
      openedAt: ago(hours: 1, minutes: 18),
      parent: 'cargo.exe',
    ),
    // A server running inside WSL.
    PortEntry(
      protocol: Protocol.tcp,
      port: 8001,
      addresses: _local,
      openedAt: ago(hours: 3, minutes: 40),
      process: ProcessDetails(
        pid: 4127,
        name: 'python3',
        exePath: '/home/dev/reports/.venv/bin/python3',
        commandLine: 'python3 manage.py runserver 0.0.0.0:8001',
        cwd: '/home/dev/reports',
        distro: 'Ubuntu',
        hostCwd: r'\\wsl.localhost\Ubuntu\home\dev\reports',
        startedAt: ago(hours: 3, minutes: 40),
      ),
      tech: const TechInfo(name: 'Django', runtime: 'Python', icon: 'django'),
      project: const ProjectInfo(
        name: 'reports',
        root: r'\\wsl.localhost\Ubuntu\home\dev\reports',
        marker: 'pyproject.toml',
      ),
      category: PortCategory.project,
    ),
    // Two containers from one Compose project.
    _container(
      port: 5432,
      id: '3f9a1c2b7d10',
      name: 'orders-db-1',
      image: 'postgres:17',
      tech: const TechInfo(name: 'PostgreSQL', icon: 'postgresql'),
      openedAt: ago(days: 2, hours: 6),
    ),
    _container(
      port: 6379,
      id: '8e44b0c6a2f5',
      name: 'orders-cache-1',
      image: 'redis:8-alpine',
      tech: const TechInfo(name: 'Redis', icon: 'redis'),
      openedAt: ago(days: 2, hours: 6),
    ),
    app(
      port: 11434,
      pid: 7340,
      exe: r'C:\Program Files\Ollama\ollama.exe',
      commandLine: r'"C:\Program Files\Ollama\ollama.exe" serve',
      tech: const TechInfo(name: 'Ollama', icon: 'ollama'),
      openedAt: ago(days: 1, hours: 9),
    ),
    app(
      port: 6463,
      pid: 15620,
      exe: r'C:\Program Files\Discord\Discord.exe',
      tech: const TechInfo(name: 'Discord', icon: 'discord'),
      openedAt: ago(hours: 7, minutes: 12),
    ),
    app(
      port: 57621,
      pid: 13376,
      exe: r'C:\Program Files\Spotify\Spotify.exe',
      tech: const TechInfo(name: 'Spotify', icon: 'spotify'),
      openedAt: ago(hours: 4, minutes: 2),
      addresses: _all,
    ),
    app(
      port: 5353,
      pid: 13376,
      exe: r'C:\Program Files\Spotify\Spotify.exe',
      tech: const TechInfo(name: 'Spotify', icon: 'spotify'),
      openedAt: ago(hours: 4, minutes: 2),
      addresses: _all,
      protocol: Protocol.udp,
    ),
    system(
      port: 445,
      pid: 4,
      name: 'System',
      tech: const TechInfo(name: 'Windows kernel', icon: 'windows'),
    ),
    system(
      port: 135,
      pid: 1284,
      name: 'svchost.exe',
      tech: const TechInfo(name: 'Service host', icon: 'windows'),
      services: ['Remote Procedure Call (RPC)', 'RPC Endpoint Mapper'],
    ),
    system(
      port: 5040,
      pid: 6012,
      name: 'svchost.exe',
      tech: const TechInfo(name: 'Service host', icon: 'windows'),
      services: ['Connected Devices Platform Service'],
    ),
  ];
}

PortEntry _container({
  required int port,
  required String id,
  required String name,
  required String image,
  required TechInfo tech,
  required DateTime openedAt,
}) => PortEntry(
  protocol: Protocol.tcp,
  port: port,
  addresses: const ['0.0.0.0', '::'],
  openedAt: openedAt,
  process: ProcessDetails(
    pid: 0,
    name: name,
    distro: 'Ubuntu',
    hostCwd: r'\\wsl.localhost\Ubuntu\home\dev\orders',
    container: ContainerInfo(
      id: id,
      name: name,
      image: image,
      composeProject: 'orders',
      directory: r'\\wsl.localhost\Ubuntu\home\dev\orders',
    ),
  ),
  tech: tech,
  project: const ProjectInfo(
    name: 'orders',
    root: r'\\wsl.localhost\Ubuntu\home\dev\orders',
    marker: ProjectInfo.composeMarker,
  ),
  category: PortCategory.project,
);
