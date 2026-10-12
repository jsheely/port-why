import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/favorites_store.dart';
import '../data/port_repository.dart';
import '../models.dart';

enum SortColumn { port, project, tech, folder, pid, opened }

enum ScopeFilter {
  all('All'),
  projects('Projects'),
  apps('Apps'),
  system('System');

  const ScopeFilter(this.label);
  final String label;

  bool admits(PortEntry entry) => switch (this) {
    all => true,
    projects => entry.category == PortCategory.project,
    apps => entry.category == PortCategory.app,
    system => entry.category == PortCategory.system,
  };
}

/// Holds the port list and everything the user can do to it: polling,
/// filtering, sorting, killing.
class PortsController extends ChangeNotifier {
  PortsController(
    this._repository, {
    this.pollInterval = const Duration(seconds: 2),
    this.ownPid,
    FavoritesStore? favorites,
  }) : _store = favorites ?? MemoryFavoritesStore();

  final PortRepository _repository;
  final FavoritesStore _store;
  final Duration pollInterval;

  /// This app's own pid, so it never offers to kill itself.
  final int? ownPid;

  Timer? _timer;
  Future<void>? _scanning;
  bool _scanAgain = false;
  bool _freshRequested = false;
  bool _disposed = false;

  List<PortEntry> _entries = const [];
  List<PortEntry> _visible = const [];
  Map<ScopeFilter, int> _counts = const {};

  String _query = '';
  ScopeFilter _scope = ScopeFilter.all;
  bool _includeUdp = false;
  bool _live = true;
  SortColumn _sortColumn = SortColumn.port;
  bool _ascending = false;

  /// What is watched until the user says otherwise: where dev servers
  /// usually land.
  static const defaultFavorites = [3000, 5173, 8080];

  late List<int> _favorites = {...(_store.load() ?? defaultFavorites)}.toList()
    ..sort();

  bool get isSupported => _repository.isSupported;

  /// The operating system the ports belong to.
  HostOs get os => _repository.os;

  /// True until the first scan has come back.
  bool get isLoading => _lastUpdated == null && _error == null;

  Object? get error => _error;
  Object? _error;

  DateTime? get lastUpdated => _lastUpdated;
  DateTime? _lastUpdated;

  /// The rows to show: filtered, then sorted.
  List<PortEntry> get visible => _visible;

  /// Every open port, before filtering.
  List<PortEntry> get entries => _entries;

  /// How many rows each scope would show under the current text filter.
  Map<ScopeFilter, int> get counts => _counts;

  String get query => _query;
  ScopeFilter get scope => _scope;
  bool get includeUdp => _includeUdp;
  bool get isLive => _live;
  SortColumn get sortColumn => _sortColumn;
  bool get ascending => _ascending;

  /// Ports worth watching whether or not anything holds them, lowest first.
  List<int> get favorites => _favorites;

  bool isFavorite(int port) => _favorites.contains(port);

  /// Adds [port] to the favourites or takes it out, and remembers the choice.
  void setFavorite(int port, bool favorite) {
    if (port < 1 || port > 65535 || favorite == isFavorite(port)) return;
    _favorites = [
      for (final other in _favorites)
        if (other != port) other,
      if (favorite) port,
    ]..sort();
    _store.save(_favorites);
    notifyListeners();
  }

  /// Whatever has [port] open right now, whether or not the filters show it.
  List<PortEntry> holdersOf(int port) => [
    for (final entry in _entries)
      if (entry.port == port) entry,
  ];

  /// How many owning processes we could not look inside.
  int get restrictedProcessCount => {
    for (final entry in _entries)
      if (entry.process.restricted)
        // Windows' kernel and idle pids are not processes to look inside.
        // Elsewhere a hidden process has no pid, only an owner.
        if (os != HostOs.windows)
          '${entry.process.pid}:${entry.process.name}'
        else if (entry.process.pid > 4)
          '${entry.process.pid}',
  }.length;

  /// Windows processes that hold ports on behalf of others. A row still
  /// showing one of these is a port we could not trace any further.
  static const _sharedRelays = {'wslrelay.exe', 'wslhost.exe'};

  /// Starts polling. Call once.
  void start() {
    if (!isSupported) return;
    refresh();
    _timer = Timer.periodic(pollInterval, (_) {
      if (_live && _scanning == null) refresh();
    });
  }

  /// Rescans now. With [fresh], project and framework detection is redone for
  /// every process instead of reusing what earlier scans worked out.
  Future<void> refresh({bool fresh = false}) {
    _freshRequested |= fresh;
    final running = _scanning;
    if (running != null) {
      // Whatever prompted this call (a kill, a new setting) may have happened
      // after the running scan read the tables, so go round once more.
      _scanAgain = true;
      return running;
    }
    return _scanning = _scan().whenComplete(() => _scanning = null);
  }

  Future<void> _scan() async {
    do {
      _scanAgain = false;
      final fresh = _freshRequested;
      _freshRequested = false;
      try {
        final entries = await _repository.scan(
          includeUdp: _includeUdp,
          fresh: fresh,
        );
        if (_disposed) return;
        _entries = entries;
        _error = null;
        _lastUpdated = DateTime.now();
      } catch (error) {
        if (_disposed) return;
        _error = error;
      }
      _recompute();
    } while (_scanAgain);
  }

  set query(String value) {
    if (value == _query) return;
    _query = value;
    _recompute();
  }

  set scope(ScopeFilter value) {
    if (value == _scope) return;
    _scope = value;
    _recompute();
  }

  set includeUdp(bool value) {
    if (value == _includeUdp) return;
    _includeUdp = value;
    notifyListeners();
    refresh();
  }

  set isLive(bool value) {
    if (value == _live) return;
    _live = value;
    notifyListeners();
    if (value) refresh();
  }

  /// Sorts by [column]; choosing the current column again flips the direction.
  void sortBy(SortColumn column) {
    if (column == _sortColumn) {
      _ascending = !_ascending;
    } else {
      _sortColumn = column;
      // Ports and times read best newest/highest first, names A to Z.
      _ascending = column != SortColumn.port && column != SortColumn.opened;
    }
    _recompute();
  }

  /// Why [entry]'s process must not be killed from here, or null if it may be.
  String? killBlockedReason(PortEntry entry) {
    final process = entry.process;
    // A container is stopped as a whole, and a pid inside WSL is a Linux
    // one, so none of the rules below apply to either.
    if (process.isInWsl || process.container != null) return null;
    final name = process.name.toLowerCase();
    if (os != HostOs.windows) {
      if (process.pid <= 0) {
        return 'This belongs to another user, and only root can see which '
            'process it is';
      }
      if (process.pid == 1) return '${os.label} cannot run without ${process.name}';
      if (process.pid == ownPid) return 'This is Port Why itself';
      if (_criticalPosixProcesses.contains(name)) {
        return '${os.label} cannot run without ${process.name}';
      }
      return null;
    }
    if (process.pid <= 4) return 'This is the Windows kernel';
    if (process.pid == ownPid) return 'This is Port Why itself';
    if (_criticalProcesses.contains(name)) {
      return 'Windows cannot run without ${process.name}';
    }
    if (_sharedRelays.contains(name)) {
      return 'This is the relay for every WSL port, and what is behind this '
          'one could not be identified';
    }
    return null;
  }

  static const _criticalProcesses = {
    'smss.exe',
    'csrss.exe',
    'wininit.exe',
    'winlogon.exe',
    'services.exe',
    'lsass.exe',
  };

  static const _criticalPosixProcesses = {
    'launchd',
    'kernel_task',
    'windowserver',
    'loginwindow',
    'systemd',
    'init',
  };

  /// Other ports that would close if [entry]'s process were killed.
  List<PortEntry> portsSharingProcess(PortEntry entry) => [
    for (final other in _entries)
      if (other.ownerKey == entry.ownerKey && other.id != entry.id) other,
  ];

  Future<KillResult> kill(PortEntry entry) async {
    final result = await _repository.kill(entry);
    await refresh();
    return result;
  }

  Future<bool> openFolder(PortEntry entry) async {
    final folder = entry.folder;
    return folder != null && await _repository.openFolder(folder);
  }

  void _recompute() {
    final terms = _query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((term) => term.isEmpty);
    final matching = [
      for (final entry in _entries)
        if (terms.every(entry.searchText.contains)) entry,
    ];
    _counts = {
      for (final scope in ScopeFilter.values)
        scope: matching.where(scope.admits).length,
    };
    _visible = matching.where(_scope.admits).toList()..sort(_compare);
    if (!_disposed) notifyListeners();
  }

  int _compare(PortEntry a, PortEntry b) {
    final primary = switch (_sortColumn) {
      SortColumn.port => _directed(a.port.compareTo(b.port)),
      SortColumn.pid => _directed(a.process.pid.compareTo(b.process.pid)),
      SortColumn.project => _nullsLast(a.project?.name, b.project?.name, _text),
      SortColumn.tech => _directed(_text(a.tech.name, b.tech.name)),
      SortColumn.folder => _nullsLast(a.folder, b.folder, _text),
      SortColumn.opened => _nullsLast(
        a.openedAt,
        b.openedAt,
        (DateTime x, DateTime y) => x.compareTo(y),
      ),
    };
    if (primary != 0) return primary;
    // Ties fall back to the default order so the list never shuffles.
    final byPort = b.port.compareTo(a.port);
    if (byPort != 0) return byPort;
    final byProtocol = a.protocol.index.compareTo(b.protocol.index);
    return byProtocol != 0 ? byProtocol : a.process.pid.compareTo(b.process.pid);
  }

  int _directed(int comparison) => _ascending ? comparison : -comparison;

  /// Rows with nothing in the sorted column sink to the bottom either way.
  int _nullsLast<T>(T? a, T? b, int Function(T, T) compare) {
    if (a == null || b == null) {
      return a == null ? (b == null ? 0 : 1) : -1;
    }
    return _directed(compare(a, b));
  }

  static int _text(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
