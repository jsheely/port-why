import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models.dart';
import '../state/ports_controller.dart';
import 'format.dart';
import 'tech_icon.dart';

const monoFont = 'Consolas';

/// The list of ports: a sortable header over one expandable row per port.
class PortTable extends StatelessWidget {
  const PortTable({
    super.key,
    required this.controller,
    required this.expanded,
    required this.onToggle,
    required this.onKill,
    required this.onOpenFolder,
    required this.placeholder,
  });

  final PortsController controller;

  /// Ids of the rows whose details are open.
  final Set<String> expanded;
  final ValueChanged<PortEntry> onToggle;
  final ValueChanged<PortEntry> onKill;
  final ValueChanged<PortEntry> onOpenFolder;

  /// Shown instead of the rows when there are none.
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = controller.visible;
    final now = DateTime.now();

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Narrow windows drop the least useful columns rather than squeeze.
          final columns = _Columns(
            showPid: constraints.maxWidth >= 900,
            showOpened: constraints.maxWidth >= 780,
          );
          return Column(
            children: [
              _HeaderRow(controller: controller, columns: columns),
              Divider(height: 1, color: scheme.outlineVariant),
              Expanded(
                child: entries.isEmpty
                    ? placeholder
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return _PortRow(
                            key: ValueKey(entry.id),
                            entry: entry,
                            columns: columns,
                            now: now,
                            showProtocol: controller.includeUdp,
                            isExpanded: expanded.contains(entry.id),
                            killBlockedReason: controller.killBlockedReason(entry),
                            onToggle: () => onToggle(entry),
                            onKill: () => onKill(entry),
                            onOpenFolder: () => onOpenFolder(entry),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Column geometry shared by the header and every row.
class _Columns {
  const _Columns({required this.showPid, required this.showOpened});

  final bool showPid;
  final bool showOpened;

  static const _port = 152.0;
  static const _pid = 76.0;
  static const _opened = 92.0;
  static const _actions = 80.0;
  static const _gap = 16.0;

  Widget arrange({
    required Widget port,
    required Widget project,
    required Widget tech,
    required Widget folder,
    required Widget pid,
    required Widget opened,
    Widget? actions,
  }) {
    Widget flexible(int flex, Widget child) => Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: _gap),
        child: child,
      ),
    );
    return Row(
      children: [
        SizedBox(width: _port, child: port),
        flexible(20, project),
        flexible(24, tech),
        flexible(26, folder),
        if (showPid) SizedBox(width: _pid, child: pid),
        if (showOpened) SizedBox(width: _opened, child: opened),
        SizedBox(width: _actions, child: actions),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.controller, required this.columns});

  final PortsController controller;
  final _Columns columns;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, SortColumn column, {double inset = 0}) => Padding(
      padding: EdgeInsets.only(left: inset),
      child: _HeaderCell(
        label: label,
        isSorted: controller.sortColumn == column,
        ascending: controller.ascending,
        onTap: () => controller.sortBy(column),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: columns.arrange(
        // Lines up with the port number, past the row's expand chevron.
        port: cell('Port', SortColumn.port, inset: 26),
        project: cell('Project', SortColumn.project),
        tech: cell('Opened by', SortColumn.tech),
        folder: cell('Folder', SortColumn.folder),
        pid: cell('PID', SortColumn.pid),
        opened: cell('Opened', SortColumn.opened),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    required this.isSorted,
    required this.ascending,
    required this.onTap,
  });

  final String label;
  final bool isSorted;
  final bool ascending;
  final VoidCallback onTap;

  static const _hitPadding = 4.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSorted
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final button = Tooltip(
      message: 'Sort by ${label.toLowerCase()}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _hitPadding,
            vertical: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
              ),
              if (isSorted) ...[
                const SizedBox(width: 3),
                Icon(
                  ascending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 13,
                  color: color,
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Align(
      alignment: Alignment.centerLeft,
      // Pull back by the hit area's padding so the label, not its hover
      // highlight, lines up with the column's content.
      child: Transform.translate(
        offset: const Offset(-_hitPadding, 0),
        child: button,
      ),
    );
  }
}

class _PortRow extends StatelessWidget {
  const _PortRow({
    super.key,
    required this.entry,
    required this.columns,
    required this.now,
    required this.showProtocol,
    required this.isExpanded,
    required this.killBlockedReason,
    required this.onToggle,
    required this.onKill,
    required this.onOpenFolder,
  });

  final PortEntry entry;
  final _Columns columns;
  final DateTime now;
  final bool showProtocol;
  final bool isExpanded;
  final String? killBlockedReason;
  final VoidCallback onToggle;
  final VoidCallback onKill;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final dim = scheme.onSurfaceVariant;
    final faint = text.bodySmall?.copyWith(color: dim, fontSize: 11.5);
    final process = entry.process;
    final project = entry.project;
    final folder = entry.folder;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isExpanded ? scheme.surfaceContainer : null,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: columns.arrange(
                port: Row(
                  children: [
                    Icon(
                      isExpanded
                          ? Icons.expand_more_rounded
                          : Icons.chevron_right_rounded,
                      size: 18,
                      color: dim,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TwoLines(
                        top: Row(
                          children: [
                            Text(
                              '${entry.port}',
                              style: text.titleMedium?.copyWith(
                                fontFamily: monoFont,
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                              ),
                            ),
                            if (showProtocol) ...[
                              const SizedBox(width: 6),
                              _Tag(entry.protocol.label),
                            ],
                          ],
                        ),
                        bottom: Text(
                          entry.addresses.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: faint?.copyWith(fontFamily: monoFont),
                        ),
                      ),
                    ),
                  ],
                ),
                project: project == null
                    ? Text('—', style: text.bodyMedium?.copyWith(color: dim))
                    : _TwoLines(
                        top: _Clipped(
                          project.name,
                          style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        bottom: _Clipped(
                          project.isDeclared ? project.marker : 'folder name',
                          style: faint,
                        ),
                      ),
                tech: Row(
                  children: [
                    TechIcon(tech: entry.tech, category: entry.category),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TwoLines(
                        top: _Clipped(entry.tech.name, style: text.bodyMedium),
                        bottom: _Clipped(_techSubtitle(entry), style: faint),
                      ),
                    ),
                  ],
                ),
                folder: folder == null
                    ? Tooltip(
                        message: process.restricted
                            ? 'Windows hides this from non-administrators'
                            : 'Unknown',
                        child: Text(
                          '—',
                          style: text.bodyMedium?.copyWith(color: dim),
                        ),
                      )
                    : Tooltip(
                        message: entry.folderIsExeDirectory
                            ? '$folder\n(where the executable lives)'
                            : folder,
                        child: _FolderLabel(folder, nameStyle: text.bodyMedium, pathStyle: faint),
                      ),
                pid: Tooltip(
                  message: process.isInWsl
                      ? 'Process id inside WSL (${process.distro})'
                      : 'Process id',
                  child: Text(
                    // Zero: a container whose process we cannot see.
                    process.pid == 0 ? '—' : '${process.pid}',
                    style: text.bodySmall?.copyWith(
                      fontFamily: monoFont,
                      color: dim,
                    ),
                  ),
                ),
                opened: entry.openedAt == null
                    ? Text('—', style: text.bodySmall?.copyWith(color: dim))
                    : Tooltip(
                        message: 'Port opened ${timestamp(entry.openedAt!)}',
                        child: Text(
                          relativeTime(entry.openedAt!, now),
                          style: text.bodySmall?.copyWith(color: dim),
                        ),
                      ),
                actions: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _RowAction(
                      tooltip: folder == null ? 'No folder known' : 'Open folder',
                      icon: Icons.folder_open_rounded,
                      onPressed: folder == null ? null : onOpenFolder,
                    ),
                    _RowAction(
                      tooltip:
                          killBlockedReason ??
                          (process.container == null
                              ? 'Kill process'
                              : 'Stop container'),
                      icon: Icons.stop_circle_outlined,
                      color: scheme.error,
                      onPressed: killBlockedReason == null ? onKill : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isExpanded) _Details(entry: entry),
        ],
      ),
    );
  }
}

/// The line under the "opened by" name: what it runs on, and where.
String _techSubtitle(PortEntry entry) {
  final process = entry.process;
  if (process.container case final container?) return '${container.name} · Docker';
  final stack = entry.tech.stack.isEmpty ? process.name : entry.tech.stack;
  return process.isInWsl ? '$stack · WSL' : stack;
}

/// An icon button with a fixed footprint, so two always fit the actions column
/// whatever tap-target padding the platform would otherwise add.
class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  static const _size = 36.0;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: _size,
    child: IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      color: color,
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(_size),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
    ),
  );
}

/// A folder shown leaf-first, because the end of a path is what tells two
/// projects apart and an ellipsis would otherwise eat it.
class _FolderLabel extends StatelessWidget {
  const _FolderLabel(this.folder, {this.nameStyle, this.pathStyle});

  final String folder;
  final TextStyle? nameStyle;
  final TextStyle? pathStyle;

  @override
  Widget build(BuildContext context) {
    final name = p.windows.basename(folder);
    final parent = p.windows.dirname(folder);
    if (name.isEmpty || parent == folder) {
      return _Clipped(folder, style: nameStyle?.copyWith(fontFamily: monoFont));
    }
    return _TwoLines(
      top: _Clipped(name, style: nameStyle),
      bottom: _Clipped(parent, style: pathStyle?.copyWith(fontFamily: monoFont)),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.entry});

  final PortEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final process = entry.process;
    final project = entry.project;
    final tech = entry.tech;

    final reach = entry.isAllInterfaces
        ? 'reachable from other machines'
        : entry.isLocalOnly
        ? 'this machine only'
        : null;
    final bound = entry.addresses
        .map((a) => a.contains(':') ? '[$a]:${entry.port}' : '$a:${entry.port}')
        .join(', ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(42, 2, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (process.restricted)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 15, color: scheme.tertiary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Windows only shows this process to administrators, so '
                      'its folder and command line are unknown. Run Port Why '
                      'as administrator to see them.',
                      style: TextStyle(color: scheme.tertiary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (process.distro case final distro?)
            _DetailLine(
              'Runs in',
              [
                'WSL distribution $distro',
                if (process.container case final container?)
                  'Docker container ${container.name}  ·  image ${container.image}',
              ].join('  ·  '),
            ),
          _DetailLine('Command', process.commandLine, mono: true),
          _DetailLine('Executable', process.exePath, mono: true),
          _DetailLine('Working folder', process.cwd, mono: true),
          if (project != null)
            _DetailLine('Project', switch (project.marker) {
              ProjectInfo.folderMarker =>
                '${project.name}  ·  named after its folder, no manifest found',
              ProjectInfo.composeMarker => [
                '${project.name}  ·  Docker Compose project',
                if (project.root.isNotEmpty) 'in ${project.root}',
              ].join(' '),
              _ => '${project.name}  ·  found ${project.marker} in ${project.root}',
            }),
          _DetailLine(
            'Opened by',
            [tech.name, if (tech.stack.isNotEmpty) tech.stack].join('  ·  '),
          ),
          _DetailLine(
            'Listening on',
            [
              '${entry.protocol.label} $bound',
              ?reach,
              if (entry.openedAt != null) 'since ${timestamp(entry.openedAt!)}',
            ].join('  ·  '),
          ),
          if (process.pid != 0)
            _DetailLine(
              'Process',
              [
                '${process.name}  ·  PID ${process.pid}',
                if (process.startedAt != null)
                  'started ${timestamp(process.startedAt!)}',
              ].join('  ·  '),
            ),
          if (process.parentName != null)
            _DetailLine(
              'Started by',
              '${process.parentName}  ·  PID ${process.parentPid}',
            ),
          if (process.services.isNotEmpty)
            _DetailLine('Services', process.services.join(', ')),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value, {this.mono = false});

  final String label;
  final String? value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: mono ? monoFont : null,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TwoLines extends StatelessWidget {
  const _TwoLines({required this.top, required this.bottom});

  final Widget top;
  final Widget bottom;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [top, const SizedBox(height: 1), bottom],
  );
}

/// One line of text that ends in an ellipsis instead of wrapping.
class _Clipped extends StatelessWidget {
  const _Clipped(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.ellipsis,
    style: style,
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
