import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Where the favourite ports are kept between runs.
abstract interface class FavoritesStore {
  /// The saved ports, or null if none were ever saved.
  List<int>? load();

  void save(List<int> ports);
}

FavoritesStore createFavoritesStore() {
  final folder = _settingsFolder(Platform.environment);
  return folder == null
      ? MemoryFavoritesStore()
      : FileFavoritesStore(p.join(folder, 'favorites.json'));
}

/// Where each system expects an app to keep its settings.
String? _settingsFolder(Map<String, String> environment) {
  final home = environment['HOME'];
  if (Platform.isWindows) {
    final appData = environment['APPDATA'];
    return appData == null ? null : p.join(appData, 'Port Why');
  }
  if (Platform.isMacOS) {
    return home == null
        ? null
        : p.join(home, 'Library', 'Application Support', 'Port Why');
  }
  final config =
      environment['XDG_CONFIG_HOME'] ?? (home == null ? null : p.join(home, '.config'));
  return config == null ? null : p.join(config, 'port-why');
}

/// Forgets everything when the app closes.
class MemoryFavoritesStore implements FavoritesStore {
  MemoryFavoritesStore([this._ports]);

  List<int>? _ports;

  @override
  List<int>? load() => _ports;

  @override
  void save(List<int> ports) => _ports = [...ports];
}

/// A JSON list of port numbers in a file.
class FileFavoritesStore implements FavoritesStore {
  const FileFavoritesStore(this.path);

  final String path;

  @override
  List<int>? load() {
    try {
      final saved = jsonDecode(File(path).readAsStringSync());
      return saved is List ? saved.whereType<int>().toList() : null;
    } on Exception {
      // Missing or mangled: start again from the defaults.
      return null;
    }
  }

  @override
  void save(List<int> ports) {
    try {
      File(path)
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(ports));
    } on FileSystemException {
      // The favourites still hold for this run; they just will not survive it.
    }
  }
}
