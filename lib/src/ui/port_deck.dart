import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models.dart';
import '../state/ports_controller.dart';
import 'ambient.dart';
import 'format.dart';
import 'glass.dart';
import 'tech_icon.dart';
import 'theme.dart';

const _gap = 12.0;

/// The ports as a deck of glass cards, as many abreast as fit, scrolling
/// beneath [header]. A card's details open in a drawer under its row.
class PortDeck extends StatefulWidget {
  const PortDeck({
    super.key,
    required this.controller,
    required this.header,
    required this.expanded,
    required this.onToggle,
    required this.onKill,
    required this.onOpenFolder,
    required this.onFavorite,
    required this.placeholder,
    this.footerClearance = 0,
  });

  final PortsController controller;

  /// Stays at the top while the cards slide under it.
  final Widget header;

  /// Ids of the cards whose details are open.
  final Set<String> expanded;
  final ValueChanged<PortEntry> onToggle;
  final ValueChanged<PortEntry> onKill;
  final ValueChanged<PortEntry> onOpenFolder;

  /// Adds the card's port to the favourites, or takes it out.
  final ValueChanged<PortEntry> onFavorite;

  /// Shown instead of the cards when there are none.
  final Widget placeholder;

  /// Room to leave under the last row for whatever floats over the deck.
  final double footerClearance;

  /// The space between the deck and the edge of the window.
  static const margin = 14.0;

  @override
  State<PortDeck> createState() => _PortDeckState();
}

/// How a card that has just appeared should make its entrance.
class _Arrival {
  const _Arrival({
    required this.at,
    required this.order,
    required this.announced,
  });

  /// When it appeared, on the deck's stopwatch.
  final Duration at;

  /// Its place in the cascade when many arrive together.
  final int order;

  /// True for a port that opened while the list was already up, which is
  /// worth drawing the eye to.
  final bool announced;

  /// A card first built later than this (scrolled to, say) just appears.
  static const window = Duration(milliseconds: 900);
}

class _PortDeckState extends State<PortDeck> {
  static const _minCardWidth = 340.0;
  static const _maxColumns = 4;

  /// More new ports than this at once is the list filling up (the first scan,
  /// UDP switched on) rather than news.
  static const _crowd = 6;

  final _stopwatch = Stopwatch()..start();
  Set<String> _known = const {};
  bool _loaded = false;
  Map<String, _Arrival> _arrivals = {};
  bool _allowsMotion = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_track);
    _track();
  }

  @override
  void didUpdateWidget(PortDeck old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_track);
      widget.controller.addListener(_track);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_track);
    super.dispose();
  }

  /// Notes which ports are new since the last scan.
  void _track() {
    final controller = widget.controller;
    if (controller.isLoading) return;
    final ids = {for (final entry in controller.entries) entry.id};
    final fresh = ids.difference(_known);
    final announced = _loaded && fresh.length <= _crowd;
    _known = ids;
    _loaded = true;
    if (fresh.isEmpty) return;

    var order = 0;
    _arrivals = {
      for (final entry in controller.visible)
        if (fresh.contains(entry.id))
          entry.id: _Arrival(
            at: _stopwatch.elapsed,
            order: announced ? 0 : order++,
            announced: announced,
          ),
    };
  }

  /// Hands a card its entrance, once: a card rebuilt elsewhere in the deck
  /// (a re-sort moves most of them) does not make it again.
  _Arrival? _takeArrival(PortEntry entry) {
    final arrival = _arrivals.remove(entry.id);
    final isRecent =
        arrival != null && _stopwatch.elapsed - arrival.at < _Arrival.window;
    return _allowsMotion && isRecent ? arrival : null;
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.controller.visible;
    final now = DateTime.now();
    _allowsMotion = Ambient.allowsMotion(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - 2 * PortDeck.margin;
        final columns = ((width + _gap) / (_minCardWidth + _gap))
            .floor()
            .clamp(1, _maxColumns);
        return CustomScrollView(
          slivers: [
            PinnedHeaderSliver(child: widget.header),
            if (entries.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: widget.placeholder,
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  PortDeck.margin,
                  _gap,
                  PortDeck.margin,
                  widget.footerClearance,
                ),
                sliver: SliverList.builder(
                  itemCount: (entries.length / columns).ceil(),
                  itemBuilder: (context, row) {
                    final first = row * columns;
                    final last = math.min(first + columns, entries.length);
                    return _DeckRow(
                      deck: widget,
                      entries: entries.sublist(first, last),
                      columns: columns,
                      now: now,
                      takeArrival: _takeArrival,
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One row of cards, and under it the drawers of whichever of them are open.
class _DeckRow extends StatelessWidget {
  const _DeckRow({
    required this.deck,
    required this.entries,
    required this.columns,
    required this.now,
    required this.takeArrival,
  });

  final PortDeck deck;
  final List<PortEntry> entries;
  final int columns;
  final DateTime now;
  final _Arrival? Function(PortEntry entry) takeArrival;

  @override
  Widget build(BuildContext context) {
    final controller = deck.controller;
    return Padding(
      padding: const EdgeInsets.only(bottom: _gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var slot = 0; slot < columns; slot++) ...[
                if (slot > 0) const SizedBox(width: _gap),
                Expanded(
                  child: slot >= entries.length
                      ? const SizedBox.shrink()
                      : _PortCard(
                          key: ValueKey(entries[slot].id),
                          entry: entries[slot],
                          now: now,
                          showProtocol: controller.includeUdp,
                          isExpanded: deck.expanded.contains(entries[slot].id),
                          isFavorite: controller.isFavorite(entries[slot].port),
                          killBlockedReason: controller.killBlockedReason(
                            entries[slot],
                          ),
                          takeArrival: () => takeArrival(entries[slot]),
                          onToggle: () => deck.onToggle(entries[slot]),
                          onKill: () => deck.onKill(entries[slot]),
                          onOpenFolder: () => deck.onOpenFolder(entries[slot]),
                          onFavorite: () => deck.onFavorite(entries[slot]),
                        ),
                ),
              ],
            ],
          ),
          for (final (slot, entry) in entries.indexed)
            _Drawer(
              key: ValueKey('details:${entry.id}'),
              entry: entry,
              isOpen: deck.expanded.contains(entry.id),
              // Where along the row its card sits, as a fraction.
              anchor: (slot + 0.5) / columns,
              onClose: () => deck.onToggle(entry),
            ),
        ],
      ),
    );
  }
}

class _PortCard extends StatefulWidget {
  const _PortCard({
    super.key,
    required this.entry,
    required this.now,
    required this.showProtocol,
    required this.isExpanded,
    required this.isFavorite,
    required this.killBlockedReason,
    required this.takeArrival,
    required this.onToggle,
    required this.onKill,
    required this.onOpenFolder,
    required this.onFavorite,
  });

  final PortEntry entry;
  final DateTime now;
  final bool showProtocol;
  final bool isExpanded;
  final bool isFavorite;
  final String? killBlockedReason;

  /// Asked once, as the card is created: how to make an entrance, or null to
  /// simply be there.
  final _Arrival? Function() takeArrival;
  final VoidCallback onToggle;
  final VoidCallback onKill;
  final VoidCallback onOpenFolder;
  final VoidCallback onFavorite;

  @override
  State<_PortCard> createState() => _PortCardState();
}

class _PortCardState extends State<_PortCard> with TickerProviderStateMixin {
  static const _forming = Duration(milliseconds: 460);

  /// The cascade: each card starts this long after the one before, up to a
  /// point, so the last of a long list is not kept waiting.
  static const _stagger = Duration(milliseconds: 38);
  static const _longestWait = 12;

  /// How long a newly opened port keeps glowing.
  static const _flaring = Duration(milliseconds: 2800);

  /// How much of the card's corner is sliced off.
  static const _cut = 14.0;

  late final AnimationController _entrance;

  /// From 0 to 1 as the card takes shape.
  late final Animation<double> _form;

  /// The light a newly opened port gives off: up fast, then slowly away.
  late final Animation<double> _flare;

  /// How brightly the card is lit by being hovered or open.
  late final AnimationController _lit;

  final _pointer = ValueNotifier<Offset?>(null);
  bool _hovered = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    final arrival = widget.takeArrival();
    if (arrival == null) {
      _entrance = AnimationController(vsync: this, value: 1);
      _form = kAlwaysCompleteAnimation;
      _flare = kAlwaysDismissedAnimation;
    } else if (arrival.announced) {
      _entrance = AnimationController(vsync: this, duration: _flaring);
      _form = _entrance.drive(_formingWithin(_flaring));
      _flare = _entrance.drive(
        TweenSequence([
          TweenSequenceItem(
            tween: Tween(begin: 0.0, end: 1.0),
            weight: 12,
          ),
          TweenSequenceItem(
            tween: Tween(
              begin: 1.0,
              end: 0.0,
            ).chain(CurveTween(curve: Curves.easeInOutSine)),
            weight: 88,
          ),
        ]),
      );
    } else {
      final wait = _stagger * math.min(arrival.order, _longestWait);
      _entrance = AnimationController(vsync: this, duration: wait + _forming);
      _form = _entrance.drive(_formingWithin(wait + _forming, after: wait));
      _flare = kAlwaysDismissedAnimation;
    }
    if (arrival != null) _entrance.forward();
    _lit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: _brightness,
    );
  }

  /// The card's forming, as a stretch of a longer animation.
  static CurveTween _formingWithin(
    Duration whole, {
    Duration after = Duration.zero,
  }) => CurveTween(
    curve: Interval(
      after.inMicroseconds / whole.inMicroseconds,
      (after + _forming).inMicroseconds / whole.inMicroseconds,
      curve: Curves.easeOutCubic,
    ),
  );

  double get _brightness => widget.isExpanded
      ? 1
      : _hovered
      ? 0.7
      : 0;

  @override
  void didUpdateWidget(_PortCard old) {
    super.didUpdateWidget(old);
    if (old.isExpanded != widget.isExpanded) _lit.animateTo(_brightness);
  }

  void _setHovered(bool hovered) {
    _hovered = hovered;
    if (!hovered) _pointer.value = null;
    _lit.animateTo(_brightness);
  }

  @override
  void dispose() {
    _entrance.dispose();
    _lit.dispose();
    _pointer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Neon.of(widget.entry.category);
    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      onHover: (event) => _pointer.value = event.localPosition,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedBuilder(
          animation: Listenable.merge([_entrance, _lit]),
          builder: (context, content) {
            final form = _form.value;
            final lit = _lit.value;
            return Transform.translate(
              // Rises into place, and lifts a little towards the pointer.
              offset: Offset(0, 18 * (1 - form) - 2 * lit),
              child: Transform.scale(
                scale: 0.96 + 0.04 * form,
                child: Glass(
                  overBackdrop: true,
                  accent: accent,
                  cut: _cut,
                  strength: form,
                  emphasis: math.max(lit, _flare.value),
                  pointer: _pointer,
                  child: content!,
                ),
              ),
            );
          },
          child: FadeTransition(
            opacity: _form,
            child: InkWell(
              onTap: widget.onToggle,
              onHighlightChanged: (pressed) =>
                  setState(() => _pressed = pressed),
              // Nothing else keeps the splash inside the card's outline.
              customBorder: const GlassBorder(cut: _cut),
              splashColor: accent.withValues(alpha: 0.14),
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: _CardFace(card: widget, accent: accent),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What is written on a card: the port and what opened it, then the project
/// and the folder it runs in.
class _CardFace extends StatelessWidget {
  const _CardFace({required this.card, required this.accent});

  final _PortCard card;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dim = scheme.onSurfaceVariant;
    final body = TextStyle(fontSize: 13, height: 1.25, color: scheme.onSurface);
    final faint = TextStyle(fontSize: 11.5, height: 1.25, color: dim);
    final readout = faint.merge(mono);

    final entry = card.entry;
    final process = entry.process;
    final project = entry.project;
    final folder = entry.folder;
    final blocked = card.killBlockedReason;

    // Leaf first: the end of a path is what tells two projects apart, and an
    // ellipsis would otherwise eat it.
    final leaf = folder == null ? '' : p.windows.basename(folder);
    final parent = folder == null ? '' : p.windows.dirname(folder);
    final isSplit = leaf.isNotEmpty && parent != folder;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TechIcon(tech: entry.tech, category: entry.category, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '${entry.port}',
                        style: mono.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          color: accent,
                          shadows: neonGlow(accent),
                        ),
                      ),
                      if (card.showProtocol) ...[
                        const SizedBox(width: 8),
                        _Tag(entry.protocol.label, color: accent),
                      ],
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Clipped(
                          entry.addresses.join(', '),
                          style: readout,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 170),
                        child: _Clipped(
                          entry.tech.name,
                          style: body.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Clipped(_techSubtitle(entry), style: faint),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _CardAction(
              tooltip: card.isFavorite
                  ? 'Stop watching port ${entry.port}'
                  : 'Watch port ${entry.port}',
              icon: card.isFavorite
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              color: card.isFavorite ? Neon.yellow : dim,
              onPressed: card.onFavorite,
            ),
            _CardAction(
              tooltip: folder == null ? 'No folder known' : 'Open folder',
              icon: Icons.folder_open_rounded,
              color: Neon.cyan,
              onPressed: folder == null ? null : card.onOpenFolder,
            ),
            _CardAction(
              tooltip:
                  blocked ??
                  (process.container == null
                      ? 'Kill process'
                      : 'Stop container'),
              icon: Icons.stop_circle_outlined,
              color: scheme.error,
              onPressed: blocked == null ? card.onKill : null,
            ),
          ],
        ),
        const SizedBox(height: 9),
        _Line(
          icon: Icons.inventory_2_outlined,
          primary: project?.name,
          primaryStyle: body.copyWith(fontWeight: FontWeight.w600),
          secondary: project == null
              ? null
              : project.isDeclared
              ? project.marker
              : 'folder name',
          secondaryStyle: faint,
          missingStyle: body.copyWith(color: dim),
          trailing: Tooltip(
            message: process.isInWsl
                ? 'Process id inside WSL (${process.distro})'
                : 'Process id',
            // Zero: a container whose process we cannot see.
            child: Text(
              process.pid == 0 ? '—' : 'PID ${process.pid}',
              style: readout,
            ),
          ),
        ),
        const SizedBox(height: 4),
        _Line(
          icon: Icons.folder_outlined,
          primary: folder == null
              ? null
              : isSplit
              ? leaf
              : folder,
          primaryStyle: isSplit ? body : body.merge(mono),
          secondary: isSplit ? parent : null,
          secondaryStyle: readout,
          missingStyle: body.copyWith(color: dim),
          tooltip: folder == null
              ? (process.restricted
                    ? 'Windows hides this from non-administrators'
                    : 'Unknown')
              : entry.folderIsExeDirectory
              ? '$folder\n(where the executable lives)'
              : folder,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (entry.openedAt case final openedAt?)
                Tooltip(
                  message: 'Port opened ${timestamp(openedAt)}',
                  child: Text(relativeTime(openedAt, card.now), style: readout),
                ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: card.isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                child: Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: card.isExpanded ? accent : dim,
                ),
              ),
            ],
          ),
        ),
      ],
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

/// One line of a card: an icon saying what it is, a name, a quieter note
/// beside it, and a readout pinned to the right.
class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.primary,
    required this.primaryStyle,
    required this.secondary,
    required this.secondaryStyle,
    required this.missingStyle,
    required this.trailing,
    this.tooltip,
  });

  final IconData icon;

  /// Null when there is nothing to say, which shows as a dash.
  final String? primary;
  final TextStyle primaryStyle;
  final String? secondary;
  final TextStyle secondaryStyle;
  final TextStyle missingStyle;
  final Widget trailing;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final primary = this.primary;
    final secondary = this.secondary;
    Widget label = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (primary == null)
          Text('—', style: missingStyle)
        else if (secondary == null)
          Flexible(child: _Clipped(primary, style: primaryStyle))
        else ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: _Clipped(primary, style: primaryStyle),
          ),
          const SizedBox(width: 8),
          Flexible(child: _Clipped(secondary, style: secondaryStyle)),
        ],
      ],
    );
    if (tooltip case final tooltip?) {
      label = Tooltip(message: tooltip, child: label);
    }
    return SizedBox(
      height: 20,
      child: Row(
        children: [
          Icon(icon, size: 14, color: missingStyle.color),
          const SizedBox(width: 8),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: label),
          ),
          const SizedBox(width: 10),
          trailing,
        ],
      ),
    );
  }
}

/// An icon button with a fixed footprint, so three always fit a card's corner
/// whatever tap-target padding the platform would otherwise add.
class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  static const _size = 34.0;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: _size,
    child: IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        foregroundColor: color.withValues(alpha: 0.85),
        hoverColor: color.withValues(alpha: 0.16),
        highlightColor: color.withValues(alpha: 0.24),
        minimumSize: const Size.square(_size),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
    ),
  );
}

/// A card's details, which slide open in a pane under its row.
class _Drawer extends StatefulWidget {
  const _Drawer({
    super.key,
    required this.entry,
    required this.isOpen,
    required this.anchor,
    required this.onClose,
  });

  final PortEntry entry;
  final bool isOpen;

  /// Where along the pane's top edge its card is, from 0 to 1.
  final double anchor;
  final VoidCallback onClose;

  @override
  State<_Drawer> createState() => _DrawerState();
}

class _DrawerState extends State<_Drawer> with SingleTickerProviderStateMixin {
  late final _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    reverseDuration: const Duration(milliseconds: 200),
    value: widget.isOpen ? 1 : 0,
  );
  late final _unfold = CurvedAnimation(
    parent: _slide,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void didUpdateWidget(_Drawer old) {
    super.didUpdateWidget(old);
    if (old.isOpen == widget.isOpen) return;
    if (widget.isOpen) {
      _slide.forward();
    } else {
      _slide.reverse();
    }
  }

  @override
  void dispose() {
    _unfold.dispose();
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Neon.of(widget.entry.category);
    return AnimatedBuilder(
      animation: _slide,
      builder: (context, details) {
        if (_slide.isDismissed) return const SizedBox.shrink();
        return SizeTransition(
          sizeFactor: _unfold,
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: _gap),
            child: Glass(
              overBackdrop: true,
              accent: accent,
              cut: 16,
              tint: 0.58,
              strength: _unfold.value,
              emphasis: 0.3,
              child: CustomPaint(
                foregroundPainter: _TetherPainter(widget.anchor, accent),
                child: FadeTransition(opacity: _unfold, child: details),
              ),
            ),
          ),
        );
      },
      child: _Details(
        entry: widget.entry,
        accent: accent,
        onClose: widget.onClose,
      ),
    );
  }
}

/// A bar of light on a drawer's top edge, under the card it belongs to.
class _TetherPainter extends CustomPainter {
  const _TetherPainter(this.anchor, this.color);

  final double anchor;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width * anchor, 1.2);
    const reach = Offset(34, 0);
    final bar = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(
        centre - reach,
        centre + reach,
        Paint()
          ..color = color
          ..strokeWidth = 5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      )
      ..drawLine(centre - reach, centre + reach, bar);
  }

  @override
  bool shouldRepaint(_TetherPainter old) =>
      old.anchor != anchor || old.color != color;
}

class _Details extends StatelessWidget {
  const _Details({
    required this.entry,
    required this.accent,
    required this.onClose,
  });

  final PortEntry entry;
  final Color accent;
  final VoidCallback onClose;

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
      padding: const EdgeInsets.fromLTRB(18, 10, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // With several cards abreast, the drawer has to say whose it is.
              Text(
                ':${entry.port}',
                style: mono.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: accent,
                  shadows: neonGlow(accent),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Clipped(
                  [tech.name, ?project?.name].join('  ·  '),
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              _CardAction(
                tooltip: 'Close details',
                icon: Icons.close_rounded,
                color: scheme.onSurfaceVariant,
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 4),
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
          _DetailLine('Command', process.commandLine, isMono: true),
          _DetailLine('Executable', process.exePath, isMono: true),
          _DetailLine('Working folder', process.cwd, isMono: true),
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
  const _DetailLine(this.label, this.value, {this.isMono = false});

  final String label;
  final String? value;
  final bool isMono;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: 12, height: 1.4, color: scheme.onSurface);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Padding(
              // Sits the small capitals on the value's first baseline.
              padding: const EdgeInsets.only(top: 2.5),
              child: Text(
                label.toUpperCase(),
                style: caption.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: isMono ? style.merge(mono) : style,
            ),
          ),
        ],
      ),
    );
  }
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
  const _Tag(this.label, {required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: color.withValues(alpha: 0.55)),
    ),
    child: Text(
      label,
      style: mono.copyWith(
        fontSize: 9.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: color,
      ),
    ),
  );
}
