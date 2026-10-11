import 'package:flutter_test/flutter_test.dart';
import 'package:port_why/src/detect/project_detector.dart';
import 'package:port_why/src/detect/tech_detector.dart';
import 'package:port_why/src/models.dart';
import 'package:port_why/src/ui/tech_icon.dart';

import 'support.dart';

DetectedProject project({
  Set<String> dependencies = const {},
  String text = '',
  String marker = 'package.json',
  String root = r'C:\work\app',
}) => DetectedProject(
  info: ProjectInfo(name: 'app', root: root, marker: marker),
  dependencies: dependencies,
  manifestText: text.toLowerCase(),
);

void main() {
  const detector = TechDetector();

  TechInfo node(String commandLine, {DetectedProject? project, String? parent}) =>
      detector.detect(
        pid: 1,
        processName: 'node.exe',
        commandLine: commandLine,
        parentCommandLine: parent,
        project: project,
      );

  TechInfo python(String commandLine, {DetectedProject? project, String? parent}) =>
      detector.detect(
        pid: 1,
        processName: 'python.exe',
        commandLine: commandLine,
        parentCommandLine: parent,
        project: project,
      );

  const viteCommand = r'node "C:\work\app\node_modules\vite\bin\vite.js"';

  group('JavaScript', () {
    test('a Vue app served by Vite is Vue, with Vite credited', () {
      final tech = node(viteCommand, project: project(dependencies: {'vue', 'vite'}));
      expect(tech.name, 'Vue');
      expect(tech.via, 'Vite');
      expect(tech.runtime, 'Node.js');
      expect(tech.icon, 'vuedotjs');
      expect(tech.stack, 'Vite · Node.js');
    });

    test('a React app served by Vite is React', () {
      final tech = node(viteCommand, project: project(dependencies: {'react', 'react-dom'}));
      expect((tech.name, tech.icon), ('React', 'react'));
    });

    test('a meta-framework outranks the UI library it is built on', () {
      final tech = node(
        viteCommand,
        project: project(dependencies: {'svelte', '@sveltejs/kit'}),
      );
      expect(tech.name, 'SvelteKit');
    });

    test('Vite with no recognisable app is just Vite', () {
      final tech = node(viteCommand, project: project());
      expect((tech.name, tech.via, tech.icon), ('Vite', null, 'vite'));
    });

    test('the real pnpm shim path on Windows still reads as Vite', () {
      final tech = node(
        r'node   "C:\work\app\node_modules\.bin\\..\vite\bin\vite.js"',
        project: project(dependencies: {'react'}),
      );
      expect((tech.name, tech.via), ('React', 'Vite'));
    });

    test('Next.js from its package path', () {
      final tech = node(
        r'"C:\Program Files\nodejs\node.exe" C:\work\app\node_modules\next\dist\server\lib\start-server.js',
      );
      expect((tech.name, tech.icon, tech.runtime), ('Next.js', 'nextdotjs', 'Node.js'));
    });

    test('Angular CLI', () {
      final tech = node(r'node C:\work\app\node_modules\@angular\cli\bin\ng.js serve');
      expect((tech.name, tech.via, tech.icon), ('Angular', 'Angular CLI', 'angular'));
    });

    test('a plain script is named after the server library it depends on', () {
      final tech = node('node server.js', project: project(dependencies: {'express'}));
      expect((tech.name, tech.via, tech.runtime), ('Express', null, 'Node.js'));
      expect(tech.icon, 'express');
    });

    test('a UI library does not label a plain script', () {
      // `node server.js` in a Vue project is some script, not the Vue app.
      final tech = node('node server.js', project: project(dependencies: {'vue'}));
      expect((tech.name, tech.icon), ('Node.js', 'nodedotjs'));
    });

    test('a script runner credits itself and finds the framework', () {
      final tech = node(
        r'node C:\work\app\node_modules\tsx\dist\cli.mjs watch src/index.ts',
        project: project(dependencies: {'hono'}),
      );
      expect((tech.name, tech.via), ('Hono', 'tsx'));
    });

    test('a folder that shares a tool name does not trigger it', () {
      for (final folder in ['vite', 'next', 'firebase', 'claude', 'astro']) {
        final tech = node('node C:\\work\\$folder\\server.js');
        expect(tech.name, 'Node.js', reason: 'folder named $folder');
      }
    });

    test('vitest is not mistaken for vite', () {
      expect(node(r'node C:\w\node_modules\vitest\vitest.mjs --ui').name, 'Vitest');
    });

    test('with nothing to go on, it is Node.js', () {
      final tech = node('node');
      expect((tech.name, tech.runtime, tech.icon), ('Node.js', null, 'nodedotjs'));
    });

    test('Bun and Deno use the same rules', () {
      final bun = detector.detect(
        pid: 1,
        processName: 'bun.exe',
        commandLine: 'bun --bun vite',
        project: project(dependencies: {'vue'}),
      );
      expect((bun.name, bun.via, bun.runtime), ('Vue', 'Vite', 'Bun'));
      final deno = detector.detect(
        pid: 1,
        processName: 'deno.exe',
        commandLine: 'deno run -A npm:vite@5.4.0',
      );
      expect((deno.name, deno.runtime), ('Vite', 'Deno'));
    });
  });

  group('Python', () {
    test('Uvicorn serving FastAPI is FastAPI', () {
      final tech = python(
        r'C:\work\app\.venv\Scripts\python.exe -m uvicorn main:app --reload',
        project: project(marker: 'requirements.txt', text: 'fastapi==0.110\nuvicorn\n'),
      );
      expect((tech.name, tech.via, tech.runtime), ('FastAPI', 'Uvicorn', 'Python'));
      expect(tech.icon, 'fastapi');
    });

    test('the console-script launcher path counts too', () {
      final tech = python(
        r'"C:\work\app\.venv\Scripts\python.exe" "C:\work\app\.venv\Scripts\uvicorn.exe" main:app',
      );
      expect((tech.name, tech.icon), ('Uvicorn', 'python'));
    });

    test('manage.py runserver is Django', () {
      final tech = python('python manage.py runserver 0.0.0.0:8000');
      expect((tech.name, tech.icon), ('Django', 'django'));
    });

    test('a reloader worker inherits its meaning from the parent', () {
      final tech = python(
        'python -c "from multiprocessing.spawn import spawn_main; spawn_main(parent_pid=4)" --multiprocessing-fork',
        parent: 'python -m uvicorn main:app --reload',
        project: project(marker: 'pyproject.toml', text: 'dependencies = ["fastapi>=0.100"]'),
      );
      expect((tech.name, tech.via), ('FastAPI', 'Uvicorn'));
    });

    test('a plain script is named after the framework it requires', () {
      final tech = python(
        'python app.py',
        project: project(marker: 'requirements.txt', text: 'Flask>=3\n'),
      );
      expect((tech.name, tech.icon), ('Flask', 'flask'));
    });

    test('http.server', () {
      expect(python('python -m http.server 8000').name, 'http.server');
    });

    test('versioned interpreter names are Python', () {
      final tech = detector.detect(pid: 1, processName: 'python3.12.exe');
      expect((tech.name, tech.icon), ('Python', 'python'));
    });
  });

  group('.NET', () {
    late Sandbox box;
    setUp(() => box = Sandbox());
    tearDown(() => box.dispose());

    test('an apphost beside an ASP.NET runtimeconfig is ASP.NET Core', () {
      final exe = box.file('app/bin/Debug/net9.0/Shop.exe');
      box.file(
        'app/bin/Debug/net9.0/Shop.runtimeconfig.json',
        '{"runtimeOptions":{"frameworks":[{"name":"Microsoft.AspNetCore.App"}]}}',
      );
      final tech = detector.detect(pid: 1, processName: 'Shop.exe', exePath: exe);
      expect((tech.name, tech.runtime, tech.icon), ('ASP.NET Core', '.NET', 'dotnet'));
    });

    test('an apphost with a console runtimeconfig is plain .NET', () {
      final exe = box.file('tool/Tool.exe');
      box.file(
        'tool/Tool.runtimeconfig.json',
        '{"runtimeOptions":{"framework":{"name":"Microsoft.NETCore.App"}}}',
      );
      final tech = detector.detect(pid: 1, processName: 'Tool.exe', exePath: exe);
      expect((tech.name, tech.icon), ('.NET', 'dotnet'));
    });

    test('`dotnet app.dll` reads the dll\'s runtimeconfig', () {
      final cwd = box.dir('publish');
      box.file(
        'publish/Shop.runtimeconfig.json',
        '{"runtimeOptions":{"frameworks":[{"name":"Microsoft.AspNetCore.App"}]}}',
      );
      final tech = detector.detect(
        pid: 1,
        processName: 'dotnet.exe',
        commandLine: 'dotnet Shop.dll --urls http://localhost:5000',
        cwd: cwd,
      );
      expect(tech.name, 'ASP.NET Core');
    });

    test('the project file marks a Blazor app', () {
      final tech = detector.detect(
        pid: 1,
        processName: 'dotnet.exe',
        commandLine: 'dotnet Shop.dll',
        project: project(
          marker: 'Shop.csproj',
          text: '<Project Sdk="Microsoft.NET.Sdk.BlazorWebAssembly">',
        ),
      );
      expect((tech.name, tech.icon), ('Blazor', 'blazor'));
    });
  });

  group('Dart and Flutter', () {
    test('the flutter tool', () {
      final tech = detector.detect(
        pid: 1,
        processName: 'dart.exe',
        commandLine:
            r'C:\flutter\bin\cache\dart-sdk\bin\dart.exe C:\flutter\bin\cache\flutter_tools.snapshot run',
      );
      expect((tech.name, tech.icon, tech.runtime), ('Flutter tool', 'flutter', 'Dart'));
    });

    test('a Flutter desktop app, by the engine DLL beside it', () {
      final box = Sandbox();
      addTearDown(box.dispose);
      final exe = box.file('build/windows/x64/runner/Debug/shop.exe');
      box.file('build/windows/x64/runner/Debug/flutter_windows.dll');
      final tech = detector.detect(pid: 1, processName: 'shop.exe', exePath: exe);
      expect((tech.name, tech.icon), ('Flutter', 'flutter'));
    });
  });

  group('compiled binaries', () {
    test('a Rust binary built inside its Cargo project', () {
      final tech = detector.detect(
        pid: 1,
        processName: 'ledger.exe',
        exePath: r'C:\work\app\target\debug\ledger.exe',
        project: project(marker: 'Cargo.toml', text: '[dependencies]\nactix-web = "4"'),
      );
      expect((tech.name, tech.runtime, tech.icon), ('Actix Web', 'Rust', 'actix'));
    });

    test('an unrelated tool run from a Cargo project is not Rust', () {
      final tech = detector.detect(
        pid: 1,
        processName: 'ncat.exe',
        exePath: r'C:\tools\ncat.exe',
        project: project(marker: 'Cargo.toml'),
        description: 'Ncat',
      );
      expect((tech.name, tech.icon), ('Ncat', null));
    });

    test('`go run` output is Go', () {
      final tech = detector.detect(
        pid: 1,
        processName: 'main.exe',
        exePath: r'C:\Users\me\AppData\Local\Temp\go-build123\b001\exe\main.exe',
      );
      expect((tech.name, tech.icon), ('Go', 'go'));
    });
  });

  group('programs and services', () {
    test('known servers by executable name', () {
      final tech = detector.detect(pid: 1, processName: 'postgres.exe');
      expect((tech.name, tech.icon), ('PostgreSQL', 'postgresql'));
    });

    test('a service host is named after its service', () {
      final tech = detector.detect(
        pid: 1,
        processName: 'svchost.exe',
        services: ['Delivery Optimization'],
        description: 'Host Process for Windows Services',
      );
      expect((tech.name, tech.via, tech.icon), (
        'Delivery Optimization',
        'Windows service',
        'windows',
      ));
    });

    test('helper executables share the family icon but keep their name', () {
      final tech = detector.detect(
        pid: 1,
        processName: 'SpotifyLauncher.exe',
        description: 'Spotify Launcher',
      );
      expect((tech.name, tech.icon), ('Spotify Launcher', 'spotify'));
    });

    test('a single-file Bun build is named after itself, not "Bun"', () {
      final tech = detector.detect(
        pid: 1,
        processName: 'opencode.exe',
        description: 'Bun',
      );
      expect((tech.name, tech.runtime, tech.icon), ('opencode', 'Bun', 'bun'));
    });

    test('an unknown program falls back to its description, then its name', () {
      expect(
        detector.detect(pid: 1, processName: 'x.exe', description: 'Acme Sync').name,
        'Acme Sync',
      );
      expect(detector.detect(pid: 1, processName: 'Mystery.exe').name, 'Mystery');
    });
  });

  test('every icon the detector can emit has a glyph', () {
    final missing = TechDetector.iconKeys.difference(techGlyphs.keys.toSet());
    expect(missing, isEmpty);
  });

  test('runtimes are recognised by executable name', () {
    expect(TechDetector.isRuntime('Node.EXE'), isTrue);
    expect(TechDetector.isRuntime('python3.11.exe'), isTrue);
    expect(TechDetector.isRuntime('chrome.exe'), isFalse);
  });
}
