import 'dart:async';
import 'dart:io' show pid;
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/favorites_store.dart';
import '../data/port_repository.dart';
import '../models.dart';
import '../state/ports_controller.dart';
import 'ambient.dart';
import 'format.dart';
import 'glass.dart';
import 'kill_dialog.dart';
import 'port_deck.dart';
import 'theme.dart';
import 'title_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.repository, this.favorites});

  final PortRepository repository;
  final FavoritesStore? favorites;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late final PortsController _controller = PortsController(
    widget.repository,
    ownPid: pid,
    favorites: widget.favorites,
  );
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _expanded = <String>{};

  /// The panels taking shape when the window opens.
  late final _boot = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  /// One turn of the rescan button.
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  bool _booted = false;

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_booted) return;
    _booted = true;
    if (Ambient.allowsMotion(context)) {
      _boot.forward();
    } else {
      _boot.value = 1;
    }
  }

  @override
  void dispose() {
    _boot.dispose();
    _spin.dispose();
    _controller.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _search.clear();
    _controller.query = '';
  }

  /// Narrows the deck to one port, or widens it again if it already is.
  void _showPort(int port) {
    final filter = ':$port';
    if (_controller.query.trim() == filter) return _clearSearch();
    _search.text = filter;
    _controller
      ..scope = ScopeFilter.all
      ..query = filter;
  }

  void _rescan() {
    _spin.forward(from: 0);
    _controller.refresh(fresh: true);
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
        const SingleActivator(LogicalKeyboardKey.f5): _rescan,
        const SingleActivator(LogicalKeyboardKey.escape): _clearSearch,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              const CyberBackdrop(),
              // Right to the top of the window: the control panel is its
              // title bar.
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => Stack(
                    fit: StackFit.expand,
                    children: [
                      PortDeck(
                        controller: _controller,
                        expanded: _expanded,
                        onToggle: _toggle,
                        onKill: _kill,
                        onOpenFolder: _openFolder,
                        onFavorite: (entry) => _controller.setFavorite(
                          entry.port,
                          !_controller.isFavorite(entry.port),
                        ),
                        footerClearance: _StatusBar.height + 12,
                        header: _ControlPanel(
                          controller: _controller,
                          search: _search,
                          searchFocus: _searchFocus,
                          boot: _boot,
                          spin: _spin,
                          onClear: _clearSearch,
                          onRescan: _rescan,
                          onShowPort: _showPort,
                        ),
                        placeholder: _Placeholder(
                          controller: _controller,
                          onClearFilters: () {
                            _clearSearch();
                            _controller.scope = ScopeFilter.all;
                          },
                        ),
                      ),
                      Positioned(
                        left: PortDeck.margin,
                        right: PortDeck.margin,
                        bottom: 10,
                        child: _StatusBar(controller: _controller, boot: _boot),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What everything is steered from, in two panes the deck scrolls beneath.
/// The first hangs from the top of the window as its title bar: what the app
/// is, the search and the switches, beside the window's own buttons. The
/// second floats under it: the favorites, the sort order and the scope.
class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.controller,
    required this.search,
    required this.searchFocus,
    required this.boot,
    required this.spin,
    required this.onClear,
    required this.onRescan,
    required this.onShowPort,
  });

  final PortsController controller;
  final TextEditingController search;
  final FocusNode searchFocus;
  final Animation<double> boot;
  final Animation<double> spin;
  final VoidCallback onClear;
  final VoidCallback onRescan;
  final ValueChanged<int> onShowPort;

  /// Narrower than these and the brand gives its room to the search: first
  /// the count under the name goes, then the name. The widths are for text
  /// at its normal size, and grow with it.
  static const _withCounts = 1000.0;
  static const _withName = 860.0;

  /// The search stops growing here, so that a wide window keeps some bare
  /// title bar to be dragged by.
  static const _widestSearch = 640.0;

  /// Narrower than this and the scope switch goes on a line of its own,
  /// under the sort order and the favorites.
  static const _oneRow = 940.0;

  @override
  Widget build(BuildContext context) {
    final field = _SearchField(
      controller: search,
      focusNode: searchFocus,
      hasQuery: controller.query.isNotEmpty,
      onChanged: (value) => controller.query = value,
      onClear: onClear,
    );
    final scope = _ScopeSwitch(
      selected: controller.scope,
      counts: controller.counts,
      onSelected: (scope) => controller.scope = scope,
    );
    final udp = _Pill(
      label: 'UDP',
      tooltip: 'Also list UDP ports',
      color: Neon.violet,
      isLit: controller.includeUdp,
      onTap: () => controller.includeUdp = !controller.includeUdp,
    );
    final live = _Pill(
      label: controller.isLive ? 'LIVE' : 'PAUSED',
      tooltip: controller.isLive
          ? 'Updating every ${controller.pollInterval.inSeconds} s. '
                'Click to pause.'
          : 'Paused. Click to resume live updates.',
      color: Neon.green,
      isLit: controller.isLive,
      pulses: true,
      onTap: () => controller.isLive = !controller.isLive,
    );
    final rescan = IconButton(
      tooltip: 'Rescan everything (F5)',
      color: Neon.cyan,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      icon: RotationTransition(
        turns: CurveTween(curve: Curves.easeOutCubic).animate(spin),
        child: const Icon(Icons.refresh_rounded),
      ),
      onPressed: onRescan,
    );
    Widget sideways(Widget child) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: child,
    );

    final bar = LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1);
        return SizedBox(
          height: TitleBar.height,
          child: Padding(
            padding: const EdgeInsets.only(
              left: PortDeck.margin,
              right: TitleBar.buttonsWidth + 6,
            ),
            child: Row(
              children: [
                _Brand(
                  controller: controller,
                  showsName: width >= _withName,
                  showsCounts: width >= _withCounts,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _widestSearch,
                      ),
                      child: TitleBarControl(child: field),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                TitleBarControl(child: udp),
                const SizedBox(width: 8),
                TitleBarControl(child: live),
                const SizedBox(width: 2),
                TitleBarControl(child: rescan),
              ],
            ),
          ),
        );
      },
    );
    // The sort order and the favorites share a line, which slides sideways
    // when the sort order opens out or there are many favorites.
    final watch = sideways(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SortBar(controller: controller),
          Container(
            width: 1,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: Colors.white.withValues(alpha: 0.12),
          ),
          _FavoritesBar(controller: controller, onShowPort: onShowPort),
        ],
      ),
    );
    final filters = LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1);
        if (width >= _oneRow) {
          return Row(
            children: [
              Expanded(child: watch),
              const SizedBox(width: 12),
              scope,
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(width: double.infinity, child: watch),
            Padding(
              padding: const EdgeInsets.only(left: 14, bottom: 7),
              child: sideways(scope),
            ),
          ],
        );
      },
    );

    return AnimatedBuilder(
      animation: boot,
      builder: (context, _) {
        final formed = Curves.easeOutCubic.transform(boot.value);
        return Transform.translate(
          offset: Offset(0, -18 * (1 - formed)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Glass(
                radius: 14,
                cut: 14,
                flatTop: true,
                blur: 26,
                tint: 0.52,
                strength: formed,
                child: FadeTransition(opacity: boot, child: bar),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  PortDeck.margin,
                  10,
                  PortDeck.margin,
                  0,
                ),
                child: Glass(
                  radius: 18,
                  cut: 18,
                  blur: 26,
                  tint: 0.52,
                  strength: formed,
                  padding: const EdgeInsets.only(right: 8),
                  child: FadeTransition(opacity: boot, child: filters),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The app's mark and name, and under the name how much is open. It is the
/// title bar's handle: nothing in it is clicked.
class _Brand extends StatelessWidget {
  const _Brand({
    required this.controller,
    required this.showsName,
    required this.showsCounts,
  });

  final PortsController controller;
  final bool showsName;
  final bool showsCounts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final processes = {for (final e in controller.entries) e.process.pid}.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Neon.cyan, Neon.violet, Neon.pink],
            ),
            boxShadow: [
              BoxShadow(
                color: Neon.cyan.withValues(alpha: 0.45),
                blurRadius: 12,
                offset: const Offset(-2, -2),
              ),
              BoxShadow(
                color: Neon.pink.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(3, 3),
              ),
            ],
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Neon.abyss.withValues(alpha: 0.84),
              borderRadius: BorderRadius.circular(7.5),
            ),
            child: Icon(
              Icons.lan_rounded,
              color: Neon.cyan,
              size: 16,
              shadows: neonGlow(Neon.cyan),
            ),
          ),
        ),
        if (showsName) ...[
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlitchText(
                'PORT WHY',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                  height: 1.15,
                  color: Colors.white,
                  shadows: neonGlow(Neon.cyan, spread: 12, alpha: 0.6),
                ),
              ),
              if (showsCounts)
                Text(
                  controller.isLoading
                      ? 'Reading open ports…'
                      : '${countOf(controller.entries.length, 'open port')} held by '
                            '${countOf(processes, 'process', plural: 'processes')}',
                  maxLines: 1,
                  softWrap: false,
                  style: mono.copyWith(
                    fontSize: 10.5,
                    height: 1.25,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The filter box: a recess in the panel whose edge lights up while it has
/// the keyboard.
class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.hasQuery,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(_SearchField old) {
    super.didUpdateWidget(old);
    if (old.focusNode == widget.focusNode) return;
    old.focusNode.removeListener(_onFocusChanged);
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dim = scheme.onSurfaceVariant;
    final isFocused = widget.focusNode.hasFocus;
    const iconBox = BoxConstraints(minWidth: 40, minHeight: 32);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: well(
        radius: 11,
        edge: isFocused ? Neon.cyan.withValues(alpha: 0.85) : null,
        glow: [
          BoxShadow(
            color: Neon.cyan.withValues(alpha: isFocused ? 0.32 : 0),
            blurRadius: 14,
          ),
        ],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        onChanged: widget.onChanged,
        style: mono.copyWith(fontSize: 13, color: scheme.onSurface),
        // A terminal's block caret.
        cursorWidth: 7,
        cursorRadius: Radius.zero,
        cursorColor: Neon.cyan.withValues(alpha: 0.75),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          // Lower than the middle: the line leaves more room over its
          // capitals than under them, and the icons sit on its middle.
          contentPadding: const EdgeInsets.only(top: 11, bottom: 5),
          hintText: 'Filter by port, project, process, folder…  (Ctrl+F)',
          hintStyle: mono.copyWith(
            fontSize: 12.5,
            color: dim.withValues(alpha: 0.75),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 19,
            color: isFocused ? Neon.cyan : dim,
          ),
          prefixIconConstraints: iconBox,
          suffixIcon: widget.hasQuery
              ? IconButton(
                  tooltip: 'Clear filter (Esc)',
                  icon: const Icon(Icons.close_rounded, size: 17),
                  color: dim,
                  // No taller than the field, or the field grows to hold
                  // it and leaves the text at the top.
                  padding: EdgeInsets.zero,
                  constraints: iconBox,
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: widget.onClear,
                )
              : null,
          suffixIconConstraints: iconBox,
        ),
      ),
    );
  }
}

/// The scope filter as a switch: a droplet of light runs to the chosen
/// segment, stretching on the way and settling when it gets there.
class _ScopeSwitch extends StatefulWidget {
  const _ScopeSwitch({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final ScopeFilter selected;

  /// How many ports each scope would show.
  final Map<ScopeFilter, int> counts;
  final ValueChanged<ScopeFilter> onSelected;

  @override
  State<_ScopeSwitch> createState() => _ScopeSwitchState();
}

class _ScopeSwitchState extends State<_ScopeSwitch>
    with SingleTickerProviderStateMixin {
  late final _travel = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
    value: 1,
  );

  /// The segment the droplet last left.
  late ScopeFilter _from = widget.selected;

  final _track = GlobalKey();
  final _segments = {
    for (final scope in ScopeFilter.values) scope: GlobalKey(),
  };

  @override
  void didUpdateWidget(_ScopeSwitch old) {
    super.didUpdateWidget(old);
    if (old.selected == widget.selected) return;
    _from = old.selected;
    _travel.forward(from: 0);
  }

  @override
  void dispose() {
    _travel.dispose();
    super.dispose();
  }

  /// Where a segment lies along the track. The segments are as wide as their
  /// labels, so this is only known once they are laid out, which they are by
  /// the time anything paints.
  Rect _boundsOf(ScopeFilter scope) {
    final track = _track.currentContext!.findRenderObject()! as RenderBox;
    final segment =
        _segments[scope]!.currentContext!.findRenderObject()! as RenderBox;
    return segment.localToGlobal(Offset.zero, ancestor: track) & segment.size;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: well(radius: 19),
      child: CustomPaint(
        key: _track,
        painter: _DropletPainter(
          travel: _travel,
          from: _from,
          to: widget.selected,
          boundsOf: _boundsOf,
          color: Neon.cyan,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final scope in ScopeFilter.values)
              InkWell(
                key: _segments[scope],
                customBorder: const StadiumBorder(),
                onTap: () => widget.onSelected(scope),
                child: Container(
                  height: 30,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 220),
                    style: TextStyle(
                      fontFamily: displayFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scope == widget.selected
                          ? Colors.white
                          : scheme.onSurfaceVariant,
                    ),
                    child: Text.rich(
                      TextSpan(
                        text: scope.label,
                        children: [
                          TextSpan(
                            text: '  ${widget.counts[scope] ?? 0}',
                            style: mono.copyWith(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w400,
                              color: scope == widget.selected
                                  ? Neon.cyan
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DropletPainter extends CustomPainter {
  _DropletPainter({
    required this.travel,
    required this.from,
    required this.to,
    required this.boundsOf,
    required this.color,
  }) : super(repaint: travel);

  final Animation<double> travel;
  final ScopeFilter from;
  final ScopeFilter to;
  final Rect Function(ScopeFilter scope) boundsOf;
  final Color color;

  // The front edge races ahead and the back edge catches up, overshooting a
  // little, which is what makes it look poured rather than pushed.
  static const _front = Interval(0, 0.6, curve: Curves.easeOutCubic);
  static const _back = Interval(0.2, 1, curve: Curves.easeOutBack);

  @override
  void paint(Canvas canvas, Size size) {
    final start = boundsOf(from);
    final end = boundsOf(to);
    final headsRight = end.left >= start.left;
    final front = _front.transform(travel.value);
    final back = _back.transform(travel.value);
    final droplet = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        lerpDouble(start.left, end.left, headsRight ? back : front)!,
        0,
        lerpDouble(start.right, end.right, headsRight ? front : back)!,
        size.height,
      ),
      Radius.circular(size.height / 2),
    );

    canvas
      ..drawRRect(
        droplet,
        Paint()
          ..color = color.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 9),
      )
      ..drawRRect(
        droplet,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.36),
              color.withValues(alpha: 0.12),
            ],
          ).createShader(droplet.outerRect),
      )
      ..drawRRect(
        droplet.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withValues(alpha: 0.9),
      );
  }

  // The segments resize with their counts without anything here changing, so
  // there is no telling when the droplet is still where it was.
  @override
  bool shouldRepaint(_DropletPainter old) => true;
}

/// A small switch with a lamp in it, lit in [color] while it is on.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.tooltip,
    required this.color,
    required this.isLit,
    required this.onTap,
    this.pulses = false,
  });

  final String label;
  final String tooltip;
  final Color color;
  final bool isLit;
  final VoidCallback onTap;

  /// Whether the lamp sends out rings while lit.
  final bool pulses;

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          height: 32,
          padding: const EdgeInsets.only(left: 6, right: 13),
          decoration: well(
            radius: 18,
            edge: isLit ? color.withValues(alpha: 0.75) : null,
            glow: [
              BoxShadow(
                color: color.withValues(alpha: isLit ? 0.28 : 0),
                blurRadius: 12,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PulseDot(
                color: isLit ? color : dim.withValues(alpha: 0.55),
                active: isLit,
                pulses: pulses,
              ),
              const SizedBox(width: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                style: caption.copyWith(
                  fontFamily: displayFont,
                  color: isLit ? color : dim,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The ports being watched, each saying what holds it or that it is free.
class _FavoritesBar extends StatelessWidget {
  const _FavoritesBar({required this.controller, required this.onShowPort});

  final PortsController controller;
  final ValueChanged<int> onShowPort;

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'FAVORITES',
          style: caption.copyWith(color: dim.withValues(alpha: 0.6)),
        ),
        const SizedBox(width: 12),
        for (final port in controller.favorites) ...[
          _FavoriteChip(
            key: ValueKey('favorite:$port'),
            port: port,
            holders: controller.holdersOf(port),
            isShown: controller.query.trim() == ':$port',
            onTap: () => onShowPort(port),
            onRemove: () => controller.setFavorite(port, false),
          ),
          const SizedBox(width: 8),
        ],
        _AddFavorite(onAdd: (port) => controller.setFavorite(port, true)),
      ],
    );
  }
}

class _FavoriteChip extends StatelessWidget {
  const _FavoriteChip({
    super.key,
    required this.port,
    required this.holders,
    required this.isShown,
    required this.onTap,
    required this.onRemove,
  });

  final int port;

  /// What has the port open; empty while it is free.
  final List<PortEntry> holders;

  /// Whether the deck is narrowed to this port.
  final bool isShown;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurfaceVariant;
    final holder = holders.firstOrNull;
    final color = holder == null ? dim : Neon.of(holder.category);
    final others = {for (final entry in holders) entry.ownerKey}.length - 1;
    final click = isShown
        ? 'Click to show every port again.'
        : 'Click to show only this port.';

    return Tooltip(
      message: holder == null
          ? 'Nothing is holding port $port'
          : 'Held by ${holder.process.container?.name ?? holder.process.name}'
                '${others > 0 ? ' and $others more' : ''}. $click',
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          height: 30,
          padding: const EdgeInsets.only(left: 4, right: 3),
          decoration: well(
            radius: 15,
            edge: holder == null && !isShown
                ? null
                : color.withValues(alpha: isShown ? 0.95 : 0.55),
            glow: [
              BoxShadow(
                color: color.withValues(alpha: isShown ? 0.34 : 0),
                blurRadius: 12,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PulseDot(
                color: holder == null ? dim.withValues(alpha: 0.55) : color,
                active: holder != null,
                pulses: false,
              ),
              Text(
                '$port',
                style: mono.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: holder == null ? dim : color,
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  holder == null
                      ? 'free'
                      : [
                          holder.project?.name ?? holder.tech.name,
                          if (others > 0) '+$others',
                        ].join(' '),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: holder == null ? dim.withValues(alpha: 0.7) : null,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              SizedBox.square(
                dimension: 24,
                child: IconButton(
                  tooltip: 'Stop watching port $port',
                  icon: const Icon(Icons.close_rounded, size: 13),
                  padding: EdgeInsets.zero,
                  color: dim.withValues(alpha: 0.7),
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onRemove,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A plus that opens into a box to type a port number in.
class _AddFavorite extends StatefulWidget {
  const _AddFavorite({required this.onAdd});

  final ValueChanged<int> onAdd;

  @override
  State<_AddFavorite> createState() => _AddFavoriteState();
}

class _AddFavoriteState extends State<_AddFavorite> {
  final _text = TextEditingController();
  late final _focus = FocusNode()..addListener(_onFocusChanged);
  bool _isOpen = false;

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  // Clicking away abandons it.
  void _onFocusChanged() {
    if (!_focus.hasFocus && _isOpen) _close();
  }

  void _close() => setState(() {
    _isOpen = false;
    _text.clear();
  });

  void _submit(String value) {
    final port = int.tryParse(value);
    if (port != null) widget.onAdd(port);
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dim = scheme.onSurfaceVariant;
    if (!_isOpen) {
      return SizedBox.square(
        dimension: 30,
        child: IconButton(
          tooltip: 'Watch another port',
          icon: const Icon(Icons.add_rounded, size: 17),
          padding: EdgeInsets.zero,
          color: Neon.cyan,
          style: IconButton.styleFrom(
            minimumSize: const Size.square(30),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => setState(() => _isOpen = true),
        ),
      );
    }
    return Container(
      width: 84,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: well(radius: 15, edge: Neon.cyan.withValues(alpha: 0.85)),
      child: TextField(
        controller: _text,
        focusNode: _focus,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(5),
        ],
        onSubmitted: _submit,
        style: mono.copyWith(fontSize: 12.5, color: scheme.onSurface),
        cursorColor: Neon.cyan.withValues(alpha: 0.75),
        decoration: InputDecoration.collapsed(
          hintText: 'port',
          hintStyle: mono.copyWith(
            fontSize: 12.5,
            color: dim.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }
}

/// What to order the deck by. Only the current order shows until the pointer
/// is over it, when the others slide out to be chosen from. Choosing the
/// current order again reverses it.
class _SortBar extends StatefulWidget {
  const _SortBar({required this.controller});

  final PortsController controller;

  @override
  State<_SortBar> createState() => _SortBarState();
}

class _SortBarState extends State<_SortBar> {
  static const _labels = {
    SortColumn.port: 'Port',
    SortColumn.project: 'Project',
    SortColumn.tech: 'Opened by',
    SortColumn.folder: 'Folder',
    SortColumn.pid: 'PID',
    SortColumn.opened: 'Opened',
  };

  static const _sliding = Duration(milliseconds: 240);

  /// How long the pointer may stray off the bar before it shuts, so that a
  /// hand drifting on its way along the options does not lose them.
  static const _grace = Duration(milliseconds: 450);

  bool _isOpen = false;
  Timer? _shutting;

  @override
  void dispose() {
    _shutting?.cancel();
    super.dispose();
  }

  void _open() {
    _shutting?.cancel();
    setState(() => _isOpen = true);
  }

  void _shutSoon() {
    _shutting?.cancel();
    _shutting = Timer(_grace, () => setState(() => _isOpen = false));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final dim = Theme.of(context).colorScheme.onSurfaceVariant;
    return MouseRegion(
      onEnter: (_) => _open(),
      onExit: (_) => _shutSoon(),
      // The padding is the pane's own, taken inside so that the whole depth
      // of the pane counts as being over the bar.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 0, 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // For a finger, which cannot hover. A mouse is already over it.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                if (details.kind == PointerDeviceKind.mouse) return;
                setState(() => _isOpen = !_isOpen);
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 7, bottom: 7, right: 6),
                child: Text(
                  'SORT',
                  style: caption.copyWith(color: dim.withValues(alpha: 0.6)),
                ),
              ),
            ),
            for (final MapEntry(key: column, value: label) in _labels.entries)
              _slideOut(
                isOut: _isOpen || controller.sortColumn == column,
                child: _SortChip(
                  label: label,
                  isSorted: controller.sortColumn == column,
                  ascending: controller.ascending,
                  onTap: () => controller.sortBy(column),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// [child] at its own width while [isOut], and shut to nothing otherwise.
  Widget _slideOut({required bool isOut, required Widget child}) => ClipRect(
    child: AnimatedAlign(
      alignment: Alignment.centerLeft,
      widthFactor: isOut ? 1 : 0,
      duration: _sliding,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: isOut ? 1 : 0,
        duration: _sliding,
        child: ExcludeFocus(excluding: !isOut, child: child),
      ),
    ),
  );
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.isSorted,
    required this.ascending,
    required this.onTap,
  });

  final String label;
  final bool isSorted;
  final bool ascending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message: 'Sort by ${label.toLowerCase()}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: caption.copyWith(
                  fontFamily: displayFont,
                  color: isSorted ? Neon.cyan : dim,
                  shadows: neonGlow(
                    Neon.cyan,
                    spread: 9,
                    alpha: isSorted ? 0.7 : 0,
                  ),
                ),
                child: Text(label.toUpperCase()),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: isSorted
                    ? Padding(
                        padding: const EdgeInsets.only(left: 3),
                        // Flips over rather than swapping one arrow for another.
                        child: AnimatedRotation(
                          turns: ascending ? 0 : 0.5,
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutBack,
                          child: const Icon(
                            Icons.arrow_upward_rounded,
                            size: 13,
                            color: Neon.cyan,
                          ),
                        ),
                      )
                    : const SizedBox(height: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the deck shows when it has no cards, and why.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.controller, required this.onClearFilters});

  final PortsController controller;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dim = scheme.onSurfaceVariant;

    Widget message(
      IconData icon,
      String title, {
      Color color = Neon.cyan,
      String? detail,
      Widget? action,
    }) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: color, shadows: neonGlow(color, spread: 18)),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: scheme.onSurface,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: mono.copyWith(fontSize: 12, color: dim),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action],
          ],
        ),
      ),
    );

    if (!controller.isSupported) {
      return message(
        Icons.desktop_windows_outlined,
        'Port Why reads ports on Windows only, for now',
        color: Neon.violet,
      );
    }
    if (controller.isLoading) return const Center(child: _Scanner());
    if (controller.error case final error?) {
      return message(
        Icons.error_outline_rounded,
        'Could not read the open ports',
        color: Neon.pink,
        detail: '$error',
        action: FilledButton(
          onPressed: controller.refresh,
          child: const Text('Try again'),
        ),
      );
    }
    if (controller.entries.isEmpty) {
      return message(
        Icons.check_circle_outline_rounded,
        'No ports are open',
        color: Neon.green,
      );
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

/// Two arcs turning against each other, for the moment before the first scan
/// comes back.
class _Scanner extends StatelessWidget {
  const _Scanner();

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(46),
    painter: _ScannerPainter(Ambient.of(context)),
  );
}

class _ScannerPainter extends CustomPainter {
  _ScannerPainter(this.clock) : super(repaint: clock);

  final AmbientClock clock;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    void arc(double inset, double turn, Color color) {
      final ring = Rect.fromCircle(
        center: centre,
        radius: size.shortestSide / 2 - inset,
      );
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas
        ..drawArc(
          ring,
          turn,
          math.pi * 1.2,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..color = color.withValues(alpha: 0.6)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        )
        ..drawArc(ring, turn, math.pi * 1.2, false, stroke);
    }

    arc(2, clock.value * 4.2, Neon.cyan);
    arc(11, -clock.value * 5.6, Neon.pink);
  }

  @override
  bool shouldRepaint(_ScannerPainter old) => old.clock != clock;
}

/// Two small panes afloat at the foot of the window: how fresh the list is,
/// and how much of it Windows is hiding.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller, required this.boot});

  final PortsController controller;
  final Animation<double> boot;

  static const height = 30.0;

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurfaceVariant;
    final style = mono.copyWith(fontSize: 11, color: dim);
    final updated = controller.lastUpdated;
    final restricted = controller.restrictedProcessCount;
    final shown = controller.visible.length;
    final total = controller.entries.length;
    final status = [
      if (shown != total) 'Showing $shown of $total',
      if (updated != null) 'Updated ${clockTime(updated)}',
      if (controller.error != null && updated != null) 'last refresh failed',
    ].join('  ·  ');

    Widget pane(Widget child) => AnimatedBuilder(
      animation: boot,
      builder: (context, child) => Glass(
        radius: height / 2,
        blur: 18,
        tint: 0.62,
        strength: Curves.easeOutCubic.transform(boot.value),
        child: FadeTransition(opacity: boot, child: child),
      ),
      child: SizedBox(
        height: height,
        child: Center(
          widthFactor: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: child,
          ),
        ),
      ),
    );

    return Row(
      children: [
        Expanded(
          child: status.isEmpty
              ? const SizedBox.shrink()
              : Align(
                  alignment: Alignment.centerLeft,
                  // Only a readout: let clicks and the scroll wheel through
                  // to the cards underneath.
                  child: IgnorePointer(
                    child: pane(
                      Text(
                        status,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: style,
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 12),
        if (restricted > 0)
          Tooltip(
            message:
                'These belong to Windows or another user. Their folder and '
                'command line are only visible to an administrator.',
            child: pane(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline_rounded, size: 13, color: Neon.yellow),
                  const SizedBox(width: 6),
                  Text(
                    '${countOf(restricted, 'process', plural: 'processes')} '
                    'hidden from non-administrators',
                    style: style,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
