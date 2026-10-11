import 'package:flutter_test/flutter_test.dart';
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
