import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher, VertexMode, Vertices;

import 'package:flutter/material.dart';

/// A shape that is drawn with smooth edges: its outline as a ring of points,
/// clockwise, each with the way squarely out of the shape from there.
///
/// The renderer on Windows (Impeller, on OpenGL) has no multisampling. A path
/// or a clip there either has a pixel or does not, which turns every curve
/// and slant into a staircase. So the shape is drawn as a mesh instead, whose
/// colour fades to nothing across the width of a pixel at each edge. The
/// outline has to bulge outwards everywhere.
class SoftEdge {
  /// Colour is only blended in straight lines between points, so wherever
  /// [split] changes sign along the outline a point is added.
  SoftEdge(List<Offset> outline, {double Function(Offset at)? split}) {
    for (var i = 0; i < outline.length; i++) {
      final from = outline[i];
      final to = outline[(i + 1) % outline.length];
      if ((to - from).distanceSquared < 1e-6) continue;
      _points.add(from);
      if (split == null) continue;
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
      final mitre =
          (before + after) / (1 + before.dx * after.dx + before.dy * after.dy);
      // At a sharp point the mitre runs away, and would draw a spike.
      _mitres.add(mitre.distance > 1.5 ? mitre / mitre.distance * 1.5 : mitre);
    }
  }

  final _points = <Offset>[];
  final _mitres = <Offset>[];

  /// How wide one pixel of the screen is.
  static double get pixel =>
      1 / (PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1);

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

  /// Fills the shape with [color].
  void fill(Canvas canvas, Color color) => _points.length < 3
      ? null
      : draw(
          canvas,
          mesh(
            [-pixel / 2, pixel / 2],
            (at, ring) => ring == 0 ? color.withValues(alpha: 0) : color,
            filled: true,
          ),
        );

  /// Draws a line of [color], [width] wide, just inside the outline.
  void stroke(Canvas canvas, Color color, double width) => draw(
    canvas,
    mesh(
      [-pixel / 2, pixel / 2, width - pixel / 2, width + pixel / 2],
      (at, ring) => ring == 1 || ring == 2 ? color : color.withValues(alpha: 0),
    ),
  );

  /// Draws a [mesh] in its own colours, and lets go of it.
  static void draw(Canvas canvas, Vertices mesh) {
    canvas.drawVertices(mesh, BlendMode.dst, Paint());
    mesh.dispose();
  }

  /// The part of [shape] inside [bounds], both of them rings of points that
  /// bulge outwards everywhere and run clockwise.
  static List<Offset> within(List<Offset> shape, List<Offset> bounds) {
    var kept = shape;
    for (var i = 0; i < bounds.length && kept.isNotEmpty; i++) {
      final from = bounds[i];
      final side = bounds[(i + 1) % bounds.length] - from;
      // Positive on the inner side of this stretch of the bounds.
      double inside(Offset at) =>
          side.dx * (at.dy - from.dy) - side.dy * (at.dx - from.dx);
      final next = <Offset>[];
      for (var j = 0; j < kept.length; j++) {
        final a = kept[j], b = kept[(j + 1) % kept.length];
        final da = inside(a), db = inside(b);
        if (da >= 0) next.add(a);
        if (da * db < 0) next.add(Offset.lerp(a, b, da / (da - db))!);
      }
      kept = next;
    }
    return kept;
  }
}

/// A rectangle with its corners cut off at a slant, [cut] along each side.
class CutBorder extends OutlinedBorder {
  const CutBorder({this.cut = 6, super.side});

  final double cut;

  List<Offset> _outline(Rect rect) {
    final c = math.min(cut, rect.shortestSide / 2);
    return [
      Offset(rect.left + c, rect.top),
      Offset(rect.right - c, rect.top),
      Offset(rect.right, rect.top + c),
      Offset(rect.right, rect.bottom - c),
      Offset(rect.right - c, rect.bottom),
      Offset(rect.left + c, rect.bottom),
      Offset(rect.left, rect.bottom - c),
      Offset(rect.left, rect.top + c),
    ];
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addPolygon(_outline(rect), true);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(side.width), textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width <= 0) return;
    SoftEdge(_outline(rect)).stroke(canvas, side.color, side.width);
  }

  @override
  CutBorder copyWith({BorderSide? side, double? cut}) =>
      CutBorder(cut: cut ?? this.cut, side: side ?? this.side);

  @override
  ShapeBorder scale(double t) => CutBorder(cut: cut * t, side: side.scale(t));

  @override
  bool operator ==(Object other) =>
      other is CutBorder && other.cut == cut && other.side == side;

  @override
  int get hashCode => Object.hash(cut, side);
}
