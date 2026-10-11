import 'package:flutter/material.dart';

import '../models.dart';
import 'glass.dart';
import 'soft_edge.dart';
import 'theme.dart';

/// Asks before killing [entry]'s process. Resolves to true only on an explicit
/// confirmation.
Future<bool> confirmKill(
  BuildContext context,
  PortEntry entry, {
  required List<PortEntry> alsoClosing,
}) async {
  final confirmed = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Neon.abyss.withValues(alpha: 0.72),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, animation, _) => _KillDialog(
      entry: entry,
      alsoClosing: alsoClosing,
      animation: animation,
    ),
    // The dialog brings itself in. The stock fade would put its glass inside
    // an opacity layer, where there is nothing behind it to blur.
    transitionBuilder: (context, animation, _, child) => child,
  );
  return confirmed ?? false;
}

class _KillDialog extends StatelessWidget {
  const _KillDialog({
    required this.entry,
    required this.alsoClosing,
    required this.animation,
  });

  final PortEntry entry;
  final List<PortEntry> alsoClosing;

  /// The route's own animation: 0 while closed, 1 once open.
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final danger = scheme.error;
    final process = entry.process;
    final container = process.container;
    final project = entry.project == null ? '' : ' (${entry.project!.name})';
    final otherPorts = {for (final other in alsoClosing) other.port}.toList()
      ..sort();
    final title = container == null
        ? 'Kill ${process.name}?'
        : 'Stop ${container.name}?';
    final body = TextStyle(
      fontSize: 13.5,
      height: 1.45,
      color: scheme.onSurface.withValues(alpha: 0.92),
    );

    // What exactly is about to be stopped, and where it lives.
    final target = switch ((container, process.distro)) {
      (final container?, final distro) =>
        'This stops the Docker container ${container.name}$project'
            '${distro == null ? '' : ' in WSL ($distro)'}',
      (null, final distro?) =>
        'This ends process ${process.pid}$project in WSL ($distro)',
      (null, null) => 'This ends process ${process.pid}$project',
    };

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomPaint(
          size: const Size.fromHeight(7),
          painter: _HazardPainter(danger, radius: _radius),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.stop_circle_outlined,
                    color: danger,
                    size: 26,
                    shadows: neonGlow(danger, spread: 14),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '$target, which is holding port ${entry.port} open. '
                'Anything it has not saved is lost.',
                style: body,
              ),
              if (otherPorts.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'It also holds ${otherPorts.length == 1 ? 'port' : 'ports'} '
                  '${_summarise(otherPorts)}, which will close too.',
                  style: body,
                ),
              ],
              if (entry.category == PortCategory.system) ...[
                const SizedBox(height: 12),
                Text(
                  'This is part of Windows. Killing it can break networking or '
                  'sign you out.',
                  style: body.copyWith(color: Neon.yellow),
                ),
              ],
              if (process.commandLine case final command?) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: well(radius: 8),
                  child: Text(
                    command,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: mono.copyWith(
                      fontSize: 12,
                      height: 1.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onSurfaceVariant,
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    style: neonButton(danger),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(
                      container == null ? 'Kill process' : 'Stop container',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label: title,
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, content) => Transform.scale(
                  // Lands with a slight bounce.
                  scale: 0.9 + 0.1 * Curves.easeOutBack.transform(animation.value),
                  child: Glass(
                    accent: danger,
                    radius: _radius,
                    cut: 22,
                    blur: 28,
                    tint: 0.68,
                    strength: Curves.easeOutCubic.transform(animation.value),
                    emphasis: 0.55,
                    child: content!,
                  ),
                ),
                child: FadeTransition(opacity: animation, child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _radius = 20.0;

  static String _summarise(List<int> ports) => ports.length <= 6
      ? ports.join(', ')
      : '${ports.take(6).join(', ')} and ${ports.length - 6} more';
}

/// The slanted stripes of warning tape, along the top of a pane whose
/// corners are rounded by [radius].
class _HazardPainter extends CustomPainter {
  const _HazardPainter(this.color, {required this.radius});

  final Color color;
  final double radius;

  static const _stripe = 9.0;

  @override
  void paint(Canvas canvas, Size size) {
    final lean = size.height;
    // The tape stops at the pane's corners by its own shape. The pane's clip
    // would cut it off there too, but along a staircase.
    final pane = GlassBorder(radius: radius)
        .outline(Rect.fromLTWH(0, 0, size.width, size.height + 2 * radius));
    final tape = color.withValues(alpha: 0.85);
    for (var x = -lean; x < size.width; x += 2 * _stripe) {
      final stripe = SoftEdge.within([
        Offset(x, size.height),
        Offset(x + lean, 0),
        Offset(x + lean + _stripe, 0),
        Offset(x + _stripe, size.height),
      ], pane);
      SoftEdge(stripe).fill(canvas, tape);
    }
  }

  @override
  bool shouldRepaint(_HazardPainter old) =>
      old.color != color || old.radius != radius;
}
