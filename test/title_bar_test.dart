import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:port_why/src/ui/theme.dart';
import 'package:port_why/src/ui/title_bar.dart';

void main() {
  const channel = MethodChannel('port_why/window');
  late List<String> asked;

  /// Where the frame last said its controls are: four edges for each.
  late List<double> controls;

  Future<void> pumpFrame(WidgetTester tester, {Widget page = const SizedBox()}) async {
    asked = [];
    controls = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setControls') {
        controls = call.arguments as List<double>;
      } else {
        asked.add(call.method);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        builder: (context, child) => WindowFrame(child: child!),
        home: page,
      ),
    );
  }

  /// What the runner sends when the window is maximized or restored.
  Future<void> reportMaximized(WidgetTester tester, bool isMaximized) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('maximized', isMaximized)),
      (_) {},
    );
    await tester.pump();
  }

  testWidgets('the buttons ask the runner to minimize, maximize and close', (tester) async {
    await pumpFrame(tester);
    await tester.tap(find.bySemanticsLabel('Minimize'));
    await tester.tap(find.bySemanticsLabel('Maximize'));
    await tester.tap(find.bySemanticsLabel('Close'));
    expect(asked, ['minimize', 'toggleMaximize', 'close']);
  });

  testWidgets('the middle button offers to restore a maximized window', (tester) async {
    await pumpFrame(tester);
    await reportMaximized(tester, true);
    expect(find.bySemanticsLabel('Maximize'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Restore'));
    expect(asked, ['toggleMaximize']);

    await reportMaximized(tester, false);
    expect(find.bySemanticsLabel('Maximize'), findsOneWidget);
  });

  testWidgets('the page is told to keep clear of the title bar', (tester) async {
    late EdgeInsets padding;
    await pumpFrame(
      tester,
      page: Builder(
        builder: (context) {
          padding = MediaQuery.paddingOf(context);
          return const SizedBox();
        },
      ),
    );
    expect(padding.top, TitleBar.height);
    // The buttons sit over the page rather than pushing it down.
    expect(tester.getTopRight(find.bySemanticsLabel('Close')), tester.getTopRight(find.byType(MaterialApp)));
  });

  testWidgets('the runner is told what in the title bar is clicked, not dragged', (tester) async {
    Widget page({required double left}) => Stack(
      children: [
        Positioned(left: left, top: 6, width: 200, height: 32, child: const TitleBarControl(child: SizedBox())),
        // Below the title bar, so no business of the runner's.
        const Positioned(left: 0, top: 100, width: 50, height: 50, child: TitleBarControl(child: SizedBox())),
      ],
    );

    await pumpFrame(tester, page: page(left: 100));
    final buttons = tester.getRect(find.byType(TitleBar));
    expect(buttons.size, const Size(TitleBar.buttonsWidth, TitleBar.height));
    expect(controls, [
      100, 6, 300, 38,
      buttons.left, buttons.top, buttons.right, buttons.bottom,
    ]);

    // It hears again when one moves.
    await pumpFrame(tester, page: page(left: 140));
    await tester.pump();
    expect(controls.sublist(0, 4), [140, 6, 340, 38]);
  });
}
