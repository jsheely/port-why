import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'project_detector.dart';

/// Works out what opened a port: the framework if the command line or the
/// project's manifest gives it away, otherwise the runtime or program.
///
/// Detection is layered, most specific first:
///
///  1. the runtime, from the executable name (`node.exe` is Node.js);
///  2. the tool, from the command line (`vite`, `uvicorn`, `manage.py`);
///  3. the app framework, from the project's dependencies (Vue behind Vite,
///     FastAPI behind Uvicorn, Express behind a plain `node server.js`).
class TechDetector {
  const TechDetector();

  TechInfo detect({
    required int pid,
    required String processName,
    String? exePath,
    String? commandLine,
    String? parentCommandLine,
    String? cwd,
    DetectedProject? project,
    List<String> services = const [],
    String? description,
  }) {
    final exe = _stem(processName);
    final command = _normalize(commandLine);

    final runtime = _runtimeFor(exe);
    if (runtime != null) {
      return _forRuntime(
        runtime,
        command,
        _normalize(parentCommandLine),
        project,
        // `dotnet app.dll`: the app's own runtimeconfig says if it is a web app.
        dotnetApp: runtime == _dotnet ? _dllOnCommandLine(commandLine, cwd) : null,
      );
    }

    if (_programs[exe] case (final name, final icon)) {
      return TechInfo(name: name, icon: icon);
    }

    final compiled = _forCompiledBinary(exePath, command, project);
    if (compiled != null) return compiled;

    // A family of executables sharing a prefix (steamwebhelper, SpotifyLauncher)
    // gets the family's icon but keeps its own description as the name.
    for (final (pattern, family, icon) in _programFamilies) {
      if (pattern.hasMatch(exe)) {
        return TechInfo(name: description ?? family, icon: icon);
      }
    }

    if (services.isNotEmpty) {
      return TechInfo(
        name: services.length <= 2
            ? services.join(', ')
            : '${services.first} +${services.length - 1} more',
        via: 'Windows service',
        icon: 'windows',
      );
    }

    // Single-file executables built with Bun, Deno or Node carry the runtime's
    // own version resource, so "Bun" there names how it was built, not what
    // it is.
    final displayName = _withoutExe(processName);
    if (description != null) {
      for (final runtime in _runtimes) {
        if (description.toLowerCase().startsWith(runtime.name.toLowerCase())) {
          return TechInfo(
            name: displayName,
            runtime: runtime.name,
            icon: runtime.icon,
          );
        }
      }
    }
    return TechInfo(name: description ?? displayName);
  }

  /// True for language runtimes (`node.exe`, `python.exe`, ...), whose own
  /// identity says nothing until you know what they are running.
  static bool isRuntime(String processName) =>
      _runtimeFor(_stem(processName)) != null;

  /// Every icon key this detector can emit. The UI's icon table must cover
  /// them all; a test enforces that.
  static Set<String> get iconKeys => {
    for (final runtime in _runtimes) ...[
      runtime.icon,
      for (final rule in runtime.rules) ?rule.icon,
      for (final dep in [...runtime.frontend, ...runtime.backend]) ?dep.icon,
    ],
    for (final (_, icon) in _programs.values) ?icon,
    for (final (_, _, icon) in _programFamilies) icon,
    for (final dep in [..._rustCrates, ..._goModules]) ?dep.icon,
    'dotnet', 'blazor', 'flutter', 'dart', 'rust', 'go', 'cplusplus', 'windows',
  };

  TechInfo _forRuntime(
    _Runtime runtime,
    String command,
    String parentCommand,
    DetectedProject? project, {
    String? dotnetApp,
  }) {
    // A worker spawned by the real entry point often has an uninformative
    // command line (multiprocessing forks, cluster workers), so ask its parent.
    final rule = runtime.match(command) ?? runtime.match(parentCommand);

    TechInfo info(String name, String? icon, {String? via}) => TechInfo(
      name: name,
      via: via == name ? null : via,
      runtime: runtime.name == name ? null : runtime.name,
      icon: icon ?? rule?.icon ?? runtime.icon,
    );

    if (rule != null && rule.role == _Role.app) {
      return info(rule.name, rule.icon, via: rule.via);
    }

    final candidates = rule?.role == _Role.bundler
        ? runtime.frontend
        : runtime.backend;
    final framework = _firstUsed(candidates, project);
    if (framework != null) {
      return info(framework.name, framework.icon, via: rule?.name);
    }
    if (dotnetApp != null && _isAspNet(dotnetApp)) {
      return info('ASP.NET Core', 'dotnet');
    }
    if (rule != null) return info(rule.name, rule.icon);
    return info(runtime.name, runtime.icon);
  }

  /// Binaries built from the project they run in. The executable name is
  /// arbitrary there, so the evidence is what sits next to it.
  TechInfo? _forCompiledBinary(
    String? exePath,
    String command,
    DetectedProject? project,
  ) {
    if (exePath == null) return null;

    // A .NET apphost is a native stub beside `<name>.runtimeconfig.json`.
    if (File('${p.windows.withoutExtension(exePath)}.runtimeconfig.json').existsSync()) {
      final framework = _firstUsed(_dotnet.backend, project);
      if (framework != null) {
        return TechInfo(name: framework.name, runtime: '.NET', icon: framework.icon);
      }
      return _isAspNet(exePath)
          ? const TechInfo(name: 'ASP.NET Core', runtime: '.NET', icon: 'dotnet')
          : const TechInfo(name: '.NET', icon: 'dotnet');
    }

    final directory = p.windows.dirname(exePath);
    if (File(p.windows.join(directory, 'flutter_windows.dll')).existsSync()) {
      return const TechInfo(name: 'Flutter', runtime: 'Dart', icon: 'flutter');
    }

    // `go run` builds into a temp folder named go-build<digits>.
    final isGoRun = exePath.toLowerCase().contains(r'\go-build');
    if (project == null) {
      return isGoRun ? const TechInfo(name: 'Go', icon: 'go') : null;
    }
    final builtHere = p.windows.isWithin(
      project.info.root.toLowerCase(),
      exePath.toLowerCase(),
    );
    final marker = project.info.marker.toLowerCase();

    if (marker == 'go.mod' && (builtHere || isGoRun)) {
      final module = _firstUsed(_goModules, project);
      return module == null
          ? const TechInfo(name: 'Go', icon: 'go')
          : TechInfo(name: module.name, runtime: 'Go', icon: module.icon ?? 'go');
    }
    if (!builtHere) return null;

    if (marker == 'cargo.toml') {
      final crate = _firstUsed(_rustCrates, project);
      return crate == null
          ? const TechInfo(name: 'Rust', icon: 'rust')
          : TechInfo(name: crate.name, runtime: 'Rust', icon: crate.icon ?? 'rust');
    }
    if (marker.endsWith('proj') || marker.endsWith('.sln') || marker.endsWith('.slnx')) {
      return const TechInfo(name: '.NET', icon: 'dotnet');
    }
    if (marker == 'pubspec.yaml') {
      return project.uses('flutter')
          ? const TechInfo(name: 'Flutter', runtime: 'Dart', icon: 'flutter')
          : const TechInfo(name: 'Dart', icon: 'dart');
    }
    if (marker == 'cmakelists.txt') {
      return const TechInfo(name: 'C/C++', icon: 'cplusplus');
    }
    return null;
  }

  static _Dep? _firstUsed(List<_Dep> candidates, DetectedProject? project) {
    if (project == null) return null;
    for (final dep in candidates) {
      if (project.uses(dep.package) || project.mentions(dep.package)) return dep;
    }
    return null;
  }

  /// True when the runtimeconfig beside [binary] pulls in the ASP.NET Core
  /// shared framework.
  static bool _isAspNet(String binary) {
    final config = File('${p.windows.withoutExtension(binary)}.runtimeconfig.json');
    try {
      return config.existsSync() &&
          config.readAsStringSync().contains('Microsoft.AspNetCore.App');
    } on FileSystemException {
      return false;
    }
  }

  static String? _dllOnCommandLine(String? commandLine, String? cwd) {
    if (commandLine == null) return null;
    for (final token in splitCommandLine(commandLine).skip(1)) {
      if (!token.toLowerCase().endsWith('.dll')) continue;
      if (p.windows.isAbsolute(token)) return token;
      return cwd == null ? null : p.windows.join(cwd, token);
    }
    return null;
  }

  static _Runtime? _runtimeFor(String exe) {
    final name = _pythonExe.hasMatch(exe) ? 'python' : exe;
    for (final runtime in _runtimes) {
      if (runtime.executables.contains(name)) return runtime;
    }
    return null;
  }

  static final _pythonExe = RegExp(r'^(python|pypy)[\d.]*w?$');

  /// `Node.EXE` becomes `node`.
  static String _stem(String processName) => _withoutExe(processName).toLowerCase();

  static String _withoutExe(String processName) =>
      processName.toLowerCase().endsWith('.exe')
      ? processName.substring(0, processName.length - 4)
      : processName;

  /// Lower-cases, uses forward slashes and drops quotes so one set of patterns
  /// matches however the path was written.
  static String _normalize(String? commandLine) => commandLine == null
      ? ''
      : commandLine.toLowerCase().replaceAll(r'\', '/').replaceAll('"', '');
}

enum _Role {
  /// The rule names the app itself.
  app,

  /// A dev server or bundler; the app framework is in the project's UI deps.
  bundler,

  /// A script runner or generic server; look in the project's server deps.
  server,
}

class _Rule {
  /// Matches tools by where an executable name can appear on a command line:
  /// as a package folder, as the script or binary being run, or as a bare
  /// argument. Deliberately not "anywhere", so a project folder that happens
  /// to be called `vite` or `firebase` does not trigger a match.
  _Rule.bin(
    String names,
    this.name,
    this.icon, {
    this.role = _Role.app,
    this.via,
  }) : pattern = RegExp(
         '(?:node_modules/|site-packages/)(?:$names)(?=\$|\\s|/)'
         '|(?:^|\\s|/\\.bin/|/scripts/|/bin/|npm:|-m\\s+)(?:$names)'
         '(?:@[\\w.-]+)?(?:\\.(?:js|mjs|cjs|ts|cmd|exe|ps1|py|bat))?(?=\$|\\s)',
       );

  /// Matches a regular expression anywhere on the command line.
  _Rule.raw(String source, this.name, this.icon, {this.role = _Role.app})
    : pattern = RegExp(source),
      via = null;

  final RegExp pattern;
  final String name;
  final String? icon;
  final _Role role;

  /// The tool to credit when [name] is the framework, e.g. `Angular CLI`.
  final String? via;
}

class _Dep {
  const _Dep(this.package, this.name, [this.icon]);
  final String package;
  final String name;
  final String? icon;
}

class _Runtime {
  _Runtime(
    this.name,
    this.icon,
    this.executables, {
    this.rules = const [],
    this.frontend = const [],
    this.backend = const [],
  });

  final String name;
  final String icon;
  final Set<String> executables;
  final List<_Rule> rules;

  /// Frameworks to look for in the manifest when a bundler is listening.
  final List<_Dep> frontend;

  /// Frameworks to look for when a plain script or generic server is.
  final List<_Dep> backend;

  _Rule? match(String command) {
    if (command.isEmpty) return null;
    for (final rule in rules) {
      if (rule.pattern.hasMatch(command)) return rule;
    }
    return null;
  }
}

// --- JavaScript -------------------------------------------------------------

const _jsMetaFrameworks = [
  _Dep('next', 'Next.js', 'nextdotjs'),
  _Dep('nuxt', 'Nuxt', 'nuxt'),
  _Dep('@remix-run/react', 'Remix', 'remix'),
  _Dep('@sveltejs/kit', 'SvelteKit', 'svelte'),
  _Dep('astro', 'Astro', 'astro'),
  _Dep('gatsby', 'Gatsby', 'gatsby'),
  _Dep('@builder.io/qwik', 'Qwik', 'qwik'),
  _Dep('@angular/core', 'Angular', 'angular'),
];

const _jsUiLibraries = [
  _Dep('vue', 'Vue', 'vuedotjs'),
  _Dep('svelte', 'Svelte', 'svelte'),
  _Dep('solid-js', 'Solid', 'solid'),
  _Dep('preact', 'Preact', 'preact'),
  _Dep('lit', 'Lit', 'lit'),
  _Dep('react', 'React', 'react'),
];

const _jsServerLibraries = [
  _Dep('@nestjs/core', 'NestJS', 'nestjs'),
  _Dep('express', 'Express', 'express'),
  _Dep('fastify', 'Fastify', 'fastify'),
  _Dep('koa', 'Koa', 'koa'),
  _Dep('hono', 'Hono', 'hono'),
  _Dep('@hapi/hapi', 'hapi'),
  _Dep('@adonisjs/core', 'AdonisJS', 'adonisjs'),
  _Dep('@strapi/strapi', 'Strapi', 'strapi'),
  _Dep('@apollo/server', 'Apollo Server', 'apollographql'),
  _Dep('@trpc/server', 'tRPC', 'trpc'),
  _Dep('socket.io', 'Socket.IO', 'socketdotio'),
];

final _jsRules = [
  _Rule.bin('next|next-server', 'Next.js', 'nextdotjs'),
  _Rule.bin('nuxt|nuxi|@nuxt/cli', 'Nuxt', 'nuxt'),
  _Rule.bin('@remix-run/dev|@remix-run/serve|remix|remix-serve', 'Remix', 'remix'),
  _Rule.bin(
    '@react-router/dev|@react-router/serve|react-router|react-router-serve',
    'React Router',
    'reactrouter',
  ),
  _Rule.bin('astro', 'Astro', 'astro'),
  _Rule.bin('@sveltejs/kit|svelte-kit', 'SvelteKit', 'svelte'),
  _Rule.bin('gatsby|gatsby-cli', 'Gatsby', 'gatsby'),
  _Rule.bin('@angular/cli|ng', 'Angular', 'angular', via: 'Angular CLI'),
  _Rule.bin('@vue/cli-service|vue-cli-service', 'Vue', 'vuedotjs', via: 'Vue CLI'),
  _Rule.bin('vitepress', 'VitePress', 'vitepress'),
  _Rule.bin('@docusaurus/core|docusaurus', 'Docusaurus', 'docusaurus'),
  _Rule.bin('storybook|@storybook/[\\w-]+', 'Storybook', 'storybook'),
  _Rule.bin('@11ty/eleventy|eleventy', 'Eleventy', 'eleventy'),
  _Rule.bin('react-scripts', 'React', 'react', via: 'Create React App'),
  _Rule.bin('expo|@expo/cli', 'Expo', 'expo'),
  _Rule.bin('react-native|metro', 'React Native', 'react', via: 'Metro'),
  _Rule.bin('@nestjs/cli|nest', 'NestJS', 'nestjs'),
  _Rule.bin('@strapi/strapi|strapi', 'Strapi', 'strapi'),
  _Rule.bin('vitest', 'Vitest', 'vitest'),
  _Rule.bin('jest', 'Jest', 'jest'),
  _Rule.bin('cypress', 'Cypress', 'cypress'),
  _Rule.bin('playwright|playwright-core|@playwright/[\\w-]+', 'Playwright', null),
  _Rule.bin(
    'wrangler|miniflare|workerd',
    'Cloudflare Workers',
    'cloudflareworkers',
    via: 'Wrangler',
  ),
  _Rule.bin('firebase|firebase-tools', 'Firebase Emulator', 'firebase'),
  _Rule.bin('supabase', 'Supabase', 'supabase'),
  _Rule.bin('prisma', 'Prisma Studio', 'prisma'),
  _Rule.bin('@anthropic-ai/claude-code|claude', 'Claude Code', 'claude'),
  _Rule.bin(
    'tsserver|typescript-language-server|typescript',
    'TypeScript language server',
    'typescript',
  ),
  _Rule.bin('eslint|eslint_d', 'ESLint', 'eslint'),
  _Rule.bin('http-server', 'http-server', null),
  _Rule.bin('live-server', 'live-server', null),
  _Rule.bin('json-server', 'JSON Server', null),
  _Rule.bin('browser-sync', 'Browsersync', null),
  _Rule.raw('node_modules/serve/', 'serve', null),
  // Dev servers and bundlers: which app they serve is in the manifest.
  _Rule.bin('vite', 'Vite', 'vite', role: _Role.bundler),
  _Rule.bin('vinxi', 'Vinxi', 'vite', role: _Role.bundler),
  _Rule.bin(
    'webpack|webpack-cli|webpack-dev-server',
    'webpack',
    'webpack',
    role: _Role.bundler,
  ),
  _Rule.bin('rspack|@rspack/cli|rsbuild|@rsbuild/core', 'Rspack', null, role: _Role.bundler),
  _Rule.bin('parcel', 'Parcel', null, role: _Role.bundler),
  _Rule.bin('rollup', 'Rollup', 'rollupdotjs', role: _Role.bundler),
  _Rule.bin('esbuild', 'esbuild', 'esbuild', role: _Role.bundler),
  // Script runners: what they run is in the manifest.
  _Rule.bin('nodemon', 'nodemon', 'nodemon', role: _Role.server),
  _Rule.bin('pm2', 'PM2', 'pm2', role: _Role.server),
  _Rule.bin('ts-node|ts-node-dev|ts-node-esm', 'ts-node', 'tsnode', role: _Role.server),
  _Rule.bin('tsx', 'tsx', 'typescript', role: _Role.server),
];

const _jsFrontend = [..._jsMetaFrameworks, ..._jsUiLibraries];
const _jsBackend = [..._jsServerLibraries, ..._jsMetaFrameworks];

// --- Python -----------------------------------------------------------------

const _pythonFrameworks = [
  _Dep('django', 'Django', 'django'),
  _Dep('fastapi', 'FastAPI', 'fastapi'),
  _Dep('flask', 'Flask', 'flask'),
  _Dep('streamlit', 'Streamlit', 'streamlit'),
  _Dep('gradio', 'Gradio', 'gradio'),
  _Dep('litestar', 'Litestar'),
  _Dep('starlette', 'Starlette'),
  _Dep('quart', 'Quart'),
  _Dep('aiohttp', 'aiohttp', 'aiohttp'),
  _Dep('sanic', 'Sanic', 'sanic'),
  _Dep('tornado', 'Tornado'),
  _Dep('falcon', 'Falcon'),
  _Dep('bottle', 'Bottle'),
];

final _pythonRules = [
  _Rule.raw(r'manage\.py\s+runserver', 'Django', 'django'),
  _Rule.bin('django|django-admin', 'Django', 'django'),
  _Rule.bin('flask', 'Flask', 'flask'),
  _Rule.bin('fastapi', 'FastAPI', 'fastapi'),
  _Rule.bin('streamlit', 'Streamlit', 'streamlit'),
  _Rule.bin('gradio', 'Gradio', 'gradio'),
  _Rule.bin(
    'jupyter|jupyter-lab|jupyter-notebook|jupyter-server|jupyterlab|notebook'
        '|ipykernel|ipykernel_launcher',
    'Jupyter',
    'jupyter',
  ),
  _Rule.bin('mkdocs', 'MkDocs', 'materialformkdocs'),
  _Rule.bin('tensorboard', 'TensorBoard', 'tensorflow'),
  _Rule.bin('mlflow', 'MLflow', 'mlflow'),
  _Rule.bin('airflow', 'Airflow', 'apacheairflow'),
  _Rule.bin('celery|flower', 'Celery', 'celery'),
  _Rule.bin('locust', 'Locust', 'locust'),
  _Rule.raw(r'-m\s+http\.server', 'http.server', null),
  _Rule.bin('debugpy', 'debugpy', null),
  _Rule.bin(
    'pylsp|pyright|pyright-langserver|basedpyright|jedi-language-server',
    'Python language server',
    null,
  ),
  // ASGI/WSGI servers: the app framework is in the project's requirements.
  _Rule.bin('uvicorn', 'Uvicorn', null, role: _Role.server),
  _Rule.bin('gunicorn', 'Gunicorn', 'gunicorn', role: _Role.server),
  _Rule.bin('hypercorn', 'Hypercorn', null, role: _Role.server),
  _Rule.bin('daphne', 'Daphne', null, role: _Role.server),
  _Rule.bin('waitress|waitress-serve', 'Waitress', null, role: _Role.server),
  _Rule.bin('granian', 'Granian', null, role: _Role.server),
];

// --- Everything else ----------------------------------------------------------

final _dotnet = _Runtime(
  '.NET',
  'dotnet',
  {'dotnet'},
  rules: [
    _Rule.raw(r'dotnet-watch|\swatch(\s|$)', 'dotnet watch', null),
    _Rule.raw(r'msbuild\.dll|/nodereuse', 'MSBuild', null),
    _Rule.raw(r'vbcscompiler', 'C# compiler server', null),
    _Rule.raw(
      r'languageserver|omnisharp|roslyn|rzls',
      'C# language server',
      null,
    ),
    _Rule.raw(r'testhost|vstest', '.NET test host', null),
  ],
  backend: const [
    _Dep('microsoft.net.sdk.blazorwebassembly', 'Blazor', 'blazor'),
    _Dep('microsoft.aspnetcore.components.webassembly', 'Blazor', 'blazor'),
    _Dep('microsoft.net.sdk.web', 'ASP.NET Core', 'dotnet'),
    _Dep('microsoft.net.sdk.worker', '.NET Worker', 'dotnet'),
    _Dep('aspire.hosting', '.NET Aspire', 'dotnet'),
  ],
);

final _runtimes = [
  _Runtime(
    'Node.js',
    'nodedotjs',
    {'node', 'nodejs'},
    rules: _jsRules,
    frontend: _jsFrontend,
    backend: _jsBackend,
  ),
  _Runtime(
    'Bun',
    'bun',
    {'bun'},
    rules: _jsRules,
    frontend: _jsFrontend,
    backend: _jsBackend,
  ),
  _Runtime(
    'Deno',
    'deno',
    {'deno'},
    rules: _jsRules,
    frontend: _jsFrontend,
    backend: _jsBackend,
  ),
  _Runtime(
    'Python',
    'python',
    {'python', 'py', 'pyw'},
    rules: _pythonRules,
    backend: _pythonFrameworks,
  ),
  _dotnet,
  _Runtime(
    'Java',
    'openjdk',
    {'java', 'javaw'},
    rules: [
      _Rule.raw(
        r'org\.springframework\.boot|spring-boot|-dspring\.',
        'Spring Boot',
        'springboot',
      ),
      _Rule.raw(r'org\.gradle\.launcher\.daemon|gradle-daemon', 'Gradle daemon', 'gradle'),
      _Rule.raw(r'org\.jetbrains\.kotlin\.daemon', 'Kotlin daemon', 'kotlin'),
      _Rule.raw(r'org\.apache\.catalina|tomcat', 'Tomcat', 'apachetomcat'),
      _Rule.raw(r'kafka\.kafka|org\.apache\.kafka|kafka-server', 'Kafka', 'apachekafka'),
      _Rule.raw(r'zookeeper', 'ZooKeeper', null),
      _Rule.raw(r'org\.elasticsearch|elasticsearch', 'Elasticsearch', 'elasticsearch'),
      _Rule.raw(r'io\.quarkus|quarkus', 'Quarkus', 'quarkus'),
      _Rule.raw(r'io\.ktor', 'Ktor', 'ktor'),
      _Rule.raw(r'jenkins', 'Jenkins', 'jenkins'),
      _Rule.raw(r'org\.eclipse\.jdt\.ls|jdtls', 'Java language server', null),
      _Rule.raw(r'plexus-classworlds|org\.apache\.maven', 'Maven', 'apachemaven'),
      _Rule.raw(r'org\.apache\.cassandra', 'Cassandra', 'apachecassandra'),
      _Rule.raw(r'neo4j', 'Neo4j', 'neo4j'),
      _Rule.raw(r'com\.android\.|android', 'Android tooling', 'android'),
    ],
    backend: const [
      _Dep('org.springframework.boot', 'Spring Boot', 'springboot'),
      _Dep('spring-boot-starter-parent', 'Spring Boot', 'springboot'),
      _Dep('io.quarkus', 'Quarkus', 'quarkus'),
      _Dep('io.ktor', 'Ktor', 'ktor'),
      _Dep('io.micronaut', 'Micronaut'),
    ],
  ),
  _Runtime(
    'Dart',
    'dart',
    {'dart', 'dartvm', 'dartaotruntime'},
    rules: [
      _Rule.raw(r'flutter_tools', 'Flutter tool', 'flutter'),
      _Rule.raw(r'frontend_server', 'Flutter compiler', 'flutter'),
      _Rule.raw(
        r'development-service|dds\.dart|dds_aot|dart development service',
        'Dart Development Service',
        null,
      ),
      _Rule.raw(r'devtools', 'Dart DevTools', null),
      _Rule.raw(r'tooling-daemon|dart_tooling_daemon', 'Dart tooling daemon', null),
      _Rule.raw(r'analysis_server|analysis-server|language-server', 'Dart analysis server', null),
    ],
    backend: const [
      _Dep('flutter', 'Flutter', 'flutter'),
      _Dep('serverpod', 'Serverpod'),
      _Dep('dart_frog', 'Dart Frog'),
      _Dep('shelf', 'shelf'),
    ],
  ),
  _Runtime(
    'Ruby',
    'ruby',
    {'ruby', 'rubyw'},
    rules: [
      _Rule.raw(r'bin/rails|rails\s+(s|server)(\s|$)', 'Rails', 'rubyonrails'),
      _Rule.raw(r'jekyll', 'Jekyll', 'jekyll'),
      _Rule.raw(r'puma', 'Puma', 'puma', role: _Role.server),
    ],
    backend: const [
      _Dep('rails', 'Rails', 'rubyonrails'),
      _Dep('sinatra', 'Sinatra'),
      _Dep('jekyll', 'Jekyll', 'jekyll'),
    ],
  ),
  _Runtime(
    'PHP',
    'php',
    {'php', 'php-cgi'},
    rules: [
      _Rule.raw(r'artisan\s+serve', 'Laravel', 'laravel'),
      _Rule.raw(r'symfony', 'Symfony', 'symfony'),
      _Rule.raw(r'\s-s\s', 'PHP built-in server', null, role: _Role.server),
    ],
    backend: const [
      _Dep('laravel/framework', 'Laravel', 'laravel'),
      _Dep('symfony/framework-bundle', 'Symfony', 'symfony'),
    ],
  ),
  _Runtime(
    'Erlang',
    'erlang',
    {'erl', 'werl', 'beam.smp'},
    rules: [_Rule.raw(r'rabbit', 'RabbitMQ', 'rabbitmq')],
    backend: const [_Dep('phoenix', 'Phoenix', 'phoenixframework')],
  ),
];

const _rustCrates = [
  _Dep('tauri', 'Tauri', 'tauri'),
  _Dep('actix-web', 'Actix Web', 'actix'),
  _Dep('rocket', 'Rocket', 'rocket'),
  _Dep('axum', 'Axum'),
  _Dep('warp', 'warp'),
];

const _goModules = [
  _Dep('github.com/gin-gonic/gin', 'Gin', 'gin'),
  _Dep('github.com/labstack/echo', 'Echo'),
  _Dep('github.com/gofiber/fiber', 'Fiber'),
  _Dep('github.com/go-chi/chi', 'chi'),
];

/// Programs recognisable from the executable name alone.
const _programs = <String, (String, String?)>{
  // Databases and infrastructure
  'postgres': ('PostgreSQL', 'postgresql'),
  'pg_ctl': ('PostgreSQL', 'postgresql'),
  'mysqld': ('MySQL', 'mysql'),
  'mariadbd': ('MariaDB', 'mariadb'),
  'mongod': ('MongoDB', 'mongodb'),
  'mongos': ('MongoDB', 'mongodb'),
  'redis-server': ('Redis', 'redis'),
  'memurai': ('Memurai (Redis)', 'redis'),
  // Container image names, which differ from the server binaries above.
  'redis': ('Redis', 'redis'),
  'mysql': ('MySQL', 'mysql'),
  'mariadb': ('MariaDB', 'mariadb'),
  'mongo': ('MongoDB', 'mongodb'),
  'clickhouse-server': ('ClickHouse', 'clickhouse'),
  'rabbitmq': ('RabbitMQ', 'rabbitmq'),
  'elasticsearch': ('Elasticsearch', 'elasticsearch'),
  'kafka': ('Kafka', 'apachekafka'),
  'sqlservr': ('SQL Server', 'database'),
  'sqlbrowser': ('SQL Server Browser', 'database'),
  'influxd': ('InfluxDB', 'influxdb'),
  'clickhouse': ('ClickHouse', 'clickhouse'),
  'meilisearch': ('Meilisearch', 'meilisearch'),
  'qdrant': ('Qdrant', 'qdrant'),
  'minio': ('MinIO', 'minio'),
  'etcd': ('etcd', 'etcd'),
  'consul': ('Consul', 'consul'),
  'vault': ('Vault', 'vault'),
  'grafana': ('Grafana', 'grafana'),
  'grafana-server': ('Grafana', 'grafana'),
  'prometheus': ('Prometheus', 'prometheus'),
  // Web servers and tunnels
  'nginx': ('nginx', 'nginx'),
  'httpd': ('Apache HTTP Server', 'apache'),
  'caddy': ('Caddy', 'caddy'),
  'traefik': ('Traefik', 'traefikproxy'),
  'iisexpress': ('IIS Express', 'dotnet'),
  'w3wp': ('IIS', 'windows'),
  'ngrok': ('ngrok', 'ngrok'),
  'cloudflared': ('Cloudflare Tunnel', 'cloudflare'),
  'tailscaled': ('Tailscale', 'tailscale'),
  'hugo': ('Hugo', 'hugo'),
  'esbuild': ('esbuild', 'esbuild'),
  // Containers and virtualisation
  'com.docker.backend': ('Docker Desktop', 'docker'),
  'com.docker.service': ('Docker Desktop', 'docker'),
  'com.docker.build': ('Docker Desktop', 'docker'),
  'docker desktop': ('Docker Desktop', 'docker'),
  'dockerd': ('Docker Engine', 'docker'),
  'docker-proxy': ('Docker', 'docker'),
  'vpnkit': ('Docker Desktop', 'docker'),
  'podman': ('Podman', 'podman'),
  'kubectl': ('kubectl', 'kubernetes'),
  'wslrelay': ('WSL', 'linux'),
  'wslhost': ('WSL', 'linux'),
  'wslservice': ('WSL', 'linux'),
  'wsl': ('WSL', 'linux'),
  // Developer tools
  'code': ('Visual Studio Code', 'vscode'),
  'code - insiders': ('Visual Studio Code Insiders', 'vscode'),
  'devenv': ('Visual Studio', 'vscode'),
  'cursor': ('Cursor', 'cursor'),
  'zed': ('Zed', 'zedindustries'),
  'idea64': ('IntelliJ IDEA', 'intellijidea'),
  'webstorm64': ('WebStorm', 'webstorm'),
  'pycharm64': ('PyCharm', 'pycharm'),
  'rider64': ('Rider', 'rider'),
  'goland64': ('GoLand', 'jetbrains'),
  'clion64': ('CLion', 'jetbrains'),
  'phpstorm64': ('PhpStorm', 'jetbrains'),
  'datagrip64': ('DataGrip', 'jetbrains'),
  'rustrover64': ('RustRover', 'jetbrains'),
  'studio64': ('Android Studio', 'androidstudio'),
  'adb': ('Android Debug Bridge', 'android'),
  'emulator': ('Android Emulator', 'android'),
  'claude': ('Claude', 'claude'),
  'ollama': ('Ollama', 'ollama'),
  'ollama app': ('Ollama', 'ollama'),
  'postman': ('Postman', 'postman'),
  'insomnia': ('Insomnia', 'insomnia'),
  'git': ('Git', 'git'),
  'git-daemon': ('Git daemon', 'git'),
  'ssh': ('OpenSSH', 'terminal'),
  'sshd': ('OpenSSH server', 'terminal'),
  'powershell': ('PowerShell', 'terminal'),
  'pwsh': ('PowerShell', 'terminal'),
  'cmd': ('Command Prompt', 'terminal'),
  'go': ('Go toolchain', 'go'),
  'cargo': ('Cargo', 'rust'),
  // Everyday apps that keep local ports open
  'chrome': ('Google Chrome', 'googlechrome'),
  'msedge': ('Microsoft Edge', 'edge'),
  'msedgewebview2': ('Edge WebView2', 'edge'),
  'firefox': ('Firefox', 'firefoxbrowser'),
  'brave': ('Brave', 'brave'),
  'opera': ('Opera', 'opera'),
  'figma_agent': ('Figma', 'figma'),
  'dropbox': ('Dropbox', 'dropbox'),
  'zoom': ('Zoom', 'zoom'),
  // Windows itself, for when we are not allowed to read the description
  'system': ('Windows kernel', 'windows'),
  'lsass': ('Local Security Authority', 'windows'),
  'wininit': ('Windows start-up', 'windows'),
  'services': ('Service Control Manager', 'windows'),
  'spoolsv': ('Print Spooler', 'windows'),
};

/// Executable-name prefixes shared by a product's helper processes.
final _programFamilies = <(RegExp, String, String)>[
  (RegExp(r'^qemu-system-'), 'QEMU', 'qemu'),
  (RegExp(r'^(vmware|vmnat|vmnetdhcp)'), 'VMware', 'vmware'),
  (RegExp(r'^(vbox|virtualbox)'), 'VirtualBox', 'virtualbox'),
  (RegExp(r'^(nvcontainer|nvidia|nvdisplay)'), 'NVIDIA', 'nvidia'),
  (RegExp(r'^godot'), 'Godot', 'godotengine'),
  (RegExp(r'^steam'), 'Steam', 'steam'),
  (RegExp(r'^spotify'), 'Spotify', 'spotify'),
  (RegExp(r'^discord'), 'Discord', 'discord'),
  (RegExp(r'^jetbrains'), 'JetBrains', 'jetbrains'),
  (RegExp(r'^teamviewer'), 'TeamViewer', 'teamviewer'),
  (RegExp(r'^tailscale'), 'Tailscale', 'tailscale'),
  (RegExp(r'^docker'), 'Docker', 'docker'),
  (RegExp(r'^caddy'), 'Caddy', 'caddy'),
];
