import 'dart:io' show pid;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/port_repository.dart';
import '../models.dart';
import '../state/ports_controller.dart';
import 'format.dart';
import 'kill_dialog.dart';
import 'port_table.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.repository});

  final PortRepository repository;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final PortsController _controller = PortsController(
    widget.repository,
    ownPid: pid,
  );
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _expanded = <String>{};

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _search.clear();
    _controller.query = '';
  }

  void _toggle(PortEntry entry) => setState(() {
    if (!_expanded.remove(entry.id)) _expanded.add(entry.id);
  });

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openFolder(PortEntry entry) async {
    final opened = await _controller.openFolder(entry);
    if (!opened && mounted) _say('${entry.folder} no longer exists.');
  }

  Future<void> _kill(PortEntry entry) async {
    final confirmed = await confirmKill(
      context,
      entry,
      alsoClosing: _controller.portsSharingProcess(entry),
    );
    if (!confirmed || !mounted) return;

    final result = await _controller.kill(entry);
    if (!mounted) return;
    final container = entry.process.container;
    final who = container == null
        ? '${entry.process.name} (PID ${entry.process.pid})'
        : 'container ${container.name}';
    final (did, verb) = container == null
        ? ('Killed', 'kill')
        : ('Stopped', 'stop');
    final stillOpen = _controller.entries.any(
      (other) => other.port == entry.port && other.protocol == entry.protocol,
    );
    _say(switch (result) {
      KillResult.killed when stillOpen =>
        '$did $who, but something is still holding port ${entry.port}.',
      KillResult.killed => '$did $who. Port ${entry.port} is free.',
      KillResult.notFound => '$who had already exited.',
      KillResult.accessDenied =>
        'Windows refused to end $who. Run Port Why as administrator to kill it.',
      KillResult.failed => 'Could not $verb $who.',
    });
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.f5): () =>
            _controller.refresh(fresh: true),
        const SingleActivator(LogicalKeyboardKey.escape): _clearSearch,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) => Column(
                  children: [
                    _Header(controller: _controller),
                    const SizedBox(height: 14),
                    _FilterBar(
                      controller: _controller,
                      search: _search,
                      searchFocus: _searchFocus,
                      onClear: _clearSearch,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: PortTable(
                        controller: _controller,
                        expanded: _expanded,
                        onToggle: _toggle,
                        onKill: _kill,
                        onOpenFolder: _openFolder,
                        placeholder: _Placeholder(
                          controller: _controller,
                          onClearFilters: () {
                            _clearSearch();
                            _controller.scope = ScopeFilter.all;
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _StatusBar(controller: _controller),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final PortsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final processes = {for (final e in controller.entries) e.process.pid}.length;

    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.lan_rounded, color: scheme.onPrimaryContainer, size: 21),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Port Why',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
            Text(
              controller.isLoading
                  ? 'Reading open ports…'
                  : '${countOf(controller.entries.length, 'open port')} held by '
                        '${countOf(processes, 'process', plural: 'processes')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const Spacer(),
        _LiveToggle(controller: controller),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Rescan everything (F5)',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => controller.refresh(fresh: true),
        ),
      ],
    );
  }
}

class _LiveToggle extends StatelessWidget {
  const _LiveToggle({required this.controller});

  final PortsController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final live = controller.isLive;
    final seconds = controller.pollInterval.inSeconds;
    return Tooltip(
      message: live
          ? 'Updating every $seconds s. Click to pause.'
          : 'Paused. Click to resume live updates.',
      child: ActionChip(
        avatar: Icon(
          live ? Icons.circle : Icons.pause_rounded,
          size: live ? 10 : 16,
          color: live ? const Color(0xff2fbf71) : scheme.onSurfaceVariant,
        ),
        label: Text(live ? 'Live' : 'Paused'),
        onPressed: () => controller.isLive = !live,
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.controller,
    required this.search,
    required this.searchFocus,
    required this.onClear,
  });

  final PortsController controller;
  final TextEditingController search;
  final FocusNode searchFocus;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: search,
            focusNode: searchFocus,
            onChanged: (value) => controller.query = value,
            decoration: InputDecoration(
              hintText: 'Filter by port, project, process, folder…  (Ctrl+F)',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: controller.query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear filter (Esc)',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: onClear,
                    ),
              isDense: true,
              filled: true,
              fillColor: scheme.surfaceContainerHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SegmentedButton<ScopeFilter>(
          showSelectedIcon: false,
          segments: [
            for (final scope in ScopeFilter.values)
              ButtonSegment(
                value: scope,
                label: Text.rich(
                  TextSpan(
                    text: scope.label,
                    children: [
                      TextSpan(
                        text: '  ${controller.counts[scope] ?? 0}',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          selected: {controller.scope},
          onSelectionChanged: (selection) => controller.scope = selection.single,
        ),
        const SizedBox(width: 12),
        Tooltip(
          message: 'Also list UDP ports',
          child: FilterChip(
            label: const Text('UDP'),
            selected: controller.includeUdp,
            onSelected: (value) => controller.includeUdp = value,
          ),
        ),
      ],
    );
  }
}

/// What the table shows when it has no rows, and why.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.controller, required this.onClearFilters});

  final PortsController controller;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;

    Widget message(IconData icon, String title, {String? detail, Widget? action}) =>
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 36, color: dim),
                const SizedBox(height: 12),
                Text(title, style: theme.textTheme.titleMedium),
                if (detail != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    detail,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: dim),
                  ),
                ],
                if (action != null) ...[const SizedBox(height: 14), action],
              ],
            ),
          ),
        );

    if (!controller.isSupported) {
      return message(
        Icons.desktop_windows_outlined,
        'Port Why reads ports on Windows only, for now',
      );
    }
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error case final error?) {
      return message(
        Icons.error_outline_rounded,
        'Could not read the open ports',
        detail: '$error',
        action: FilledButton.tonal(
          onPressed: controller.refresh,
          child: const Text('Try again'),
        ),
      );
    }
    if (controller.entries.isEmpty) {
      return message(Icons.check_circle_outline_rounded, 'No ports are open');
    }

    final query = controller.query.trim();
    return message(
      Icons.filter_alt_off_outlined,
      query.isEmpty
          ? 'Nothing under ${controller.scope.label} right now'
          : 'No open port matches “$query”',
      detail: query.isNotEmpty && controller.scope != ScopeFilter.all
          ? 'Searching within ${controller.scope.label} only.'
          : null,
      action: TextButton(
        onPressed: onClearFilters,
        child: const Text('Show all ports'),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});

  final PortsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: 11.5,
    );
    final updated = controller.lastUpdated;
    final restricted = controller.restrictedProcessCount;
    final shown = controller.visible.length;
    final total = controller.entries.length;

    return Row(
      children: [
        Text(
          [
            if (shown != total) 'Showing $shown of $total',
            if (updated != null) 'Updated ${clockTime(updated)}',
            if (controller.error != null && updated != null)
              'last refresh failed',
          ].join('  ·  '),
          style: style,
        ),
        const Spacer(),
        if (restricted > 0)
          Tooltip(
            message:
                'These belong to Windows or another user. Their folder and '
                'command line are only visible to an administrator.',
            child: Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 13, color: style?.color),
                const SizedBox(width: 4),
                Text(
                  '${countOf(restricted, 'process', plural: 'processes')} '
                  'hidden from non-administrators',
                  style: style,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
