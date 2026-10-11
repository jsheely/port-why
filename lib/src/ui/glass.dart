import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'ambient.dart';
import 'theme.dart';

/// A pane of frosted glass: whatever is behind it shows through blurred, under
/// a faint tint, with a bright rim where light would catch the edge.
///
/// To fade a pane in or out, animate [strength] rather than wrapping it in an
/// [Opacity]. A backdrop filter inside an opacity layer can only see that
/// layer, so the blur would vanish for as long as the fade lasted.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.accent = Neon.cyan,
    this.radius = 16,
    this.cut = 0,
    this.blur = 22,
    this.tint = 0.46,
    this.strength = 1,
    this.emphasis = 0,
    this.pointer,
    this.overBackdrop = false,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;

  /// The colour the far edge of the rim glows in.
  final Color accent;
  final double radius;

  /// How much of the bottom-right corner is sliced off.
  final double cut;
  final double blur;

  /// How dark the glass itself is, from clear to opaque.
  final double tint;

  /// From 0, not there at all, to 1, fully formed.
  final double strength;

  /// From 0 to 1, how brightly the pane is lit: hovered, selected, announced.
  final double emphasis;

  /// Where the pointer is over the pane, which throws a soft light there.
  final ValueListenable<Offset?>? pointer;

  /// True when the pane lies straight on the backdrop, with nothing else ever
  /// passing behind it. It then shows a [Frost] in place of a real blur,
  /// which looks the same and costs far less. A pane that floats over other
  /// things has to blur them for real.
  final bool overBackdrop;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final shape = GlassBorder(radius: radius, cut: cut);
    final pane = CustomPaint(
      isComplex: expFlags.contains('complexhint'), // EXPERIMENT
      painter: _GlassPainter(
        accent: accent,
        shape: shape,
        tint: tint,
        strength: strength,
        emphasis: emphasis,
        pointer: pointer,
      ),
      // Ink has to land on top of the glass, not on the page far beneath it.
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child),
      ),
    );

    final Widget frosted;
    if (overBackdrop) {
      frosted = Stack(
        children: [
          if (strength > 0 && !expFlags.contains('nofrostlayer')) // EXPERIMENT
            Positioned.fill(child: Frost(shape: shape, opacity: strength)),
          pane,
        ],
      );
    } else {
      final sigma = expFlags.contains('noblur') ? 0.0 : blur * strength; // EXPERIMENT
      frosted = ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          enabled: sigma > 0,
          child: pane,
        ),
      );
    }
    return CustomPaint(
      painter: emphasis > 0
          ? _HaloPainter(
              accent: accent,
              shape: shape,
              glow: emphasis * strength,
            )
          : null,
      child: frosted,
    );
  }
}

/// The outline every pane shares: a rounded rectangle, with the bottom-right
/// corner sliced off when [cut] is positive.
class GlassBorder extends ShapeBorder {
  const GlassBorder({this.radius = 16, this.cut = 0});

  final double radius;
  final double cut;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final corner = Radius.circular(radius);
    if (cut <= 0 || expFlags.contains('nocut')) { // EXPERIMENT
      return Path()..addRRect(RRect.fromRectAndRadius(rect, corner));
    }
    return Path()
      ..moveTo(rect.left + radius, rect.top)
      ..lineTo(rect.right - radius, rect.top)
      ..arcToPoint(Offset(rect.right, rect.top + radius), radius: corner)
      ..lineTo(rect.right, rect.bottom - cut)
      ..lineTo(rect.right - cut, rect.bottom)
      ..lineTo(rect.left + radius, rect.bottom)
      ..arcToPoint(Offset(rect.left, rect.bottom - radius), radius: corner)
      ..lineTo(rect.left, rect.top + radius)
      ..arcToPoint(Offset(rect.left + radius, rect.top), radius: corner)
      ..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => GlassBorder(radius: radius * t, cut: cut * t);

  @override
  bool operator ==(Object other) =>
      other is GlassBorder && other.radius == radius && other.cut == cut;

  @override
  int get hashCode => Object.hash(radius, cut);
}

class _GlassPainter extends CustomPainter {
  _GlassPainter({
    required this.accent,
    required this.shape,
    required this.tint,
    required this.strength,
    required this.emphasis,
    required this.pointer,
  }) : super(repaint: pointer);

  final Color accent;
  final GlassBorder shape;
  final double tint;
  final double strength;
  final double emphasis;
  final ValueListenable<Offset?>? pointer;

  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0 || expFlags.contains('noglassfill')) return; // EXPERIMENT
    final rect = Offset.zero & size;
    Color white(double alpha) =>
        Colors.white.withValues(alpha: alpha * strength);
    Color tinted(double alpha) => accent.withValues(alpha: alpha * strength);

    // EXPERIMENT (whole block)
    canvas.save();
    if (!expFlags.contains('g_noclip')) canvas.clipPath(shape.getOuterPath(rect));
    if (!expFlags.contains('g_nosmoke')) {
      canvas.drawRect(
        rect,
        Paint()..color = Neon.smoke.withValues(alpha: tint * strength),
      );
    }
    if (!expFlags.contains('g_nograd1')) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [white(0.10), white(0.015)],
          ).createShader(rect),
      );
    }
    if (!expFlags.contains('g_nograd2')) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: const Alignment(0.3, 0.9),
            colors: [tinted(0.07 + 0.10 * emphasis), tinted(0)],
          ).createShader(rect),
      );
    }

    if (pointer?.value case final at?) {
      final reach = math.max(size.shortestSide * 1.5, 190.0);
      canvas.drawCircle(
        at,
        reach,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Color.lerp(Colors.white, accent, 0.5)!.withValues(
                alpha: 0.17 * strength,
              ),
              tinted(0),
            ],
          ).createShader(Rect.fromCircle(center: at, radius: reach)),
      );
    }

    // Inset so the whole stroke falls inside the outline.
    final rim = shape.getOuterPath(rect.deflate(0.6));
    if (!expFlags.contains('norim')) canvas.drawPath( // EXPERIMENT
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [white(0.5), white(0.08), tinted(0.3 + 0.6 * emphasis)],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
    if (emphasis > 0) {
      canvas.drawPath(
        rim,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = tinted(0.55 * emphasis)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassPainter old) =>
      old.accent != accent ||
      old.shape != shape ||
      old.tint != tint ||
      old.strength != strength ||
      old.emphasis != emphasis ||
      old.pointer != pointer;
}

/// The light a lit pane throws on what is around it.
class _HaloPainter extends CustomPainter {
  const _HaloPainter({
    required this.accent,
    required this.shape,
    required this.glow,
  });

  final Color accent;
  final GlassBorder shape;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    shape.getOuterPath(Offset.zero & size),
    Paint()
      ..color = accent.withValues(alpha: 0.42 * glow)
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 16),
  );

  @override
  bool shouldRepaint(_HaloPainter old) =>
      old.accent != accent || old.shape != shape || old.glow != glow;
}
