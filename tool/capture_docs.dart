// Render the real app with demo data at 3x resolution (Windows fonts required).
// Run from the repository root: flutter test tool/capture_docs.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:port_why/src/app.dart';
import 'package:port_why/src/data/favorites_store.dart';

import 'demo.dart';

void main() {
  testWidgets('render documentation screenshot', (tester) async {
    await tester.runAsync(() async {
      // Widget tests otherwise substitute a test font for every real typeface.
      final fonts =
          jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
      for (final family in fonts) {
        final loader = FontLoader(family['family'] as String);
        for (final font in family['fonts'] as List) {
          loader.addFont(rootBundle.load(font['asset'] as String));
        }
        await loader.load();
      }
      final windows = Platform.environment['WINDIR'] ?? r'C:\Windows';
      for (final font in {
        'Bahnschrift': 'bahnschrift.ttf',
        'Cascadia Mono': 'CascadiaMono.ttf',
        'Segoe UI': 'segoeui.ttf',
      }.entries) {
        final bytes = await File('$windows/Fonts/${font.value}').readAsBytes();
        await (FontLoader(
          font.key,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    });
    tester.view.physicalSize = const Size(1264, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: PortWhyApp(
          repository: DemoPortRepository(),
          favorites: MemoryFavoritesStore(),
          drawsWindowButtons: true,
        ),
      ),
    );
    await tester.pump();
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(tester.takeException(), isNull);
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('docs/screenshot.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
