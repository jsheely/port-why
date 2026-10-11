// EXPERIMENT: temporary. Draws one primitive many times every frame, to learn
// what each costs on this renderer. Delete with the other experiment hooks.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'glass.dart';
import 'theme.dart';

final benchKind = Platform.environment['PW_BENCH'];

class BenchPage extends StatefulWidget {
  const BenchPage({super.key, required this.kind});
  final String kind;
  @override
  State<BenchPage> createState() => _BenchPageState();
}

class _BenchPageState extends State<BenchPage> with SingleTickerProviderStateMixin {
  final _tick = ValueNotifier<int>(0);
  late final Ticker _ticker = createTicker((_) => _tick.value++)..start();
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    // A small soft picture to stretch, standing in for a low-res frost.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const rect = Rect.fromLTWH(0, 0, 160, 100);
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(colors: [Neon.cyan, Neon.pink]).createShader(rect));
    _image = recorder.endRecording().toImageSync(160, 100);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Neon.abyss,
    child: CustomPaint(painter: _BenchPainter(widget.kind, _tick, _image!), size: Size.infinite),
  );
}

class _BenchPainter extends CustomPainter {
  _BenchPainter(this.kind, this.tick, this.image) : super(repaint: tick);
  final String kind;
  final ValueNotifier<int> tick;
  final ui.Image image;

  static const count = 100;

  @override
  void paint(Canvas canvas, Size size) {
    const shape = GlassBorder(cut: 14);
    final text = TextPainter(
      text: TextSpan(text: 'node.exe 127.0.0.1', style: mono.copyWith(fontSize: 13, color: Colors.white, shadows: kind == 'textshadow' ? neonGlow(Neon.cyan) : null)),
      textDirection: TextDirection.ltr,
    )..layout();
    for (var i = 0; i < count; i++) {
      final rect = Rect.fromLTWH(10.0 + (i % 10) * 124, 10.0 + (i ~/ 10) * 74, 116, 66);
      final a = Colors.white.withValues(alpha: 0.10);
      final b = Colors.white.withValues(alpha: 0.015);
      switch (kind) {
        case 'none':
          break;
        case 'solid':
          canvas.drawRect(rect, Paint()..color = a);
        case 'rrect':
          canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)), Paint()..color = a);
        case 'path':
          canvas.drawPath(shape.getOuterPath(rect), Paint()..color = a);
        case 'pathstroke':
          canvas.drawPath(shape.getOuterPath(rect), Paint()..color = a..style = PaintingStyle.stroke..strokeWidth = 1.2);
        case 'clipsolid':
          canvas..save()..clipPath(shape.getOuterPath(rect))..drawRect(rect, Paint()..color = a)..restore();
        case 'lin2':
          canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b]).createShader(rect));
        case 'lin2opaque':
          canvas.drawRect(rect, Paint()..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Neon.abyss, Neon.dusk]).createShader(rect));
        case 'lin3':
          canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b, a], stops: const [0, 0.5, 1]).createShader(rect));
        case 'linfast':
          canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [a, b]).createShader(rect));
        case 'linpath':
          canvas.drawPath(shape.getOuterPath(rect), Paint()..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b]).createShader(rect));
        case 'linstroke':
          canvas.drawPath(shape.getOuterPath(rect), Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [a, b, a], stops: const [0, 0.5, 1]).createShader(rect));
        case 'radial':
          canvas.drawRect(rect, Paint()..shader = RadialGradient(colors: [Neon.cyan.withValues(alpha: 0.4), Neon.cyan.withValues(alpha: 0)]).createShader(rect));
        case 'radialplus':
          canvas.drawRect(rect, Paint()..blendMode = BlendMode.plus..shader = RadialGradient(colors: [Neon.cyan.withValues(alpha: 0.4), Neon.cyan.withValues(alpha: 0)]).createShader(rect));
        case 'image':
          canvas.drawImageRect(image, const Rect.fromLTWH(0, 0, 160, 100), rect, Paint()..filterQuality = FilterQuality.low);
        case 'imageshader':
          final m = Matrix4.identity()..translateByDouble(rect.left, rect.top, 0, 1)..scaleByDouble(rect.width / 160, rect.height / 100, 1, 1);
          canvas.drawPath(shape.getOuterPath(rect), Paint()..shader = ui.ImageShader(image, TileMode.clamp, TileMode.clamp, m.storage, filterQuality: FilterQuality.low));
        case 'blur':
          canvas.drawRRect(RRect.fromRectAndRadius(rect.deflate(12), const Radius.circular(10)), Paint()..color = Neon.cyan..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        case 'blurouter':
          canvas.drawRRect(RRect.fromRectAndRadius(rect.deflate(12), const Radius.circular(10)), Paint()..color = Neon.cyan..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6));
        case 'blurpath':
          canvas.drawPath(shape.getOuterPath(rect.deflate(12)), Paint()..color = Neon.cyan..maskFilter = const MaskFilter.blur(BlurStyle.outer, 6));
        case 'text' || 'textshadow':
          text.paint(canvas, rect.topLeft);
      }
    }
    text.dispose();
  }

  @override
  bool shouldRepaint(_BenchPainter old) => true;
}
