import 'package:flutter_test/flutter_test.dart';
import 'package:port_why/src/detect/project_detector.dart';
import 'package:port_why/src/models.dart';

import 'support.dart';

void main() {
  late Sandbox box;
  late ProjectDetector detector;

  setUp(() {
    box = Sandbox();
    detector = ProjectDetector(environment: box.environment);
  });
  tearDown(() => box.dispose());

  group('names a project from its manifest', () {
    test('package.json', () {
      box.file('home/code/shop/package.json', '{"name": "@acme/shop"}');
      final project = detector.detect(cwd: box.dir('home/code/shop'));
      expect(project?.info.name, '@acme/shop');
      expect(project?.info.marker, 'package.json');
      expect(project?.info.root, box.dir('home/code/shop'));
    });

    test('pubspec.yaml', () {
      box.file('home/code/app/pubspec.yaml', 'name: port_why\ndescription: x\n');
      expect(detector.detect(cwd: box.dir('home/code/app'))?.info.name, 'port_why');
    });

    test('Cargo.toml takes the [package] name, not a dependency name', () {
      box.file(
        'home/code/svc/Cargo.toml',
        '[dependencies]\nname = "decoy"\n\n[package]\nname = "ledger"\nversion = "0.1.0"\n',
      );
      expect(detector.detect(cwd: box.dir('home/code/svc'))?.info.name, 'ledger');
    });

    test('pyproject.toml, PEP 621 and Poetry', () {
      box.file('home/code/a/pyproject.toml', '[project]\nname = "api"\n');
      box.file('home/code/b/pyproject.toml', '[tool.poetry]\nname = "worker"\n');
      expect(detector.detect(cwd: box.dir('home/code/a'))?.info.name, 'api');
      expect(detector.detect(cwd: box.dir('home/code/b'))?.info.name, 'worker');
    });

    test('go.mod uses the last path segment of the module', () {
      box.file('home/code/g/go.mod', 'module github.com/acme/gateway\n\ngo 1.22\n');
      expect(detector.detect(cwd: box.dir('home/code/g'))?.info.name, 'gateway');
    });

    test('.csproj uses the file name', () {
      box.file('home/code/Web/Acme.Web.csproj', '<Project Sdk="Microsoft.NET.Sdk.Web" />');
      final project = detector.detect(cwd: box.dir('home/code/Web'));
      expect(project?.info.name, 'Acme.Web');
      expect(project?.mentions('microsoft.net.sdk.web'), isTrue);
    });

    test('pom.xml ignores the parent artifactId', () {
      box.file(
        'home/code/j/pom.xml',
        '<project><parent><artifactId>spring-boot-starter-parent</artifactId></parent>'
            '<artifactId>billing</artifactId></project>',
      );
      expect(detector.detect(cwd: box.dir('home/code/j'))?.info.name, 'billing');
    });

    test('falls back to the folder name when the manifest has no name', () {
      box.file('home/code/unnamed/package.json', '{"private": true}');
      expect(detector.detect(cwd: box.dir('home/code/unnamed'))?.info.name, 'unnamed');
    });

    test('survives a malformed manifest', () {
      box.file('home/code/broken/package.json', '{ not json');
      expect(detector.detect(cwd: box.dir('home/code/broken'))?.info.name, 'broken');
    });
  });

  group('finds the right folder', () {
    test('walks up from a subdirectory', () {
      box.file('home/code/shop/package.json', '{"name": "shop"}');
      final project = detector.detect(cwd: box.dir('home/code/shop/src/server'));
      expect(project?.info.name, 'shop');
      expect(project?.info.root, box.dir('home/code/shop'));
    });

    test('the nearest manifest wins in a monorepo', () {
      box.file('home/code/mono/package.json', '{"name": "mono"}');
      box.file('home/code/mono/apps/web/package.json', '{"name": "web"}');
      expect(detector.detect(cwd: box.dir('home/code/mono/apps/web'))?.info.name, 'web');
    });

    test('a script inside node_modules belongs to the project above it', () {
      box.file('home/code/shop/package.json', '{"name": "shop"}');
      final script = box.file(
        'home/code/shop/node_modules/vite/bin/vite.js',
      );
      box.file('home/code/shop/node_modules/vite/package.json', '{"name": "vite"}');
      // No working directory: only the script path on the command line.
      final project = detector.detect(commandLine: 'node "$script" --port 5173');
      expect(project?.info.name, 'shop');
    });

    test('uses the executable location when nothing else is known', () {
      box.file('home/code/svc/Cargo.toml', '[package]\nname = "ledger"\n');
      final exe = box.file('home/code/svc/target/debug/ledger.exe');
      expect(detector.detect(exePath: exe)?.info.name, 'ledger');
    });

    test('does not climb out of a git repository', () {
      box.file('home/code/package.json', '{"name": "outer"}');
      box.dir('home/code/repo/.git');
      final project = detector.detect(cwd: box.dir('home/code/repo/src'));
      expect(project?.info.name, 'repo');
      expect(project?.info.marker, '.git');
    });

    test('a manifest below the git root beats the git root', () {
      box.dir('home/code/repo/.git');
      box.file('home/code/repo/api/pyproject.toml', '[project]\nname = "api"\n');
      expect(detector.detect(cwd: box.dir('home/code/repo/api'))?.info.name, 'api');
    });
  });

  group('refuses to invent projects', () {
    test('not in the home folder itself', () {
      box.file('home/package.json', '{"name": "oops"}');
      expect(detector.detect(cwd: box.dir('home')), isNull);
    });

    // AppData is a Windows folder; macOS and Linux keep the same things in
    // ~/Library and dot-folders, which are off limits there.
    test('not under AppData, where Electron apps keep a package.json', () {
      box.file('home/AppData/Local/Programs/Editor/package.json', '{"name": "editor"}');
      expect(
        detector.detect(cwd: box.dir('home/AppData/Local/Programs/Editor')),
        isNull,
      );
    }, testOn: 'windows');

    test('not in a tool cache such as a global install under ~/.bun', () {
      box.file('home/.bun/install/global/package.json', '{"name": "global"}');
      final exe = box.file(
        'home/.bun/install/global/node_modules/@tool/cli/bin/tool.exe',
      );
      expect(detector.detect(cwd: box.dir('home'), exePath: exe), isNull);
    });

    test('not under Program Files or Windows', () {
      box.file('Program Files/Thing/package.json', '{"name": "thing"}');
      expect(detector.detect(cwd: box.dir('Program Files/Thing')), isNull);
      expect(detector.detect(cwd: box.dir('Windows/System32')), isNull);
    });
  });

  group('folder-name fallback', () {
    test('names a manifest-less folder after itself', () {
      final project = detector.detect(cwd: box.dir('home/code/static-site'));
      expect(project?.info.name, 'static-site');
      expect(project?.info.marker, ProjectInfo.folderMarker);
      expect(project?.info.isDeclared, isFalse);
    });

    test('can be switched off', () {
      expect(
        detector.detect(cwd: box.dir('home/code/static-site'), allowFolderName: false),
        isNull,
      );
    });

    test('never uses a folder directly under home, such as Documents', () {
      expect(detector.detect(cwd: box.dir('home/Documents')), isNull);
    });
  });

  test('collects dependencies for the tech detector', () {
    box.file(
      'home/code/shop/package.json',
      '{"name": "shop", "dependencies": {"vue": "^3"}, "devDependencies": {"vite": "^5"}}',
    );
    box.file('home/code/shop/requirements.txt', 'fastapi==0.110\nuvicorn[standard]\n');
    final project = detector.detect(cwd: box.dir('home/code/shop'))!;
    expect(project.uses('vue'), isTrue);
    expect(project.uses('vite'), isTrue);
    expect(project.uses('react'), isFalse);
    // A Python backend sharing the folder is still visible.
    expect(project.mentions('fastapi'), isTrue);
    expect(project.mentions('fast'), isFalse);
  });

  test('splitCommandLine honours quotes', () {
    expect(
      splitCommandLine(r'"C:\Program Files\nodejs\node.exe"  "C:\my app\server.js" --port 3000'),
      [r'C:\Program Files\nodejs\node.exe', r'C:\my app\server.js', '--port', '3000'],
    );
  });
}
