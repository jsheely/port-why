import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Lays the app's own title bar over the top of [child], where Windows would
/// have drawn one, and tells [child] through its padding to keep clear of it.
class WindowFrame extends StatelessWidget {
  const WindowFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        MediaQuery(
          data: media.copyWith(
            padding: media.padding.copyWith(
              top: media.padding.top + TitleBar.height,
            ),
          ),
          child: child,
        ),
        // Above the navigator, so the window can still be closed from behind
        // a dialog.
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: TitleBar.height,
          child: TitleBar(),
        ),
      ],
    );
  }
}

/// The strip the window is moved by, and its minimize, maximize and close
/// buttons.
///
/// Only the buttons are Flutter's. The rest of the strip the runner hands to
/// Windows as a title bar, so dragging it, double-clicking it and
/// right-clicking it do what they do on any other window. Its size is
/// therefore repeated in windows/runner/win32_window.cpp, and does not grow
/// with the text.
class TitleBar extends StatefulWidget {
  const TitleBar({super.key});

  static const height = 32.0;
  static const buttonWidth = 46.0;

  @override
  State<TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<TitleBar> {
  /// Answered by windows/runner/flutter_window.cpp.
  static const _window = MethodChannel('port_why/window');

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
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
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
