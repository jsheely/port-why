import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Answered by windows/runner/flutter_window.cpp.
const _window = MethodChannel('port_why/window');

/// Lays the window's buttons over the top of [child], where Windows would
/// have drawn a title bar, and tells [child] through its padding how deep
/// that strip is.
///
/// The strip is the page's to draw in. Whatever it puts there moves the
/// window when dragged, as a title bar does, apart from what it wraps in a
/// [TitleBarControl].
///
/// On macOS and Linux the system keeps its own title bar, buttons and all,
/// so the strip is only the top of the page.
class WindowFrame extends StatefulWidget {
  const WindowFrame({super.key, required this.child, this.drawsButtons});

  final Widget child;

  /// Whether the window's buttons are ours to draw. Left out, they are on
  /// Windows alone, where the runner hands the title bar over.
  final bool? drawsButtons;

  /// The room the window's buttons take up at the right-hand end of the
  /// strip, for a page to keep clear of.
  static double buttonsWidthOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_TitleBarScope>()
          ?.buttonsWidth ??
      0;

  @override
  State<WindowFrame> createState() => _WindowFrameState();
}

class _WindowFrameState extends State<WindowFrame> {
  /// Every [TitleBarControl] on screen.
  final _controls = <BuildContext>{};

  /// Their edges as the runner last heard them.
  List<double>? _reported;

  bool get _drawsButtons =>
      widget.drawsButtons ?? defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_report);
  }

  /// Tells the runner where the controls are, after any frame that moved
  /// them. Nothing says when one has moved, so each frame looks.
  void _report(Duration _) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback(_report);
    // A title bar the system draws is the system's to hit-test.
    if (!_drawsButtons) return;

    final edges = <double>[];
    for (final control in _controls) {
      final box = control.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final rect = MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      );
      if (rect.top >= TitleBar.height) continue;
      edges.addAll([rect.left, rect.top, rect.right, rect.bottom]);
    }
    if (listEquals(edges, _reported)) return;
    _reported = edges;
    _send(edges);
  }

  Future<void> _send(List<double> edges) async {
    try {
      await _window.invokeMethod<void>(
        'setControls',
        Float64List.fromList(edges),
      );
    } on MissingPluginException {
      // No runner to tell: a test.
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return _TitleBarScope(
      controls: _controls,
      buttonsWidth: _drawsButtons ? TitleBar.buttonsWidth : 0,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MediaQuery(
            data: media.copyWith(
              padding: media.padding.copyWith(
                top: media.padding.top + TitleBar.height,
              ),
            ),
            child: widget.child,
          ),
          // Above the navigator, so the window can still be closed from
          // behind a dialog.
          if (_drawsButtons)
            const Positioned(
              top: 0,
              right: 0,
              height: TitleBar.height,
              child: TitleBar(),
            ),
        ],
      ),
    );
  }
}

class _TitleBarScope extends InheritedWidget {
  const _TitleBarScope({
    required this.controls,
    required this.buttonsWidth,
    required super.child,
  });

  final Set<BuildContext> controls;
  final double buttonsWidth;

  @override
  bool updateShouldNotify(_TitleBarScope old) => old.buttonsWidth != buttonsWidth;
}

/// Something in the title bar that is clicked rather than dragged: Windows
/// leaves the pointer to [child] instead of moving the window by it.
class TitleBarControl extends StatefulWidget {
  const TitleBarControl({super.key, required this.child});

  final Widget child;

  @override
  State<TitleBarControl> createState() => _TitleBarControlState();
}

class _TitleBarControlState extends State<TitleBarControl> {
  Set<BuildContext>? _controls;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controls?.remove(context);
    _controls = context
        .dependOnInheritedWidgetOfExactType<_TitleBarScope>()
        ?.controls;
    _controls?.add(context);
  }

  @override
  void dispose() {
    _controls?.remove(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The window's minimize, maximize and close buttons, at the right-hand end
/// of the strip it is moved by.
///
/// The runner hands that strip to Windows as a title bar, so dragging it,
/// double-clicking it and right-clicking it do what they do on any other
/// window. Its height is therefore repeated in
/// windows/runner/win32_window.cpp, and does not grow with the text.
class TitleBar extends StatefulWidget {
  const TitleBar({super.key});

  static const height = 52.0;
  static const buttonWidth = 46.0;

  /// The room the buttons take up. A page asks [WindowFrame.buttonsWidthOf]
  /// how much of that to keep clear of.
  static const buttonsWidth = 3 * buttonWidth;

  @override
  State<TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<TitleBar> {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    _window.setMethodCallHandler(_onCall);
  }

  @override
  void dispose() {
    _window.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'maximized') return;
    setState(() => _isMaximized = call.arguments as bool);
  }

  @override
  Widget build(BuildContext context) {
    return TitleBarControl(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WindowButton(
            label: 'Minimize',
            icon: Icons.remove_rounded,
            color: Neon.cyan,
            onTap: () => _window.invokeMethod<void>('minimize'),
          ),
          _WindowButton(
            label: _isMaximized ? 'Restore' : 'Maximize',
            icon: _isMaximized
                ? Icons.filter_none_rounded
                : Icons.crop_square_rounded,
            iconSize: _isMaximized ? 13 : 15,
            color: Neon.cyan,
            onTap: () => _window.invokeMethod<void>('toggleMaximize'),
          ),
          _WindowButton(
            label: 'Close',
            icon: Icons.close_rounded,
            color: Neon.pink,
            onTap: () => _window.invokeMethod<void>('close'),
          ),
        ],
      ),
    );
  }
}

/// One of the title bar's buttons, which lights up in [color] under the
/// pointer.
class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.iconSize = 16,
  });

  final String label;
  final IconData icon;
  final double iconSize;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurfaceVariant;
    final color = widget.color;
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: TitleBar.buttonWidth,
            color: color.withValues(
              alpha: _pressed
                  ? 0.34
                  : _hovered
                  ? 0.2
                  : 0,
            ),
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: _hovered ? color : dim,
              shadows: _hovered ? neonGlow(color) : null,
            ),
          ),
        ),
      ),
    );
  }
}
