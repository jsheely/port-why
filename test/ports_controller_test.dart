import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:port_why/src/data/favorites_store.dart';
import 'package:port_why/src/models.dart';
import 'package:port_why/src/state/ports_controller.dart';

import 'support.dart';

void main() {
  late FakePortRepository repository;
  late PortsController controller;

  List<int> ports() => [for (final e in controller.visible) e.port];

  Future<void> load(List<PortEntry> entries, {int? ownPid}) async {
    repository = FakePortRepository(entries);
    controller = PortsController(repository, ownPid: ownPid);
    addTearDown(controller.dispose);
    await controller.refresh();
  }

  test('lists ports highest first by default', () async {
    await load([entry(port: 3000), entry(port: 8080), entry(port: 443), entry(port: 5173)]);
    expect(ports(), [8080, 5173, 3000, 443]);
    expect(controller.sortColumn, SortColumn.port);
    expect(controller.ascending, isFalse);
  });

  group('filter', () {
    setUp(
      () => load([
        entry(port: 5173, project: 'shop', tech: 'Vue', via: 'Vite', cwd: r'C:\work\shop'),
        entry(port: 8000, pid: 200, name: 'python.exe', project: 'api', tech: 'FastAPI'),
        entry(port: 5432, pid: 300, name: 'postgres.exe', tech: 'PostgreSQL'),
        entry(port: 445, pid: 4, name: 'System', tech: 'Windows kernel', category: PortCategory.system),
      ]),
    );

    test('matches the port number', () {
      controller.query = '5432';
      expect(ports(), [5432]);
    });

    test('matches project, framework, process name and folder, ignoring case', () {
      for (final (query, expected) in [
        ('SHOP', 5173),
        ('vite', 5173),
        ('fastapi', 8000),
        ('python.exe', 8000),
        (r'c:\work\shop', 5173),
        ('postgres', 5432),
      ]) {
        controller.query = query;
        expect(ports(), [expected], reason: 'query "$query"');
      }
    });

    test('every word must match', () {
      controller.query = 'node 51';
      expect(ports(), [5173]);
      controller.query = 'node 8000';
      expect(ports(), isEmpty);
    });

    test('an empty query shows everything again', () {
      controller.query = 'shop';
      controller.query = '   ';
      expect(ports(), [8000, 5432, 5173, 445]);
    });

    test('scope narrows to a category', () {
      controller.scope = ScopeFilter.projects;
      expect(ports(), [8000, 5173]);
      controller.scope = ScopeFilter.apps;
      expect(ports(), [5432]);
      controller.scope = ScopeFilter.system;
      expect(ports(), [445]);
    });

    test('counts say what each scope would show under the text filter', () {
      expect(controller.counts, {
        ScopeFilter.all: 4,
        ScopeFilter.projects: 2,
        ScopeFilter.apps: 1,
        ScopeFilter.system: 1,
      });
      controller.query = 'python';
      expect(controller.counts[ScopeFilter.all], 1);
      expect(controller.counts[ScopeFilter.projects], 1);
      expect(controller.counts[ScopeFilter.apps], 0);
    });

    test('pid: prefix finds a process without matching port numbers', () {
      controller.query = 'pid:300';
      expect(ports(), [5432]);
    });
  });

  group('sorting', () {
    test('choosing the same column again flips it', () async {
      await load([entry(port: 1), entry(port: 3), entry(port: 2)]);
      controller.sortBy(SortColumn.port);
      expect(ports(), [1, 2, 3]);
      controller.sortBy(SortColumn.port);
      expect(ports(), [3, 2, 1]);
    });

    test('names sort A to Z first, and rows without one go last either way', () async {
      await load([
        entry(port: 1, project: 'zeta'),
        entry(port: 2),
        entry(port: 3, project: 'Alpha'),
      ]);
      controller.sortBy(SortColumn.project);
      expect(ports(), [3, 1, 2]);
      controller.sortBy(SortColumn.project);
      expect(ports(), [1, 3, 2]);
    });

    test('opened sorts most recent first', () async {
      final noon = DateTime(2026, 10, 11, 12);
      await load([
        entry(port: 1, openedAt: noon.subtract(const Duration(hours: 3))),
        entry(port: 2, openedAt: noon),
        entry(port: 3),
        entry(port: 4, openedAt: noon.subtract(const Duration(minutes: 5))),
      ]);
      controller.sortBy(SortColumn.opened);
      expect(ports(), [2, 4, 1, 3]);
    });

    test('ties keep the default port order', () async {
      await load([
        entry(port: 10, tech: 'Vue'),
        entry(port: 30, tech: 'Vue'),
        entry(port: 20, tech: 'Vue'),
      ]);
      controller.sortBy(SortColumn.tech);
      expect(ports(), [30, 20, 10]);
    });
  });

  group('favorites', () {
    test('default to the usual dev ports and report who holds them', () async {
      await load([entry(port: 3000, pid: 7), entry(port: 9000, pid: 8)]);
      expect(controller.favorites, [3000, 5173, 8080]);
      expect(controller.holdersOf(3000).single.process.pid, 7);
      expect(controller.holdersOf(8080), isEmpty);
      // Filtering the list does not make a held port look free.
      controller.query = '9000';
      expect(controller.holdersOf(3000), hasLength(1));
    });

    test('are kept in order and saved as they change', () async {
      final store = MemoryFavoritesStore();
      controller = PortsController(FakePortRepository([]), favorites: store);
      addTearDown(controller.dispose);
      controller
        ..setFavorite(4200, true)
        ..setFavorite(4200, true)
        ..setFavorite(8080, false)
        ..setFavorite(70000, true);
      expect(controller.favorites, [3000, 4200, 5173]);
      expect(controller.isFavorite(4200), isTrue);
      expect(store.load(), [3000, 4200, 5173]);
    });

    test('saved ones replace the defaults, even when there are none', () {
      for (final saved in [<int>[], [9229, 80]]) {
        final restored = PortsController(
          FakePortRepository([]),
          favorites: MemoryFavoritesStore(saved),
        );
        addTearDown(restored.dispose);
        expect(restored.favorites, [...saved]..sort());
      }
    });

    test('survive in a file, and a mangled file means the defaults', () {
      final sandbox = Sandbox();
      addTearDown(sandbox.dispose);
      final store = FileFavoritesStore(p.join(sandbox.root, 'Port Why', 'favorites.json'));
      expect(store.load(), isNull);
      store.save([3000, 8443]);
      expect(store.load(), [3000, 8443]);
      File(store.path).writeAsStringSync('{not json');
      expect(store.load(), isNull);
    });
  });

  group('UDP', () {
    test('is left out until asked for', () async {
      await load([entry(port: 80), entry(port: 5353, protocol: Protocol.udp)]);
      expect(ports(), [80]);
      controller.includeUdp = true;
      await controller.refresh();
      expect(ports(), [5353, 80]);
      expect(repository.scans.last.includeUdp, isTrue);
    });
  });

  group('kill', () {
    test('kills, then rescans so the port is gone', () async {
      await load([entry(port: 3000, pid: 7), entry(port: 3001, pid: 7), entry(port: 9000, pid: 8)]);
      final target = controller.visible.firstWhere((e) => e.port == 3000);
      expect([for (final e in controller.portsSharingProcess(target)) e.port], [3001]);

      expect(await controller.kill(target), KillResult.killed);
      expect(repository.killed.single.process.pid, 7);
      expect(ports(), [9000]);
    });

    test('a refused kill leaves the list intact', () async {
      await load([entry(port: 3000, pid: 7)]);
      repository.killResult = KillResult.accessDenied;
      expect(await controller.kill(controller.visible.single), KillResult.accessDenied);
      expect(ports(), [3000]);
    });

    test('is blocked for the kernel, critical processes and the app itself', () async {
      await load([
        entry(port: 445, pid: 4, name: 'System'),
        entry(port: 49664, pid: 900, name: 'lsass.exe'),
        entry(port: 50000, pid: 4242, name: 'port_why.exe'),
        entry(port: 3000, pid: 7, name: 'node.exe'),
      ], ownPid: 4242);
      String? reason(int port) => controller.killBlockedReason(
        controller.visible.firstWhere((e) => e.port == port),
      );
      expect(reason(445), isNotNull);
      expect(reason(49664), contains('lsass.exe'));
      expect(reason(50000), contains('Port Why'));
      expect(reason(3000), isNull);
    });
  });

  group('WSL and containers', () {
    const postgres = ContainerInfo(
      id: 'aaaa',
      name: 'shop-postgres-1',
      image: 'postgres:18',
      composeProject: 'shop',
    );
    PortEntry row(int port) => controller.visible.firstWhere((e) => e.port == port);

    setUp(
      () => load([
        entry(port: 5432, pid: 1187, name: 'docker-proxy', tech: 'PostgreSQL', distro: 'dev', container: postgres),
        entry(port: 5433, pid: 1190, name: 'docker-proxy', tech: 'PostgreSQL', distro: 'dev', container: postgres),
        // Linux pid 1, which on Windows would be off limits.
        entry(port: 8080, pid: 1, name: 'node', distro: 'dev', cwd: '/home/me/shop', hostCwd: r'\\wsl.localhost\dev\home\me\shop'),
        // Same pid number as the Linux process above, but a Windows process.
        entry(port: 9000, pid: 1, name: 'weird.exe'),
        // A relayed port nothing could be found behind.
        entry(port: 7000, pid: 54036, name: 'wslrelay.exe', tech: 'WSL'),
      ]),
    );

    test('a Linux process may be killed whatever its pid', () {
      expect(controller.killBlockedReason(row(8080)), isNull);
      expect(controller.killBlockedReason(row(5432)), isNull);
      expect(controller.killBlockedReason(row(9000)), contains('kernel'));
    });

    test('the shared WSL relay itself is never offered for killing', () {
      expect(controller.killBlockedReason(row(7000)), contains('relay for every WSL port'));
    });

    test('ports are grouped by container, not by forwarder pid', () {
      expect([for (final e in controller.portsSharingProcess(row(5432))) e.port], [5433]);
      // A Windows pid and a Linux pid that happen to match are unrelated.
      expect(controller.portsSharingProcess(row(8080)), isEmpty);
    });

    test('the folder to open is the Windows view of the Linux one', () {
      expect(row(8080).folder, r'\\wsl.localhost\dev\home\me\shop');
      // A bare Linux path is never handed to Explorer.
      expect(row(5432).folder, isNull);
    });

    test('filtering finds them by distribution, container, image and kind', () {
      for (final (query, expected) in [
        ('wsl', [8080, 7000, 5433, 5432]),
        ('docker', [5433, 5432]),
        ('shop-postgres', [5433, 5432]),
        ('postgres:18', [5433, 5432]),
        ('dev node', [8080]),
        ('/home/me', [8080]),
      ]) {
        controller.query = query;
        expect(ports(), expected, reason: 'query "$query"');
      }
    });

    test('stopping a container removes every port it published', () async {
      expect(await controller.kill(row(5432)), KillResult.killed);
      expect(ports(), [9000, 8080, 7000]);
    });
  });

  group('refresh', () {
    test('a manual rescan asks for fresh detection, polling does not', () async {
      await load([entry()]);
      expect(repository.scans.single.fresh, isFalse);
      await controller.refresh(fresh: true);
      expect(repository.scans.last.fresh, isTrue);
    });

    test('a request made mid-scan triggers one more scan instead of being lost', () async {
      await load([entry(port: 1)]);
      final before = repository.scans.length;
      final first = controller.refresh();
      // Arrives while the scan above is still running.
      repository.entries = [entry(port: 2)];
      final second = controller.refresh();
      await Future.wait([first, second]);
      expect(repository.scans.length, before + 2);
      expect(ports(), [2]);
    });

    test('reports a failed scan and recovers on the next', () async {
      await load([entry(port: 1)]);
      final failing = _ThrowingRepository();
      final broken = PortsController(failing);
      addTearDown(broken.dispose);
      await broken.refresh();
      expect(broken.error, isA<StateError>());
      expect(broken.isLoading, isFalse);

      failing.fail = false;
      await broken.refresh();
      expect(broken.error, isNull);
      expect(broken.visible.single.port, 7);
    });

    test('opening a folder goes to the repository', () async {
      await load([entry(cwd: r'C:\work\shop')]);
      expect(await controller.openFolder(controller.visible.single), isTrue);
      expect(repository.openedFolders, [r'C:\work\shop']);
    });
  });
}

class _ThrowingRepository extends FakePortRepository {
  _ThrowingRepository() : super([entry(port: 7)]);

  bool fail = true;

  @override
  Future<List<PortEntry>> scan({bool includeUdp = false, bool fresh = false}) =>
      fail ? Future.error(StateError('no access')) : super.scan();
}
