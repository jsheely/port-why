import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:port_why/src/app.dart';
import 'package:port_why/src/data/favorites_store.dart';
import 'package:port_why/src/models.dart';
import 'package:port_why/src/state/ports_controller.dart';
import 'package:port_why/src/ui/tech_icon.dart';
import 'package:port_why/src/ui/title_bar.dart';

import 'support.dart';

/// Lets entrances, dialogs and toasts finish. The backdrop never stops moving,
/// so there is no waiting for the app to fall still.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

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

  /// A window wide enough for three cards abreast.
  void openWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpApp(WidgetTester tester) async {
    openWindow(tester);
    await tester.pumpWidget(PortWhyApp(repository: repository));
    await settle(tester);
  }

  /// Port numbers in reading order: along each row of cards, top row first.
  List<int> portsShown(WidgetTester tester) {
    final found = <(Offset, int)>[];
    for (final element in find.byType(Text).evaluate()) {
      final text = (element.widget as Text).data;
      final port = text == null ? null : int.tryParse(text);
      final isPortCell = (element.widget as Text).style?.fontWeight == FontWeight.w700;
      if (port != null && isPortCell) {
        found.add((tester.getTopLeft(find.byWidget(element.widget)), port));
      }
    }
    found.sort((a, b) {
      final byRow = a.$1.dy.compareTo(b.$1.dy);
      return byRow != 0 ? byRow : a.$1.dx.compareTo(b.$1.dx);
    });
    return [for (final (_, port) in found) port];
  }

  Finder rowAction(int port, IconData icon) => find.descendant(
    of: find.byKey(ValueKey('tcp:$port:${repository.entries.firstWhere((e) => e.port == port).process.pid}')),
    matching: find.byIcon(icon),
  );

  /// The port number on a card, which a favourite's chip shows too.
  Finder cardPort(int port) => find.descendant(
    of: find.byKey(ValueKey(repository.entries.firstWhere((e) => e.port == port).id)),
    matching: find.text('$port'),
  );

  Finder favorite(int port) => find.byKey(ValueKey('favorite:$port'));

  setUp(() => repository = FakePortRepository(sample()));

  testWidgets('lists every port, highest first, with project and tech', (tester) async {
    await pumpApp(tester);
    expect(portsShown(tester), [8000, 5432, 5174, 5173, 445]);
    // Two cards, each showing "shop" as the project and again as the folder,
    // and the favourite it holds.
    expect(find.text('shop'), findsNWidgets(5));
    expect(find.text(r'C:\work'), findsNWidgets(3));
    expect(find.text('FastAPI'), findsOneWidget);
    expect(find.text('Vite'), findsNWidgets(2));
    expect(find.text('5 open ports held by 4 processes'), findsOneWidget);
    // Each card carries its tech icon.
    expect(find.byType(TechIcon), findsNWidgets(5));
    expect(find.byIcon(techGlyphs['vuedotjs']!.icon), findsNWidgets(2));
  });

  testWidgets('cards sit as many abreast as the window has room for', (tester) async {
    Finder card(int port) => find.byKey(ValueKey('tcp:$port:${repository.entries.firstWhere((e) => e.port == port).process.pid}'));

    await pumpApp(tester);
    // Three to a row at this width, so the fourth starts the next row.
    expect(tester.getTopLeft(card(5432)).dy, tester.getTopLeft(card(8000)).dy);
    expect(tester.getTopLeft(card(5173)).dy, greaterThan(tester.getTopLeft(card(8000)).dy));
    expect(tester.getTopLeft(card(5173)).dx, tester.getTopLeft(card(8000)).dx);

    tester.view.physicalSize = const Size(520, 900);
    await settle(tester);
    expect(tester.getTopLeft(card(5432)).dy, greaterThan(tester.getTopLeft(card(8000)).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow window is one column of cards, with the search on a line of its own', (tester) async {
    repository.entries = [...sample(), entry(port: 135, pid: 1200, name: 'svchost.exe', tech: 'Windows service', category: PortCategory.system, restricted: true)];
    await pumpApp(tester);
    expect(tester.getRect(find.byType(TextField)).bottom, lessThan(TitleBar.height));
    await tester.enterText(find.byType(TextField), 'shop');
    await tester.tap(find.text('LIVE'));
    await tester.pump();

    // As narrow as the runner lets the window go.
    tester.view.physicalSize = const Size(424, 1200);
    await settle(tester);
    expect(tester.takeException(), isNull);
    // The search kept what was typed in it, and now runs the window's width
    // under the title bar.
    final search = tester.getRect(find.byType(TextField));
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'shop');
    expect(search.top, greaterThanOrEqualTo(TitleBar.height));
    expect(search.width, greaterThan(380));
    // The switches are still beside the window's buttons.
    expect(tester.getRect(find.text('PAUSED')).bottom, lessThan(TitleBar.height));
    expect(tester.getRect(find.byTooltip('Rescan everything (F5)')).right, lessThan(424 - TitleBar.buttonsWidth));

    expect(portsShown(tester), [5174, 5173]);
    expect(tester.getTopLeft(cardPort(5173)).dx, tester.getTopLeft(cardPort(5174)).dx);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(portsShown(tester), [8000, 5432, 5174, 5173, 445, 135]);
    expect(find.text('1 hidden'), findsOneWidget);

    // A card's details put each value under its label.
    await tester.tap(cardPort(8000));
    await settle(tester);
    expect(tester.getTopLeft(find.text(r'C:\work\api')).dy, greaterThan(tester.getBottomLeft(find.text('WORKING FOLDER')).dy - 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a port that opens later joins the deck', (tester) async {
    await pumpApp(tester);
    repository.entries = [...sample(), entry(port: 9229, pid: 4500, tech: 'Node.js', icon: 'nodedotjs')];
    // The next poll picks it up, and its entrance runs its course.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 3));
    expect(portsShown(tester).first, 9229);
    expect(find.text('6 open ports held by 5 processes'), findsOneWidget);
  });

  testWidgets('with reduced motion the app falls still', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    openWindow(tester);
    await tester.pumpWidget(PortWhyApp(repository: repository));
    await tester.pump();
    // Cards are simply there, with no entrance to sit through...
    expect(tester.getSize(find.byKey(const ValueKey('tcp:8000:4200'))).height, greaterThan(100));
    expect(tester.getTopLeft(find.text('8000')).dy, tester.getTopLeft(find.text('5174')).dy);
    // ...and nothing keeps asking for frames, which this would wait on for ever.
    await tester.pumpAndSettle();
    expect(portsShown(tester), hasLength(5));
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
    // Each segment carries the number of cards it would show.
    Finder scope(ScopeFilter scope, int count) =>
        find.textContaining(RegExp('^${scope.label}  $count\$'));
    await tester.tap(scope(ScopeFilter.projects, 3));
    await tester.pump();
    expect(portsShown(tester), [8000, 5174, 5173]);
    await tester.tap(scope(ScopeFilter.system, 1));
    await tester.pump();
    expect(portsShown(tester), [445]);
  });

  testWidgets('choosing a sort order re-sorts', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('PORT'));
    await tester.pump();
    expect(portsShown(tester), [445, 5173, 5174, 5432, 8000]);

    // The other orders are shut away until the pointer is over the sort bar.
    expect(tester.getSize(find.text('PROJECT')).width, greaterThan(0));
    expect(find.text('PROJECT').hitTestable(), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('SORT')));
    await settle(tester);
    await tester.tap(find.text('PROJECT'));
    await tester.pump();
    // api, shop, shop, then the rows with no project.
    expect(portsShown(tester).take(3), [8000, 5174, 5173]);
  });

  testWidgets('a card opens to show the command line', (tester) async {
    await pumpApp(tester);
    expect(find.textContaining('vite.js'), findsNothing);
    await tester.tap(cardPort(5173));
    await tester.pump();
    expect(find.textContaining(r'node_modules\vite\bin\vite.js'), findsOneWidget);
    expect(find.textContaining('this machine only'), findsOneWidget);

    await settle(tester);
    await tester.tap(find.byTooltip('Close details'));
    await settle(tester);
    expect(find.textContaining('vite.js'), findsNothing);
  });

  testWidgets("a path in a card's details can be copied", (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpApp(tester);
    await tester.tap(cardPort(5173));
    await settle(tester);
    await tester.tap(find.byTooltip('Copy working folder'));
    await settle(tester);
    expect(copied, [r'C:\work\shop']);
    expect(find.text('Copied the working folder.'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy command'));
    await settle(tester);
    expect(copied.last, r'node C:\work\shop\node_modules\vite\bin\vite.js');
    // Only what is known has a button.
    expect(find.byTooltip('Copy executable'), findsNothing);
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
    await settle(tester);
    expect(find.text('Kill node.exe?'), findsOneWidget);
    // The other port held by the same process is called out.
    expect(find.textContaining('It also holds port 5174'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(repository.killed, isEmpty);
    expect(portsShown(tester), hasLength(5));
  });

  testWidgets('confirming kills the process and its ports leave the list', (tester) async {
    await pumpApp(tester);
    await tester.tap(rowAction(5173, Icons.stop_circle_outlined));
    await settle(tester);
    await tester.tap(find.text('Kill process'));
    await settle(tester);

    expect(repository.killed.single.process.pid, 4100);
    expect(portsShown(tester), [8000, 5432, 445]);
    expect(find.textContaining('Port 5173 is free'), findsOneWidget);
  });

  testWidgets('a refused kill says so', (tester) async {
    repository.killResult = KillResult.accessDenied;
    await pumpApp(tester);
    await tester.tap(rowAction(5432, Icons.stop_circle_outlined));
    await settle(tester);
    await tester.tap(find.text('Kill process'));
    await settle(tester);
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

      await tester.tap(cardPort(3000));
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
      await settle(tester);
      expect(find.text('Stop e2b-api-1?'), findsOneWidget);
      expect(find.textContaining('Docker container e2b-api-1 (e2b) in WSL (dev)'), findsOneWidget);

      await tester.tap(find.text('Stop container'));
      await settle(tester);
      expect(repository.killed.single.process.container, api);
      expect(find.textContaining('Stopped container e2b-api-1. Port 3000 is free.'), findsOneWidget);
      expect(portsShown(tester), isNot(contains(3000)));
    });
  });

  group('favorites', () {
    testWidgets('start as the usual dev ports, saying what holds each', (tester) async {
      await pumpApp(tester);
      expect(favorite(3000), findsOneWidget);
      expect(favorite(8080), findsOneWidget);
      expect(find.descendant(of: favorite(5173), matching: find.text('shop')), findsOneWidget);
      expect(find.descendant(of: favorite(3000), matching: find.text('free')), findsOneWidget);
    });

    testWidgets('one that gets taken says by what', (tester) async {
      await pumpApp(tester);
      repository.entries = [...sample(), entry(port: 8080, pid: 4600, tech: 'Spring Boot')];
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.descendant(of: favorite(8080), matching: find.text('Spring Boot')), findsOneWidget);
    });

    testWidgets('clicking one shows only that port, and again shows them all', (tester) async {
      await pumpApp(tester);
      await tester.tap(favorite(5173));
      await tester.pump();
      expect(portsShown(tester), [5173]);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, ':5173');

      await tester.tap(favorite(5173));
      await tester.pump();
      expect(portsShown(tester), hasLength(5));
    });

    testWidgets('a port is added by number and dropped again', (tester) async {
      final store = MemoryFavoritesStore();
      openWindow(tester);
      await tester.pumpWidget(PortWhyApp(repository: repository, favorites: store));
      await settle(tester);

      await tester.tap(find.byTooltip('Watch another port'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'port'), '5432');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.descendant(of: favorite(5432), matching: find.text('PostgreSQL')), findsOneWidget);
      expect(store.load(), [3000, 5173, 5432, 8080]);
      // The box folds away again.
      expect(find.byType(TextField), findsOneWidget);

      // The line slid along to show the box, and takes no clicks until it stops.
      await settle(tester);
      await tester.tap(find.byTooltip('Stop watching port 3000'));
      await tester.pump();
      expect(favorite(3000), findsNothing);
      expect(store.load(), [5173, 5432, 8080]);
    });

    testWidgets("a card's star adds its port and takes it out", (tester) async {
      await pumpApp(tester);
      await tester.tap(rowAction(8000, Icons.star_outline_rounded));
      await tester.pump();
      expect(favorite(8000), findsOneWidget);
      await tester.tap(rowAction(8000, Icons.star_rounded));
      await tester.pump();
      expect(favorite(8000), findsNothing);
    });

    testWidgets('are remembered from the last run', (tester) async {
      openWindow(tester);
      await tester.pumpWidget(PortWhyApp(repository: repository, favorites: MemoryFavoritesStore([9000, 445])));
      await settle(tester);
      expect(favorite(445), findsOneWidget);
      expect(favorite(9000), findsOneWidget);
      expect(favorite(3000), findsNothing);
    });
  });

  testWidgets('UDP ports appear only when the chip is on', (tester) async {
    repository.entries = [...sample(), entry(port: 5353, protocol: Protocol.udp, pid: 4400, name: 'mdns.exe')];
    await pumpApp(tester);
    expect(portsShown(tester), isNot(contains(5353)));
    await tester.tap(find.text('UDP'));
    await settle(tester);
    expect(portsShown(tester), contains(5353));
    // With both protocols listed, cards are tagged with theirs.
    expect(find.text('TCP'), findsWidgets);
  });
}
