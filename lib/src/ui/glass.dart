import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageFilter, VertexMode, Vertices;

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
    this.flatTop = false,
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

  /// True for a pane hung from the top of the window, whose top corners are
  /// square to meet it.
  final bool flatTop;
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
    final shape = GlassBorder(radius: radius, cut: cut, flatTop: flatTop);
    final pane = CustomPaint(
      painter: _GlassPainter(
        accent: accent,
        shape: shape,
        tint: tint,
        strength: strength,
        emphasis: emphasis,
        pointer: pointer,
        pixel: 1 / MediaQuery.devicePixelRatioOf(context),
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
          if (strength > 0)
            Positioned.fill(
              child: Frost(shape: shape, opacity: strength),
            ),
          pane,
        ],
      );
    } else {
      final sigma = blur * strength;
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
/// corner sliced off when [cut] is positive, and the top corners left square
/// with [flatTop].
class GlassBorder extends ShapeBorder {
  const GlassBorder({this.radius = 16, this.cut = 0, this.flatTop = false});

  final double radius;
  final double cut;
  final bool flatTop;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final corner = Radius.circular(radius);
    final top = flatTop ? 0.0 : radius;
    final topCorner = Radius.circular(top);
    if (cut <= 0) {
      return Path()..addRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: topCorner,
          topRight: topCorner,
          bottomLeft: corner,
          bottomRight: corner,
        ),
      );
    }
    return Path()
      ..moveTo(rect.left + top, rect.top)
      ..lineTo(rect.right - top, rect.top)
      ..arcToPoint(Offset(rect.right, rect.top + top), radius: topCorner)
      ..lineTo(rect.right, rect.bottom - cut)
      ..lineTo(rect.right - cut, rect.bottom)
      ..lineTo(rect.left + radius, rect.bottom)
      ..arcToPoint(Offset(rect.left, rect.bottom - radius), radius: corner)
      ..lineTo(rect.left, rect.top + top)
      ..arcToPoint(Offset(rect.left + top, rect.top), radius: topCorner)
      ..close();
  }

  /// The same outline as a ring of points, clockwise from the top left, with
  /// each curve broken into steps too short to see.
  List<Offset> outline(Rect rect) {
    final top = flatTop ? 0.0 : radius;
    final points = <Offset>[];
    void arc(Offset centre, double radius, double from) {
      // A square corner is a single point.
      final steps = radius > 0 ? (radius * 0.8).ceil().clamp(4, 32) : 1;
      for (var i = 0; i <= steps; i++) {
        final angle = from + math.pi / 2 * i / steps;
        points.add(centre + Offset(math.cos(angle), math.sin(angle)) * radius);
      }
    }

    arc(Offset(rect.left + top, rect.top + top), top, math.pi);
    arc(Offset(rect.right - top, rect.top + top), top, -math.pi / 2);
    if (cut > 0) {
      points
        ..add(Offset(rect.right, rect.bottom - cut))
        ..add(Offset(rect.right - cut, rect.bottom));
    } else {
      arc(Offset(rect.right - radius, rect.bottom - radius), radius, 0);
    }
    arc(Offset(rect.left + radius, rect.bottom - radius), radius, math.pi / 2);
    return points;
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) =>
      GlassBorder(radius: radius * t, cut: cut * t, flatTop: flatTop);

  @override
  bool operator ==(Object other) =>
      other is GlassBorder &&
      other.radius == radius &&
      other.cut == cut &&
      other.flatTop == flatTop;

  @override
  int get hashCode => Object.hash(radius, cut, flatTop);
}

class _GlassPainter extends CustomPainter {
  _GlassPainter({
    required this.accent,
    required this.shape,
    required this.tint,
    required this.strength,
    required this.emphasis,
    required this.pointer,
    required this.pixel,
  }) : super(repaint: pointer);

  final Color accent;
  final GlassBorder shape;
  final double tint;
  final double strength;
  final double emphasis;
  final ValueListenable<Offset?>? pointer;

  /// How wide one pixel of the screen is.
  final double pixel;

  static const _rimWidth = 1.2;

  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0) return;
    final rect = Offset.zero & size;
    Color white(double alpha) =>
        Colors.white.withValues(alpha: alpha * strength);
    Color tinted(double alpha) => accent.withValues(alpha: alpha * strength);

    final across = rect.bottomRight - rect.topLeft;
    // How far from the top left corner to the bottom right a point is.
    double along(Offset point) =>
        ((point.dx - rect.left) * across.dx +
            (point.dy - rect.top) * across.dy) /
        across.distanceSquared;
    // The rim changes colour halfway along, which needs points there.
    final edge = _Edge(shape.outline(rect), split: (at) => along(at) - 0.5);
    final half = pixel / 2;
    void draw(Vertices mesh) {
      canvas.drawVertices(mesh, BlendMode.dst, Paint());
      mesh.dispose();
    }

    // The pane is drawn as meshes that fade out across the last pixel, not
    // as paths or under a clip. The renderer on Windows (Impeller, on OpenGL)
    // has no multisampling: a path or a clip there either has a pixel or does
    // not, which turns every curve and slant into a staircase. It does smooth
    // rectangles and circles, by drawing them from a distance field, but it
    // gives one a gradient by rendering both off screen and blending them:
    // three extra render passes a fill, on every pane, sixty times a second.
    // Measured, that was most of a frame.
    final smoke = Neon.smoke.withValues(alpha: tint * strength);
    draw(
      edge.mesh(
        [-half, half],
        (at, ring) => ring == 0 ? smoke.withValues(alpha: 0) : smoke,
        filled: true,
      ),
    );
    // The body of the pane catches light from the top left...
    draw(
      edge.mesh(
        [-half, half],
        (at, ring) => white(ring == 0 ? 0 : 0.10 - 0.085 * along(at)),
        filled: true,
      ),
    );

    // What is left is too faint for its hard edge to show, and is poured over
    // the whole clip with drawPaint, which costs no extra passes either.
    canvas
      ..save()
      ..clipPath(shape.getOuterPath(rect))
      // ...and takes a little colour from whatever it is showing.
      ..drawPaint(
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: const Alignment(0.3, 0.9),
            colors: [tinted(0.07 + 0.10 * emphasis), tinted(0)],
          ).createShader(rect),
      );

    if (pointer?.value case final at?) {
      final reach = math.max(size.shortestSide * 1.5, 190.0);
      // The gradient ends clear, so beyond its reach this paints nothing.
      canvas.drawPaint(
        Paint()
          ..shader = RadialGradient(
            colors: [
              Color.lerp(
                Colors.white,
                accent,
                0.5,
              )!.withValues(alpha: 0.17 * strength),
              tinted(0),
            ],
          ).createShader(Rect.fromCircle(center: at, radius: reach)),
      );
    }
    canvas.restore();

    // The rim is solid for its width just inside the outline, and clear a
    // pixel either side of that.
    final rim = [white(0.5), white(0.08), tinted(0.3 + 0.6 * emphasis)];
    draw(
      edge.mesh([-half, half, _rimWidth - half, _rimWidth + half], (at, ring) {
        final t = along(at) * 2;
        final color = t < 1
            ? Color.lerp(rim[0], rim[1], t)!
            : Color.lerp(rim[1], rim[2], t - 1)!;
        return ring == 1 || ring == 2 ? color : color.withValues(alpha: 0);
      }),
    );
    if (emphasis > 0) {
      canvas
        ..save()
        ..clipPath(shape.getOuterPath(rect))
        ..drawPath(
          // Inset so the whole stroke falls inside the outline.
          shape.getOuterPath(rect.deflate(_rimWidth / 2)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = tinted(0.55 * emphasis)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_GlassPainter old) =>
      old.accent != accent ||
      old.shape != shape ||
      old.tint != tint ||
      old.strength != strength ||
      old.emphasis != emphasis ||
      old.pointer != pointer ||
      old.pixel != pixel;
}

/// A pane's outline as a ring of points, each with the way squarely out of
/// the pane from there.
class _Edge {
  /// Colour is only blended in straight lines between points, so wherever
  /// [split] changes sign along the outline a point is added.
  _Edge(List<Offset> outline, {required double Function(Offset at) split}) {
    for (var i = 0; i < outline.length; i++) {
      final from = outline[i];
      final to = outline[(i + 1) % outline.length];
      if ((to - from).distanceSquared < 1e-6) continue;
      _points.add(from);
      final a = split(from), b = split(to);
      if (a * b < 0) _points.add(Offset.lerp(from, to, a / (a - b))!);
    }
    Offset outward(Offset from, Offset to) {
      final side = to - from;
      return Offset(side.dy, -side.dx) / side.distance;
    }

    final count = _points.length;
    for (var i = 0; i < count; i++) {
      final before = outward(_points[(i - 1 + count) % count], _points[i]);
      final after = outward(_points[i], _points[(i + 1) % count]);
      // Stepping along the mitre keeps a ring parallel to the outline on both
      // sides of a corner.
      _mitres.add(
        (before + after) / (1 + before.dx * after.dx + before.dy * after.dy),
      );
    }
  }

  final _points = <Offset>[];
  final _mitres = <Offset>[];

  /// Bands between copies of the outline, each moved in by one of [depths],
  /// coloured by [shade] at every point of every ring. With [filled], the
  /// innermost ring is filled in as well.
  Vertices mesh(
    List<double> depths,
    Color Function(Offset at, int ring) shade, {
    bool filled = false,
  }) {
    final count = _points.length;
    final rings = depths.length;
    final bands = rings - 1;
    final hub = count * rings;
    final positions = Float32List((hub + 1) * 2);
    final shades = Int32List(hub + 1);
    final indices = Uint16List(count * (bands * 6 + (filled ? 3 : 0)));
    var index = 0;
    var middle = Offset.zero;
    for (var i = 0; i < count; i++) {
      final next = (i + 1) % count;
      for (var ring = 0; ring < rings; ring++) {
        final at = i * rings + ring;
        final other = next * rings + ring;
        final vertex = _points[i] - _mitres[i] * depths[ring];
        positions[at * 2] = vertex.dx;
        positions[at * 2 + 1] = vertex.dy;
        shades[at] = shade(vertex, ring).toARGB32();
        if (ring < bands) {
          indices
            ..[index++] = at
            ..[index++] = other
            ..[index++] = other + 1
            ..[index++] = at
            ..[index++] = other + 1
            ..[index++] = at + 1;
        } else if (filled) {
          indices
            ..[index++] = hub
            ..[index++] = at
            ..[index++] = other;
        }
      }
      middle += _points[i] / count.toDouble();
    }
    positions[hub * 2] = middle.dx;
    positions[hub * 2 + 1] = middle.dy;
    shades[hub] = shade(middle, bands).toARGB32();
    return Vertices.raw(
      VertexMode.triangles,
      positions,
      colors: shades,
      indices: indices,
    );
  }
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
