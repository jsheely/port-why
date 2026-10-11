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
    _home = _normalize(_env['USERPROFILE']);
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
      if (_home != null) '$_home\\appdata',
    ];
  }

  final Map<String, String> _env;
  late final String? _home;
  late final List<String> _offLimits;
  final _inspected = <String, _Inspection>{};

  static final _path = p.windows;

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
      if (exePath != null) _path.dirname(exePath),
    };
    for (final start in starts) {
      final found = _findUp(_rewind(start));
      if (found != null) return found;
    }

    if (allowFolderName && cwd != null && _isNameworthy(cwd)) {
      return DetectedProject(
        info: ProjectInfo(
          name: _path.basename(cwd),
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
    return _normalize(_path.dirname(directory)) != _home;
  }

  /// False for drive roots, the home folder itself, and anywhere under Windows,
  /// Program Files, AppData or a dot-folder in the home directory (`.bun`,
  /// `.cargo`, `.vscode`). Installed software and tool caches live there, not
  /// projects, and they are full of stray manifests: every Electron app and
  /// every global npm install ships a package.json.
  bool isProjectTerritory(String directory) {
    final dir = _normalize(directory);
    if (dir == null || _path.dirname(dir) == dir) return false;
    if (dir == _home) return false;
    if (_home != null && dir.startsWith('$_home\\.')) return false;
    return !_offLimits.any((root) => dir == root || dir.startsWith('$root\\'));
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
      dir = _path.dirname(dir);
    }
    if (firstWeak == null) return null;
    return DetectedProject(
      info: ProjectInfo(
        name: _path.basename(firstWeak.directory),
        root: firstWeak.directory,
        marker: firstWeak.weakMarker!,
      ),
    );
  }

  String _rewind(String directory) {
    final parts = _path.split(directory);
    final cut = parts.indexWhere((s) => _dependencyDirs.contains(s.toLowerCase()));
    return cut <= 0 ? directory : _path.joinAll(parts.take(cut));
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
      if (!_path.isAbsolute(value) || value.length < 4) continue;
      final type = _typeOf(value);
      if (type == FileSystemEntityType.notFound) continue;
      yield type == FileSystemEntityType.directory ? value : _path.dirname(value);
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
    final names = <String, String>{};
    try {
      for (final entity in Directory(directory).listSync(followLinks: false)) {
        final name = _path.basename(entity.path);
        names[name.toLowerCase()] = name;
      }
    } on FileSystemException {
      return _Inspection(directory);
    }

    String read(String lowerName) =>
        _readText(_path.join(directory, names[lowerName]!));
    DetectedProject project(
      String marker,
      String? name, {
      Set<String> dependencies = const {},
      String text = '',
    }) => DetectedProject(
      info: ProjectInfo(
        name: name == null || name.trim().isEmpty
            ? _path.basename(directory)
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
      found = project(sln, _path.basenameWithoutExtension(sln));
    } else if (_withExtension(names, const ['.csproj', '.fsproj', '.vbproj'])
        case final proj?) {
      found = project(
        proj,
        _path.basenameWithoutExtension(proj),
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
    final normalized = _path.normalize(path).toLowerCase();
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

/// Splits a Windows command line into arguments, honouring double quotes.
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
