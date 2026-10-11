import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ClipOp;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Time for everything that moves without being asked to: the backdrop, the
/// live pulse, the title's glitch.
///
/// It is one clock so that all of it stops together, which it does while the
/// window is in the background (every frame redraws the whole window, and
/// nobody is watching) and when the system asks for reduced motion.
class AmbientClock extends ChangeNotifier implements ValueListenable<double> {
  AmbientClock._();

  /// Seconds the clock has run for.
  @override
  double get value => _seconds;
  double _seconds = 0;

  /// False while time is standing still.
  bool get isRunning => _running;
  bool _running = false;

  void _advanceTo(double seconds) {
    _seconds = seconds;
    notifyListeners();
  }

  void _setRunning(bool running) {
    _running = running;
    notifyListeners();
  }
}

/// Owns the [AmbientClock] for everything beneath it.
class Ambient extends StatefulWidget {
  const Ambient({super.key, required this.child});

  final Widget child;

  static AmbientClock of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_AmbientScope>()!.clock;

  /// False when the system asks for reduced motion, in which case entrances
  /// and other flourishes are skipped too.
  static bool allowsMotion(BuildContext context) =>
      !MediaQuery.disableAnimationsOf(context);

  @override
  State<Ambient> createState() => _AmbientState();
}

class _AmbientState extends State<Ambient> {
  final _clock = AmbientClock._();
  late final AppLifecycleListener _lifecycle;

  /// What moves the clock on. A timer and not a ticker, because a ticker asks
  /// for a frame at the display's full rate, and with no raster cache in the
  /// renderer every frame redraws the whole window. Drifting lights look the
  /// same at half that, for half the work.
  Timer? _timer;
  static const _step = Duration(milliseconds: 33);
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _foreground = state == AppLifecycleState.resumed;
        _sync();
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    final run = _foreground && Ambient.allowsMotion(context);
    if (run == (_timer != null)) return;
    if (run) {
      _timer = Timer.periodic(_step, (_) => _tick());
    } else {
      _timer?.cancel();
      _timer = null;
    }
    _clock._setRunning(run);
  }

  // Counted in steps rather than read off a stopwatch: if the app is too busy
  // to keep up, ambient time simply runs a little slow.
  void _tick() => _clock._advanceTo(
    _clock.value + _step.inMicroseconds / Duration.microsecondsPerSecond,
  );

  @override
  void dispose() {
    _lifecycle.dispose();
    _timer?.cancel();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _AmbientScope(clock: _clock, child: widget.child);
}

class _AmbientScope extends InheritedWidget {
  const _AmbientScope({required this.clock, required super.child});

  final AmbientClock clock;

  @override
  bool updateShouldNotify(_AmbientScope old) => old.clock != clock;
}

//// The night city behind the glass: slow lights adrift over a grid, swept by
/// a scan beam.
class CyberBackdrop extends StatelessWidget {
  const CyberBackdrop({super.key});

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _BackdropPainter(Ambient.of(context)),
      size: Size.infinite,
    ),
  );
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.clock) : super(repaint: clock);

  final AmbientClock clock;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    _Scene.at(size, clock).paint(canvas, frosted: false);
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.clock != clock;
}

/// The backdrop as it looks through frosted glass, for a pane with nothing
/// else behind it.
///
/// Blurring what is behind a pane has to be redone for every pane on every
/// frame, and a deck of cards is a lot of panes. But the backdrop is all soft
/// light apart from its grid and scanlines, which are exactly what a blur
/// takes away, so painting it again without them comes to the same picture
/// for a small fraction of the work.
class Frost extends StatelessWidget {
  const Frost({super.key, required this.shape, this.opacity = 1});

  /// The pane's outline.
  final ShapeBorder shape;
  final double opacity;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _FrostPainter(
        clock: Ambient.of(context),
        scroll: Scrollable.maybeOf(context)?.position,
        window: MediaQuery.sizeOf(context),
        pane: context,
        shape: shape,
        opacity: opacity,
      ),
    ),
  );
}

class _FrostPainter extends CustomPainter {
  _FrostPainter({
    required this.clock,
    required this.scroll,
    required this.window,
    required this.pane,
    required this.shape,
    required this.opacity,
  }) : super(repaint: Listenable.merge([clock, scroll]));

  final AmbientClock clock;

  /// Scrolling moves the pane over the backdrop without repainting it.
  final ScrollPosition? scroll;
  final Size window;

  /// Whose render object says where in the window the pane is.
  final BuildContext pane;
  final ShapeBorder shape;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final box = pane.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    // The backdrop fills the window, so the part of it behind this pane is
    // found by undoing whatever put the pane where it is: its place in the
    // layout, the scroll offset, and any transform it is being animated by.
    final fromWindow = Matrix4.tryInvert(box.getTransformTo(null));
    if (fromWindow == null) return;

    final bounds = Offset.zero & size;
    canvas
      ..save()
      ..clipPath(shape.getOuterPath(bounds));
    if (opacity < 1) {
      canvas.saveLayer(
        bounds,
        Paint()..color = Colors.black.withValues(alpha: opacity),
      );
    }
    canvas.transform(fromWindow.storage);
    _Scene.at(window, clock).paint(canvas, frosted: true);
    if (opacity < 1) canvas.restore();
    canvas.restore();
  }

  // The pane can move (a row above it grows, say) without anything here
  // changing, so there is no telling when the last painting still holds.
  @override
  bool shouldRepaint(_FrostPainter old) => true;
}

/// One drifting light. Positions and sizes are fractions of the window, paces
/// are radians a second.
class _Orb {
  const _Orb(
    this.color, {
    required this.home,
    required this.roam,
    required this.radius,
    required this.alpha,
    required this.pace,
    required this.phase,
  });

  final Color color;
  final Offset home;
  final Offset roam;
  final double radius;
  final double alpha;
  final double pace;
  final double phase;
}

/// The backdrop at one moment in one size of window, worked out once and then
/// painted as often as needed: by the backdrop itself, and by every frosted
/// pane in the same frame.
class _Scene {
  _Scene._(this.size, this.seconds, this.isRunning) {
    final rect = Offset.zero & size;
    _sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Neon.abyss, Neon.dusk],
      ).createShader(rect);

    for (final orb in _orbs) {
      final angle = seconds * orb.pace + orb.phase;
      final centre = Offset(
        size.width * (orb.home.dx + orb.roam.dx * math.sin(angle)),
        // A different pace on each axis, so the path never quite repeats.
        size.height * (orb.home.dy + orb.roam.dy * math.cos(angle * 1.37)),
      );
      final radius =
          size.longestSide * orb.radius * (1 + 0.1 * math.sin(angle * 2.3));
      _lights.add(
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [
              orb.color.withValues(alpha: orb.alpha),
              orb.color.withValues(alpha: orb.alpha * 0.32),
              orb.color.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }

    final sweep = (seconds % _beamEvery) / _beamCrossing;
    if (isRunning && sweep < 1) {
      final beam = Rect.fromLTWH(
        0,
        sweep * (size.height + _beamDepth) - _beamDepth,
        size.width,
        _beamDepth,
      );
      Paint lit(double edge) => Paint()
        ..blendMode = BlendMode.plus
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Neon.cyan.withValues(alpha: 0),
            Neon.cyan.withValues(alpha: 0.075),
            Neon.cyan.withValues(alpha: 0),
          ],
          stops: [0, edge, 1],
        ).createShader(beam);
      _hasBeam = true;
      // The light trails behind a hard leading edge, which frost softens.
      _beamSharp = lit(0.94);
      _beamSoft = lit(0.78);
    }

    // One dark row in every three.
    _scanlines = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        tileMode: TileMode.repeated,
        colors: [
          Colors.transparent,
          Colors.transparent,
          Colors.black.withValues(alpha: _scanlineDepth),
          Colors.black.withValues(alpha: _scanlineDepth),
        ],
        stops: const [0, 0.66, 0.66, 1],
      ).createShader(const Rect.fromLTWH(0, 0, 1, 3));

    _vignette = Paint()
      ..shader = RadialGradient(
        radius: 0.9,
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.5)],
        stops: const [0.55, 1],
      ).createShader(rect);
  }

  /// The scene for this window at this moment, kept for as long as neither
  /// changes.
  factory _Scene.at(Size size, AmbientClock clock) {
    final latest = _latest;
    if (latest != null &&
        latest.size == size &&
        latest.seconds == clock.value &&
        latest.isRunning == clock.isRunning) {
      return latest;
    }
    return _latest = _Scene._(size, clock.value, clock.isRunning);
  }

  static _Scene? _latest;

  final Size size;
  final double seconds;
  final bool isRunning;

  late final Paint _sky;
  final _lights = <Paint>[];
  bool _hasBeam = false;
  late final Paint _beamSharp;
  late final Paint _beamSoft;
  late final Paint _scanlines;
  late final Paint _vignette;

  static const _orbs = [
    _Orb(
      Neon.cyan,
      home: Offset(0.14, 0.20),
      roam: Offset(0.13, 0.12),
      radius: 0.36,
      alpha: 0.46,
      pace: 0.17,
      phase: 0,
    ),
    _Orb(
      Neon.pink,
      home: Offset(0.88, 0.34),
      roam: Offset(0.11, 0.18),
      radius: 0.38,
      alpha: 0.40,
      pace: 0.13,
      phase: 1.9,
    ),
    _Orb(
      Neon.violet,
      home: Offset(0.50, 0.94),
      roam: Offset(0.24, 0.10),
      radius: 0.46,
      alpha: 0.48,
      pace: 0.11,
      phase: 3.7,
    ),
    _Orb(
      Neon.yellow,
      home: Offset(0.70, 0.66),
      roam: Offset(0.16, 0.14),
      radius: 0.15,
      alpha: 0.14,
      pace: 0.21,
      phase: 5.1,
    ),
  ];

  static const _gridStep = 46.0;

  /// Pixels a second the grid slides up and to the left.
  static const _gridDrift = 5.0;

  /// Seconds the scan beam takes to cross the window, and to come round again.
  static const _beamCrossing = 7.0;
  static const _beamEvery = 11.0;
  static const _beamDepth = 170.0;

  static const _scanlineDepth = 0.22;

  /// Paints the scene, laid out for a window at the canvas's origin, over
  /// whatever the canvas is clipped to. With [frosted], as seen through glass:
  /// the lights, with the fine lines blurred away.
  ///
  /// Everything is poured over the clip with drawPaint, each gradient fading
  /// to nothing where its shape would have ended, rather than drawn as a
  /// rectangle or circle. On Windows the renderer gives those shapes a
  /// gradient by way of three extra render passes each, which adds up fast
  /// when every frosted pane paints this on every frame.
  void paint(Canvas canvas, {required bool frosted}) {
    canvas.drawPaint(_sky);
    for (final light in _lights) {
      canvas.drawPaint(light);
    }

    if (!frosted) {
      final line = Paint()..color = Neon.cyan.withValues(alpha: 0.055);
      final slide = (seconds * _gridDrift) % _gridStep;
      for (var x = -slide; x < size.width; x += _gridStep) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      }
      for (var y = -slide; y < size.height; y += _gridStep) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      }
    }
    if (_hasBeam) canvas.drawPaint(frosted ? _beamSoft : _beamSharp);
    if (frosted) {
      // Scanlines blur to an even dimming: a third of the rows, spread out.
      canvas.drawPaint(
        Paint()..color = Colors.black.withValues(alpha: _scanlineDepth / 3),
      );
    } else {
      canvas.drawPaint(_scanlines);
    }
    canvas.drawPaint(_vignette);
  }
}

// Text that now and then tears and splits into its colour channels, like a
/// sign with a bad connection.
class GlitchText extends StatefulWidget {
  const GlitchText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<GlitchText> createState() => _GlitchTextState();
}

class _GlitchTextState extends State<GlitchText> {
  /// The text as it normally reads, and its two displaced colour channels.
  TextPainter? _steady;
  TextPainter? _cold;
  TextPainter? _hot;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _layout();
  }

  @override
  void didUpdateWidget(GlitchText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.style != widget.style) _layout();
  }

  void _layout() {
    _disposePainters();
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    TextPainter laidOut(TextStyle style) => TextPainter(
      text: TextSpan(text: widget.text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    TextStyle channel(Color color) => style.copyWith(
      color: color.withValues(alpha: 0.85),
      shadows: const [],
    );
    _steady = laidOut(style);
    _cold = laidOut(channel(Neon.cyan));
    _hot = laidOut(channel(Neon.pink));
  }

  void _disposePainters() {
    _steady?.dispose();
    _cold?.dispose();
    _hot?.dispose();
  }

  @override
  void dispose() {
    _disposePainters();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.text,
    // It repaints with the clock; nothing around it needs to.
    child: RepaintBoundary(
      child: CustomPaint(
        size: _steady!.size,
        painter: _GlitchPainter(Ambient.of(context), _steady!, _cold!, _hot!),
      ),
    ),
  );
}

class _GlitchPainter extends CustomPainter {
  _GlitchPainter(this.clock, this.steady, this.cold, this.hot)
    : super(repaint: clock);

  final AmbientClock clock;
  final TextPainter steady;
  final TextPainter cold;
  final TextPainter hot;

  /// Seconds between glitches, and how long one lasts.
  static const _every = 8.5;
  static const _lasts = 0.42;

  /// A glitch holds each tear for this long before jumping to the next.
  static const _tearsPerSecond = 18;

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    // The glitch closes each cycle rather than opening it, so that a clock
    // that never starts does not leave the title torn.
    if (!clock.isRunning || t % _every < _every - _lasts) {
      steady.paint(canvas, Offset.zero);
      return;
    }

    final tear = (t * _tearsPerSecond).floor();
    final shove = (_noise(tear) - 0.5) * 9;
    cold.paint(canvas, Offset(shove, 0));
    hot.paint(canvas, Offset(-shove, 0));

    // One band of the text slides sideways; the rest stays put.
    final band = Rect.fromLTWH(
      -12,
      _noise(tear + 31) * size.height * 0.7,
      size.width + 24,
      size.height * 0.3,
    );
    canvas
      ..save()
      ..clipRect(band, clipOp: ClipOp.difference);
    steady.paint(canvas, Offset.zero);
    canvas
      ..restore()
      ..save()
      ..clipRect(band);
    steady.paint(canvas, Offset(shove * 1.7, 0));
    canvas.restore();
  }

  /// A repeatable scatter of values between 0 and 1.
  static double _noise(int n) {
    final x = math.sin(n * 12.9898) * 43758.5453;
    return x - x.floorToDouble();
  }

  @override
  bool shouldRepaint(_GlitchPainter old) =>
      old.clock != clock ||
      old.steady != steady ||
      old.cold != cold ||
      old.hot != hot;
}

/// A lamp. While [active] it glows, and with [pulses] it also sends out a
/// ring every couple of seconds.
class PulseDot extends StatelessWidget {
  const PulseDot({
    super.key,
    required this.color,
    this.active = true,
    this.pulses = true,
  });

  final Color color;
  final bool active;
  final bool pulses;

  static const _lamp = 3.5;
  static const _reach = 10.0;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: const Size.square(_reach * 2),
      painter: _PulsePainter(Ambient.of(context), color, active, pulses),
    ),
  );
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.clock, this.color, this.active, this.pulses)
    : super(repaint: clock);

  final AmbientClock clock;
  final Color color;
  final bool active;
  final bool pulses;

  static const _every = 1.8;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    if (active && pulses && clock.isRunning) {
      final spread = Curves.easeOut.transform(clock.value % _every / _every);
      canvas.drawCircle(
        centre,
        PulseDot._lamp + (PulseDot._reach - PulseDot._lamp) * spread,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = color.withValues(alpha: 0.7 * (1 - spread)),
      );
    }
    if (active) {
      canvas.drawCircle(
        centre,
        PulseDot._lamp,
        Paint()
          ..color = color.withValues(alpha: 0.8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    canvas.drawCircle(centre, PulseDot._lamp, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      old.clock != clock ||
      old.color != color ||
      old.active != active ||
      old.pulses != pulses;
}
