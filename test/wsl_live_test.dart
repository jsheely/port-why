@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:port_why/src/data/windows/windows_scan.dart';
import 'package:port_why/src/data/windows/wsl.dart' as wsl;
import 'package:port_why/src/models.dart';

/// Drives a real WSL distribution: starts a throwaway server inside it, checks
/// the scan traces the relayed port back to it, then kills it through the same
/// path the app uses. Skipped when no suitable distribution is running.
void main() {
  const port = 47611;
  final folder = 'port_why_wsl_fixture_$pid';

  /// Runs [script] in [distro] as its default user, the way a developer would.
  Future<ProcessResult> sh(String distro, String script) async {
    final process = await Process.start('wsl.exe', ['-d', distro, '-e', 'sh', '-s']);
    process.stdin.add(utf8.encode(script));
    await process.stdin.close();
    final out = process.stdout.transform(utf8.decoder).join();
    final err = process.stderr.transform(utf8.decoder).join();
    return ProcessResult(process.pid, await process.exitCode, await out, await err);
  }

  /// A running distribution that has what the fixture needs, if any.
  Future<String?> usableDistro() async {
    for (final distro in await wsl.runningDistros() ?? const <String>[]) {
      final probe = await sh(distro, 'command -v python3 >/dev/null && command -v ss >/dev/null && echo ok');
      if ('${probe.stdout}'.contains('ok')) return distro;
    }
    return null;
  }

  Future<ScannedPort?> find(Set<String> known) async {
    for (final scanned in await scanMachine(ScanRequest(knownProcesses: known))) {
      if (scanned.port == port && scanned.protocol == Protocol.tcp) return scanned;
    }
    return null;
  }

  /// Polls until the relayed port is (or is no longer) visible on Windows.
  Future<ScannedPort?> waitFor({required bool present}) async {
    ScannedPort? scanned;
    for (var attempt = 0; attempt < 40; attempt++) {
      scanned = await find(const {});
      if ((scanned != null) == present) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return scanned;
  }

  test('traces a relayed port to the WSL process behind it, then kills it', () async {
    final distro = await usableDistro();
    if (distro == null) {
      markTestSkipped('no running WSL distribution with python3 and ss');
      return;
    }

    // A stand-in dev server in its own project folder under the user's home.
    final server = await Process.start('wsl.exe', ['-d', distro, '-e', 'sh', '-s']);
    addTearDown(() async {
      await sh(distro, 'pkill -f "http.server $port"; rm -rf "\$HOME/$folder"');
      server.kill();
    });
    server.stdin.add(
      utf8.encode(
        'mkdir -p "\$HOME/$folder" && cd "\$HOME/$folder" && '
        'printf \'{"name": "wsl-fixture"}\' > package.json && '
        'exec python3 -m http.server $port --bind 127.0.0.1\n',
      ),
    );
    await server.stdin.close();

    final scanned = await waitFor(present: true);
    expect(scanned, isNotNull, reason: 'port $port never appeared on Windows');
    final process = scanned!.process;
    final details = process.details;

    // Windows says wslrelay.exe; the scan must say what is really there.
    expect(process.isBehindRelay, isTrue);
    expect(details.distro, distro);
    expect(details.name, startsWith('python'));
    expect(details.pid, greaterThan(0));
    expect(details.commandLine, contains('http.server $port'));
    expect(details.cwd, endsWith('/$folder'));
    expect(details.container, isNull);
    // The folder is reachable from Windows and really is that folder.
    expect(details.hostCwd, startsWith(r'\\'));
    expect(File('${details.hostCwd}\\package.json').existsSync(), isTrue);

    final insight = process.insight!;
    expect(insight.project?.name, 'wsl-fixture');
    expect(insight.project?.marker, 'package.json');
    expect(insight.tech.name, 'http.server');
    expect(insight.tech.runtime, 'Python');
    expect(insight.category, PortCategory.project);

    // Once known, a scan must not go back into WSL: it hands back the relay
    // and leaves the caller to use what it remembered.
    final again = (await find({process.key}))!;
    expect(again.process.key, process.key);
    expect(again.process.insight, isNull);
    expect(again.process.isBehindRelay, isFalse);

    // Killing checks it is still the same process...
    expect(
      await wsl.killWslProcess(distro, details.pid, details.startStamp! + 1),
      KillResult.notFound,
    );
    expect(await find(const {}), isNotNull, reason: 'the wrong process was killed');

    // ...and then ends it, after which Windows lets go of the port.
    expect(
      await wsl.killWslProcess(distro, details.pid, details.startStamp),
      KillResult.killed,
    );
    expect(await waitFor(present: false), isNull, reason: 'port $port still open');
    expect(
      await wsl.killWslProcess(distro, details.pid, details.startStamp),
      KillResult.notFound,
    );
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('stopping a container that does not exist reports it as gone', () async {
    final distro = await usableDistro();
    if (distro == null) {
      markTestSkipped('no running WSL distribution');
      return;
    }
    final probe = await sh(distro, 'command -v docker >/dev/null && docker ps >/dev/null 2>&1 && echo ok');
    if (!'${probe.stdout}'.contains('ok')) {
      markTestSkipped('no Docker engine reachable from $distro');
      return;
    }
    expect(await wsl.stopContainer(distro, 'f' * 64), KillResult.notFound);
    // Anything that is not a container id never reaches a shell.
    expect(await wsl.stopContainer(distro, 'x; rm -rf /'), KillResult.failed);
  });
}
