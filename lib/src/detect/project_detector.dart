import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';

/// A project found on disk, plus what its manifest declares. The extra detail
/// lets the tech detector tell a Vue app from a React app when both are just
/// "node running Vite".
class DetectedProject {
  const DetectedProject({
    required this.info,
    this.dependencies = const {},
    this.manifestText = '',
  });

  final ProjectInfo info;

  /// Dependency names from manifests that list them as keys (package.json,
  /// composer.json, pubspec.yaml).
  final Set<String> dependencies;

  /// Lower-cased manifest text, for manifests with no cheap structured form.
  final String manifestText;

  bool uses(String dependency) => dependencies.contains(dependency);

  /// True when [word] appears in the manifest as a whole package name.
  bool mentions(String word) => RegExp(
    '(^|[^a-z0-9_.-])${RegExp.escape(word)}(\$|[^a-z0-9_-])',
  ).hasMatch(manifestText);
}

/// Works out which project a process belongs to by walking up from the places
/// it is running in, looking for a manifest.
class ProjectDetector {
  ProjectDetector({Map<String, String>? environment})
    : _env = environment ?? Platform.environment {
    _home = _normalize(_env['USERPROFILE'] ?? _env['HOME']);
    _homeParts = _home != null && _home.startsWith('/') ? _posixParts(_home) : null;
    _offLimits = [
      for (final key in const [
        'SystemRoot',
        'ProgramFiles',
        'ProgramFiles(x86)',
        'ProgramW6432',
        'ProgramData',
        'LOCALAPPDATA',
        'APPDATA',
      ])
        ?_normalize(_env[key]),
      if (_home != null && !_home.startsWith('/')) '$_home\\appdata',
    ];
  }

  final Map<String, String> _env;
  late final String? _home;

  /// [_home] in parts, when it is a macOS or Linux one.
  late final List<String>? _homeParts;
  late final List<String> _offLimits;
  final _inspected = <String, _Inspection>{};

  /// Directories that belong to a dependency, not to the project using it.
  /// A path through one of these is rewound to the directory containing it.
  static const _dependencyDirs = {
    'node_modules',
    '.venv',
    'venv',
    'site-packages',
    '.dart_tool',
    '.pub-cache',
    '.nuget',
    '.cargo',
    '.rustup',
    '.gradle',
    '.m2',
    '.pyenv',
    '.nvm',
  };

  /// Finds the project for a process, trying its working directory, then any
  /// paths on its command line, then the folder its executable lives in.
  ///
  /// With [allowFolderName], a process with no manifest anywhere is named
  /// after its working directory, which is usually what the developer calls
  /// the thing they ran there.
  DetectedProject? detect({
    String? cwd,
    String? commandLine,
    String? exePath,
    bool allowFolderName = true,
  }) {
    final starts = <String>{
      ?cwd,
      ..._pathsIn(commandLine),
      if (exePath != null) pathContextOf(exePath).dirname(exePath),
    };
    for (final start in starts) {
      final found = _findUp(_rewind(start));
      if (found != null) return found;
    }

    if (allowFolderName && cwd != null && _isNameworthy(cwd)) {
      return DetectedProject(
        info: ProjectInfo(
          name: pathContextOf(cwd).basename(cwd),
          root: cwd,
          marker: ProjectInfo.folderMarker,
        ),
      );
    }
    return null;
  }

  /// Whether a bare folder name says anything. `Documents`, `Desktop` and the
  /// other folders directly under the home directory do not.
  bool _isNameworthy(String directory) {
    if (!isProjectTerritory(directory)) return false;
    final dir = _normalize(directory)!;
    if (dir.startsWith('/') ? _posixParts(dir) : _wslParts(dir) case final parts?) {
      final home = _homeDepth(parts);
      return home == 0 || parts.length > home + 1;
    }
    return _normalize(p.windows.dirname(directory)) != _home;
  }

  /// False for drive roots, the home folder itself, and anywhere under Windows,
  /// Program Files, AppData or a dot-folder in the home directory (`.bun`,
  /// `.cargo`, `.vscode`). Installed software and tool caches live there, not
  /// projects, and they are full of stray manifests: every Electron app and
  /// every global npm install ships a package.json.
  ///
  /// A macOS or Linux folder is judged by the equivalent rules for those
  /// systems, and so is one inside a WSL distribution
  /// (`\\wsl.localhost\Ubuntu\...`).
  bool isProjectTerritory(String directory) {
    final dir = _normalize(directory);
    if (dir == null) return false;
    if (dir.startsWith('/')) return _isPosixProjectTerritory(_posixParts(dir));
    if (p.windows.dirname(dir) == dir) return false;
    if (_wslParts(dir) case final parts?) return _isPosixProjectTerritory(parts);
    if (dir == _home) return false;
    if (_home != null && dir.startsWith('$_home\\.')) return false;
    return !_offLimits.any((root) => dir == root || dir.startsWith('$root\\'));
  }

  static final _wslShare = RegExp(r'^\\\\(?:wsl\.localhost|wsl\$)\\[^\\]+\\?(.*)$');

  /// Top-level macOS and Linux directories that hold the system, not anyone's
  /// work. `/opt`, `/srv`, `/mnt` and `/Volumes` are deliberately absent:
  /// projects do live there.
  static const _posixSystemDirs = {
    'bin',
    'boot',
    'dev',
    'etc',
    'init',
    'lib',
    'lib32',
    'lib64',
    'libx32',
    'proc',
    'run',
    'sbin',
    'snap',
    'sys',
    'tmp',
    'usr',
    'var',
    // macOS
    'Applications',
    'Library',
    'System',
    'cores',
    'private',
  };

  /// Folders in a home directory that hold installed software and its data.
  static const _homeSystemDirs = {'Applications', 'Library', 'snap'};

  /// A macOS or Linux path, already normalized, split into parts.
  static List<String> _posixParts(String normalized) =>
      p.posix.split(normalized).skip(1).toList();

  /// The path below the distribution root, split into parts, if [normalized]
  /// is inside a WSL distribution.
  static List<String>? _wslParts(String normalized) {
    final match = _wslShare.firstMatch(normalized);
    if (match == null) return null;
    return match[1]!.split(r'\').where((part) => part.isNotEmpty).toList();
  }

  /// How many leading parts make up a home directory: our own, or by the
  /// usual shapes `/home/me`, `/Users/me` and `/root`.
  int _homeDepth(List<String> parts) {
    final own = _homeParts;
    if (own != null && own.isNotEmpty && parts.length >= own.length) {
      var isWithin = true;
      for (var i = 0; i < own.length && isWithin; i++) {
        isWithin = parts[i] == own[i];
      }
      if (isWithin) return own.length;
    }
    return switch (parts) {
      ['root', ...] => 1,
      ['home' || 'Users', _, ...] => 2,
      _ => 0,
    };
  }

  bool _isPosixProjectTerritory(List<String> parts) {
    if (parts.isEmpty) return false;
    final home = _homeDepth(parts);
    if (home == 0) {
      if (parts.length == 1 && (parts.first == 'home' || parts.first == 'Users')) {
        return false;
      }
      // Homebrew keeps the packages it installs under /opt.
      if (parts case ['opt', 'homebrew', ...]) return false;
      return !_posixSystemDirs.contains(parts.first);
    }
    // Not the home directory itself, nor a dot-folder inside it (~/.nvm).
    return parts.length > home &&
        !parts[home].startsWith('.') &&
        !_homeSystemDirs.contains(parts[home]);
  }

  DetectedProject? _findUp(String start) {
    _Inspection? firstWeak;
    var dir = start;
    for (var depth = 0; depth < 24 && isProjectTerritory(dir); depth++) {
      final here = _inspected[_normalize(dir)!] ??= _inspect(dir);
      if (here.project != null) return here.project;
      if (here.weakMarker != null) firstWeak ??= here;
      // A repository root is a hard boundary: whatever sits above it is a
      // different project.
      if (here.isGitRoot) break;
      dir = pathContextOf(dir).dirname(dir);
    }
    if (firstWeak == null) return null;
    return DetectedProject(
      info: ProjectInfo(
        name: pathContextOf(firstWeak.directory).basename(firstWeak.directory),
        root: firstWeak.directory,
        marker: firstWeak.weakMarker!,
      ),
    );
  }

  String _rewind(String directory) {
    final path = pathContextOf(directory);
    final parts = path.split(directory);
    final cut = parts.indexWhere((s) => _dependencyDirs.contains(s.toLowerCase()));
    return cut <= 0 ? directory : path.joinAll(parts.take(cut));
  }

  /// Absolute paths mentioned on a command line, as directories.
  Iterable<String> _pathsIn(String? commandLine) sync* {
    if (commandLine == null) return;
    var yielded = 0;
    // Skip the first token: it is the executable, which is tried last.
    for (final token in splitCommandLine(commandLine).skip(1)) {
      final value = token.startsWith('-') && token.contains('=')
          ? token.substring(token.indexOf('=') + 1)
          : token;
      // Read off this machine's disk, so by this machine's rules.
      if (!p.isAbsolute(value) || value.length < 4) continue;
      final type = _typeOf(value);
      if (type == FileSystemEntityType.notFound) continue;
      yield type == FileSystemEntityType.directory ? value : p.dirname(value);
      if (++yielded == 6) return;
    }
  }

  static FileSystemEntityType _typeOf(String path) {
    try {
      return FileSystemEntity.typeSync(path);
    } on FileSystemException {
      return FileSystemEntityType.notFound;
    }
  }

  _Inspection _inspect(String directory) {
    final path = pathContextOf(directory);
    final names = <String, String>{};
    try {
      for (final entity in Directory(directory).listSync(followLinks: false)) {
        final name = path.basename(entity.path);
        names[name.toLowerCase()] = name;
      }
    } on FileSystemException {
      return _Inspection(directory);
    }

    String read(String lowerName) =>
        _readText(path.join(directory, names[lowerName]!));
    DetectedProject project(
      String marker,
      String? name, {
      Set<String> dependencies = const {},
      String text = '',
    }) => DetectedProject(
      info: ProjectInfo(
        name: name == null || name.trim().isEmpty
            ? path.basename(directory)
            : name.trim(),
        root: directory,
        marker: marker,
      ),
      dependencies: dependencies,
      manifestText: text.toLowerCase(),
    );

    // A Python backend often shares a folder with another manifest, so what it
    // requires is always read alongside whichever manifest names the project.
    final requirements = names.containsKey('requirements.txt')
        ? read('requirements.txt')
        : '';

    DetectedProject? found;
    if (names.containsKey('package.json')) {
      final json = _decodeJson(read('package.json'));
      found = project(
        'package.json',
        _string(json['name']),
        text: requirements,
        dependencies: {
          for (final section in const [
            'dependencies',
            'devDependencies',
            'peerDependencies',
          ])
            if (json[section] case final Map<String, dynamic> deps) ...deps.keys,
        },
      );
    } else if (names.containsKey('pubspec.yaml')) {
      final text = read('pubspec.yaml');
      found = project(
        'pubspec.yaml',
        _first(text, r'^name:\s*([\w.-]+)'),
        dependencies: {
          for (final m in RegExp(r'^  ([a-z_][\w]*):', multiLine: true).allMatches(text))
            m[1]!,
        },
      );
    } else if (names.containsKey('cargo.toml')) {
      final text = read('cargo.toml');
      found = project(
        'Cargo.toml',
        _first(_tomlSection(text, 'package'), r'''^name\s*=\s*["']([^"']+)'''),
        text: text,
      );
    } else if (names.containsKey('pyproject.toml')) {
      final text = read('pyproject.toml');
      found = project(
        'pyproject.toml',
        _first(_tomlSection(text, 'project'), r'''^name\s*=\s*["']([^"']+)''') ??
            _first(
              _tomlSection(text, 'tool.poetry'),
              r'''^name\s*=\s*["']([^"']+)''',
            ),
        text: '$text\n$requirements',
      );
    } else if (names.containsKey('go.mod')) {
      final text = read('go.mod');
      final module = _first(text, r'^module\s+(\S+)');
      found = project('go.mod', module?.split('/').last, text: text);
    } else if (_withExtension(names, const ['.sln', '.slnx']) case final sln?) {
      found = project(sln, p.basenameWithoutExtension(sln));
    } else if (_withExtension(names, const ['.csproj', '.fsproj', '.vbproj'])
        case final proj?) {
      found = project(
        proj,
        p.basenameWithoutExtension(proj),
        text: read(proj.toLowerCase()),
      );
    } else if (names.containsKey('pom.xml')) {
      final text = read('pom.xml');
      final ownCoordinates = text.replaceAll(
        RegExp(r'<parent>.*?</parent>', dotAll: true),
        '',
      );
      found = project(
        'pom.xml',
        _first(ownCoordinates, r'<artifactId>\s*([^<\s]+)\s*</artifactId>'),
        text: text,
      );
    } else if (_firstPresent(names, const [
          'settings.gradle',
          'settings.gradle.kts',
          'build.gradle',
          'build.gradle.kts',
        ])
        case final gradle?) {
      final texts = [
        for (final file in const [
          'settings.gradle',
          'settings.gradle.kts',
          'build.gradle',
          'build.gradle.kts',
        ])
          if (names.containsKey(file)) read(file),
      ].join('\n');
      found = project(
        gradle,
        _first(texts, r'''rootProject\.name\s*=\s*["']([^"']+)'''),
        text: texts,
      );
    } else if (names.containsKey('composer.json')) {
      final json = _decodeJson(read('composer.json'));
      found = project(
        'composer.json',
        _string(json['name']),
        dependencies: {
          if (json['require'] case final Map<String, dynamic> deps) ...deps.keys,
        },
      );
    } else if (names.containsKey('mix.exs')) {
      final text = read('mix.exs');
      found = project('mix.exs', _first(text, r'app:\s*:(\w+)'), text: text);
    } else if (_firstPresent(names, const ['deno.json', 'deno.jsonc'])
        case final deno?) {
      found = project(
        deno,
        _string(_decodeJson(read(deno.toLowerCase()))['name']),
      );
    } else if (names.containsKey('gemfile')) {
      found = project('Gemfile', null, text: read('gemfile'));
    } else if (names.containsKey('requirements.txt')) {
      found = project('requirements.txt', null, text: requirements);
    }

    return _Inspection(
      directory,
      project: found,
      isGitRoot: names.containsKey('.git'),
      weakMarker: _firstPresent(names, const [
        '.git',
        'manage.py',
        'setup.py',
        'pipfile',
        'cmakelists.txt',
        'makefile',
        'docker-compose.yml',
        'docker-compose.yaml',
        'compose.yml',
        'compose.yaml',
      ]),
    );
  }

  static String? _firstPresent(Map<String, String> names, List<String> wanted) {
    for (final name in wanted) {
      if (names[name] case final actual?) return actual;
    }
    return null;
  }

  static String? _withExtension(Map<String, String> names, List<String> extensions) {
    for (final extension in extensions) {
      for (final entry in names.entries) {
        if (entry.key.endsWith(extension)) return entry.value;
      }
    }
    return null;
  }

  static String _readText(String path) {
    try {
      final file = File(path);
      if (file.lengthSync() > 1024 * 1024) return '';
      return utf8.decode(file.readAsBytesSync(), allowMalformed: true);
    } on FileSystemException {
      return '';
    }
  }

  static Map<String, dynamic> _decodeJson(String text) {
    try {
      final value = jsonDecode(text);
      return value is Map<String, dynamic> ? value : const {};
    } on FormatException {
      return const {};
    }
  }

  static String? _string(Object? value) => value is String ? value : null;

  static String? _first(String text, String pattern) =>
      RegExp(pattern, multiLine: true).firstMatch(text)?[1];

  /// The body of `[name]` in a TOML document, up to the next table header.
  static String _tomlSection(String text, String name) {
    final header = RegExp(
      '^\\[${RegExp.escape(name)}\\]\\s*\$',
      multiLine: true,
    ).firstMatch(text);
    if (header == null) return '';
    final rest = text.substring(header.end);
    final next = RegExp(r'^\[', multiLine: true).firstMatch(rest);
    return next == null ? rest : rest.substring(0, next.start);
  }

  static String? _normalize(String? path) {
    if (path == null || path.isEmpty) return null;
    // Away from Windows a name's case is part of the name.
    if (path.startsWith('/')) return p.posix.normalize(path);
    final normalized = p.windows.normalize(path).toLowerCase();
    // Keep the separator on a drive root ("c:\") so dirname() is a fixed point.
    return normalized.length > 3 && normalized.endsWith('\\')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }
}

class _Inspection {
  const _Inspection(
    this.directory, {
    this.project,
    this.isGitRoot = false,
    this.weakMarker,
  });

  final String directory;
  final DetectedProject? project;
  final bool isGitRoot;
  final String? weakMarker;
}

/// Splits a command line into arguments, honouring double quotes.
List<String> splitCommandLine(String commandLine) {
  final arguments = <String>[];
  final current = StringBuffer();
  var quoted = false;
  var started = false;
  for (final char in commandLine.split('')) {
    if (char == '"') {
      quoted = !quoted;
      started = true;
    } else if (!quoted && (char == ' ' || char == '\t')) {
      if (started) arguments.add(current.toString());
      current.clear();
      started = false;
    } else {
      current.write(char);
      started = true;
    }
  }
  if (started) arguments.add(current.toString());
  return arguments;
}
