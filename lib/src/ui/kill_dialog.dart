import 'package:flutter/material.dart';

import '../models.dart';

/// Asks before killing [entry]'s process. Resolves to true only on an explicit
/// confirmation.
Future<bool> confirmKill(
  BuildContext context,
  PortEntry entry, {
  required List<PortEntry> alsoClosing,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => _KillDialog(entry: entry, alsoClosing: alsoClosing),
  );
  return confirmed ?? false;
}

class _KillDialog extends StatelessWidget {
  const _KillDialog({required this.entry, required this.alsoClosing});

  final PortEntry entry;
  final List<PortEntry> alsoClosing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final process = entry.process;
    final container = process.container;
    final project = entry.project == null ? '' : ' (${entry.project!.name})';
    final otherPorts = {for (final other in alsoClosing) other.port}.toList()
      ..sort();

    // What exactly is about to be stopped, and where it lives.
    final target = switch ((container, process.distro)) {
      (final container?, final distro) =>
        'This stops the Docker container ${container.name}$project'
            '${distro == null ? '' : ' in WSL ($distro)'}',
      (null, final distro?) =>
        'This ends process ${process.pid}$project in WSL ($distro)',
      (null, null) => 'This ends process ${process.pid}$project',
    };

    return AlertDialog(
      icon: Icon(Icons.stop_circle_outlined, color: scheme.error),
      title: Text(
        container == null ? 'Kill ${process.name}?' : 'Stop ${container.name}?',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$target, which is holding port ${entry.port} open. '
              'Anything it has not saved is lost.',
            ),
            if (otherPorts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'It also holds ${otherPorts.length == 1 ? 'port' : 'ports'} '
                '${_summarise(otherPorts)}, which will close too.',
              ),
            ],
            if (entry.category == PortCategory.system) ...[
              const SizedBox(height: 12),
              Text(
                'This is part of Windows. Killing it can break networking or '
                'sign you out.',
                style: TextStyle(color: scheme.error),
              ),
            ],
            if (process.commandLine case final command?) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  command,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'Consolas',
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(container == null ? 'Kill process' : 'Stop container'),
        ),
      ],
    );
  }

  static String _summarise(List<int> ports) => ports.length <= 6
      ? ports.join(', ')
      : '${ports.take(6).join(', ')} and ${ports.length - 6} more';
}
