import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:port_why/src/app.dart';
import 'package:port_why/src/models.dart';
import 'package:port_why/src/state/ports_controller.dart';
import 'package:port_why/src/ui/tech_icon.dart';

import 'support.dart';

void main() {
  late FakePortRepository repository;

  List<PortEntry> sample() => [
    entry(
      port: 5173,
      pid: 4100,
      project: 'shop',
      tech: 'Vue',
      via: 'Vite',
      icon: 'vuedotjs',
      cwd: r'C:\work\shop',
      commandLine: r'node C:\work\shop\node_modules\vite\bin\vite.js',
    ),
    entry(port: 5174, pid: 4100, project: 'shop', tech: 'Vue', via: 'Vite', icon: 'vuedotjs', cwd: r'C:\work\shop'),
    entry(port: 8000, pid: 4200, name: 'python.exe', project: 'api', tech: 'FastAPI', icon: 'fastapi', cwd: r'C:\work\api'),
    entry(port: 5432, pid: 4300, name: 'postgres.exe', tech: 'PostgreSQL', icon: 'postgresql'),
    entry(port: 445, pid: 4, name: 'System', tech: 'Windows kernel', icon: 'windows', category: PortCategory.system, restricted: true),
  ];

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(PortWhyApp(repository: repository));
    await tester.pump();
  }

  /// Port numbers in the order they appear on screen, top to bottom.
  List<int> portsShown(WidgetTester tester) {
    final found = <(double, int)>[];
    for (final element in find.byType(Text).evaluate()) {
      final text = (element.widget as Text).data;
      final port = text == null ? null : int.tryParse(text);
      final isPortCell = (element.widget as Text).style?.fontWeight == FontWeight.w700;
      if (port != null && isPortCell) {
        found.add((tester.getTopLeft(find.byWidget(element.widget)).dy, port));
      }
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, port) in found) port];
  }

  Finder rowAction(int port, IconData icon) => find.descendant(
    of: find.byKey(ValueKey('tcp:$port:${repository.entries.firstWhere((e) => e.port == port).process.pid}')),
    matching: find.byIcon(icon),
  );

  setUp(() => repository = FakePortRepository(sample()));

  testWidgets('lists every port, highest first, with project and tech', (tester) async {
    await pumpApp(tester);
    expect(portsShown(tester), [8000, 5432, 5174, 5173, 445]);
    // Two rows, each showing "shop" as the project and again as the folder.
    expect(find.text('shop'), findsNWidgets(4));
    expect(find.text(r'C:\work'), findsNWidgets(3));
    expect(find.text('FastAPI'), findsOneWidget);
    expect(find.text('Vite'), findsNWidgets(2));
    expect(find.text('5 open ports held by 4 processes'), findsOneWidget);
    // Each row carries its tech icon.
    expect(find.byType(TechIcon), findsNWidgets(5));
    expect(find.byIcon(techGlyphs['vuedotjs']!.icon), findsNWidgets(2));
  });

  testWidgets('typing in the filter narrows the list', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.byType(TextField), 'shop');
    await tester.pump();
    expect(portsShown(tester), [5174, 5173]);
    expect(find.textContaining('Showing 2 of 5'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nothing-matches-this');
    await tester.pump();
    expect(portsShown(tester), isEmpty);
    expect(find.textContaining('No open port matches'), findsOneWidget);

    await tester.tap(find.text('Show all ports'));
    await tester.pump();
    expect(portsShown(tester), hasLength(5));
  });

  testWidgets('scope buttons filter by category', (tester) async {
    await pumpApp(tester);
    Finder scope(String label) => find.descendant(
      of: find.byType(SegmentedButton<ScopeFilter>),
      matching: find.textContaining(label),
    );
    // Each button carries the number of rows it would show.
    expect(scope('Projects  3'), findsOneWidget);
    await tester.tap(scope('Projects'));
    await tester.pump();
    expect(portsShown(tester), [8000, 5174, 5173]);
    await tester.tap(scope('System'));
    await tester.pump();
    expect(portsShown(tester), [445]);
  });

  testWidgets('clicking a column header re-sorts', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('PORT'));
    await tester.pump();
    expect(portsShown(tester), [445, 5173, 5174, 5432, 8000]);
    await tester.tap(find.text('PROJECT'));
    await tester.pump();
    // api, shop, shop, then the rows with no project.
    expect(portsShown(tester).take(3), [8000, 5174, 5173]);
  });

  testWidgets('a row expands to show the command line', (tester) async {
    await pumpApp(tester);
    expect(find.textContaining('vite.js'), findsNothing);
    await tester.tap(find.text('5173'));
    await tester.pump();
    expect(find.textContaining(r'node_modules\vite\bin\vite.js'), findsOneWidget);
    expect(find.textContaining('this machine only'), findsOneWidget);
  });

  testWidgets('open folder asks the repository for the working folder', (tester) async {
    await pumpApp(tester);
    await tester.tap(rowAction(8000, Icons.folder_open_rounded));
    await tester.pump();
    expect(repository.openedFolders, [r'C:\work\api']);
  });

  testWidgets('kill asks first, and cancelling kills nothing', (tester) async {
    await pumpApp(tester);
    await tester.tap(rowAction(5173, Icons.stop_circle_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Kill node.exe?'), findsOneWidget);
    // The other port held by the same process is called out.
    expect(find.textContaining('It also holds port 5174'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.killed, isEmpty);
    expect(portsShown(tester), hasLength(5));
  });

  testWidgets('confirming kills the process and its ports leave the list', (tester) async {
    await pumpApp(tester);
    await tester.tap(rowAction(5173, Icons.stop_circle_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kill process'));
    await tester.pumpAndSettle();

    expect(repository.killed.single.process.pid, 4100);
    expect(portsShown(tester), [8000, 5432, 445]);
    expect(find.textContaining('Port 5173 is free'), findsOneWidget);
  });

  testWidgets('a refused kill says so', (tester) async {
    repository.killResult = KillResult.accessDenied;
    await pumpApp(tester);
    await tester.tap(rowAction(5432, Icons.stop_circle_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kill process'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Windows refused'), findsOneWidget);
    expect(portsShown(tester), hasLength(5));
  });

  testWidgets('the kernel cannot be killed', (tester) async {
    await pumpApp(tester);
    final button = tester.widget<IconButton>(
      find.ancestor(
        of: rowAction(445, Icons.stop_circle_outlined),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('Ctrl+F focuses the filter and Esc clears it', (tester) async {
    await pumpApp(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue);

    await tester.enterText(find.byType(TextField), 'api');
    await tester.pump();
    expect(portsShown(tester), [8000]);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(portsShown(tester), hasLength(5));
    expect(field.controller!.text, isEmpty);
  });

  group('a port held by a Docker container in WSL', () {
    const api = ContainerInfo(
      id: 'a1b2c3d4e5f6',
      name: 'e2b-api-1',
      image: 'registry.example/e2b/api:v0.14',
      composeProject: 'e2b',
      directory: r'\\wsl.localhost\dev\opt\e2b',
    );

    setUp(() {
      repository.entries = [
        ...sample(),
        PortEntry(
          protocol: Protocol.tcp,
          port: 3000,
          addresses: const ['::1'],
          process: const ProcessDetails(
            pid: 1598,
            name: 'api',
            exePath: '/api',
            cwd: '/',
            commandLine: './api --port 3000',
            distro: 'dev',
            container: api,
          ),
          tech: const TechInfo(name: 'api', icon: 'docker'),
          project: const ProjectInfo(
            name: 'e2b',
            root: r'\\wsl.localhost\dev\opt\e2b',
            marker: ProjectInfo.composeMarker,
          ),
          category: PortCategory.project,
        ),
      ];
    });

    Finder action(IconData icon) => find.descendant(
      of: find.byKey(const ValueKey('tcp:3000:container:a1b2c3d4e5f6')),
      matching: find.byIcon(icon),
    );

    testWidgets('names the container, its project and its folder', (tester) async {
      await pumpApp(tester);
      expect(find.text('e2b-api-1 · Docker'), findsOneWidget);
      expect(find.text('docker compose'), findsOneWidget);
      // The Compose folder, leaf first, as Windows can open it.
      expect(find.text(r'\\wsl.localhost\dev\opt'), findsOneWidget);

      await tester.tap(find.text('3000'));
      await tester.pump();
      expect(find.textContaining('WSL distribution dev'), findsOneWidget);
      expect(find.textContaining('Docker container e2b-api-1'), findsOneWidget);
      expect(find.textContaining('Docker Compose project'), findsOneWidget);
    });

    testWidgets('opens the Compose folder', (tester) async {
      await pumpApp(tester);
      await tester.tap(action(Icons.folder_open_rounded));
      await tester.pump();
      expect(repository.openedFolders, [r'\\wsl.localhost\dev\opt\e2b']);
    });

    testWidgets('offers to stop the container rather than kill a process', (tester) async {
      await pumpApp(tester);
      await tester.tap(action(Icons.stop_circle_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Stop e2b-api-1?'), findsOneWidget);
      expect(find.textContaining('Docker container e2b-api-1 (e2b) in WSL (dev)'), findsOneWidget);

      await tester.tap(find.text('Stop container'));
      await tester.pumpAndSettle();
      expect(repository.killed.single.process.container, api);
      expect(find.textContaining('Stopped container e2b-api-1. Port 3000 is free.'), findsOneWidget);
      expect(portsShown(tester), isNot(contains(3000)));
    });
  });

  testWidgets('UDP ports appear only when the chip is on', (tester) async {
    repository.entries = [...sample(), entry(port: 5353, protocol: Protocol.udp, pid: 4400, name: 'mdns.exe')];
    await pumpApp(tester);
    expect(portsShown(tester), isNot(contains(5353)));
    await tester.tap(find.widgetWithText(FilterChip, 'UDP'));
    await tester.pumpAndSettle();
    expect(portsShown(tester), contains(5353));
    // With both protocols listed, rows are tagged with theirs.
    expect(find.text('TCP'), findsWidgets);
  });
}
