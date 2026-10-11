@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:port_why/src/data/windows/win32.dart' as win32;
import 'package:port_why/src/data/windows/windows_scan.dart';
import 'package:port_why/src/models.dart';

/// True when running with a high or system integrity token.
bool _isElevated() => Process.runSync('whoami', [
  '/groups',
]).stdout.toString().contains(RegExp(r'S-1-16-(12288|16384)'));

/// These run the real Win32 calls against real sockets and processes.
void main() {
  ScannedPort? find(int port, {Protocol protocol = Protocol.tcp, bool udp = false}) {
    for (final scanned in scanWindows(ScanRequest(includeUdp: udp))) {
      if (scanned.port == port && scanned.protocol == protocol) return scanned;
    }
    return null;
  }

  test('finds a port this process opens, with our pid, path and folder', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final before = DateTime.now().subtract(const Duration(seconds: 5));

    final scanned = find(server.port);
    expect(scanned, isNotNull, reason: 'port ${server.port} not reported');
    expect(scanned!.addresses, ['127.0.0.1']);

    final process = scanned.process.details;
    expect(process.pid, pid);
    expect(p.equals(process.exePath!, Platform.resolvedExecutable), isTrue);
    expect(p.equals(process.cwd!, Directory.current.path), isTrue);
    expect(process.commandLine, isNotEmpty);
    expect(process.restricted, isFalse);
    expect(process.startStamp, isNotNull);
    expect(process.parentName, isNotNull);
    // The bind time comes from the kernel and should be "just now".
    expect(scanned.openedAt!.isAfter(before), isTrue);
    expect(scanned.openedAt!.isBefore(DateTime.now().add(const Duration(seconds: 5))), isTrue);

    await server.close();
    expect(find(server.port), isNull, reason: 'closed port still reported');
  });

  test('merges the IPv4 and IPv6 halves of one listener into one row', () async {
    final v6 = await ServerSocket.bind(InternetAddress.anyIPv6, 0, v6Only: false);
    addTearDown(v6.close);
    final scanned = scanWindows(const ScanRequest())
        .where((s) => s.port == v6.port && s.process.details.pid == pid)
        .toList();
    expect(scanned, hasLength(1));
    expect(scanned.single.addresses, ['0.0.0.0', '::']);
  });

  test('reports UDP only when asked', () async {
    final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(socket.close);
    expect(find(socket.port, protocol: Protocol.udp), isNull);
    final scanned = find(socket.port, protocol: Protocol.udp, udp: true);
    expect(scanned?.process.details.pid, pid);
  });

  test('skips detection for processes the caller already knows', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final first = find(server.port)!;
    expect(first.process.insight, isNotNull);

    final again = scanWindows(ScanRequest(knownProcesses: {first.process.key}))
        .firstWhere((s) => s.port == server.port);
    expect(again.process.key, first.process.key);
    expect(again.process.insight, isNull);
  });

  group('another process', () {
    late Directory project;
    late Process child;
    late int port;

    setUp(() async {
      // A stand-in dev server: a child process, in its own project folder,
      // listening on a port it picked. The folder lives under build/ rather
      // than the system temp directory because nothing under AppData is ever
      // treated as a project.
      project = Directory(p.join(Directory.current.path, 'build', 'scan_fixture_$pid'))
        ..createSync(recursive: true);
      File(p.join(project.path, 'package.json'))
          .writeAsStringSync('{"name": "scan-fixture", "dependencies": {"express": "^4"}}');
      child = await Process.start('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'$l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); '
            r'$l.Start(); [Console]::Out.WriteLine($l.LocalEndpoint.Port); Start-Sleep 120',
      ], workingDirectory: project.path);
      port = int.parse(
        await child.stdout.transform(utf8.decoder).transform(const LineSplitter()).first,
      );
    });

    tearDown(() async {
      child.kill();
      await child.exitCode;
      project.deleteSync(recursive: true);
    });

    test('reads its working folder and command line, and names its project', () {
      final scanned = find(port)!;
      final process = scanned.process.details;
      expect(process.pid, child.pid);
      expect(process.name.toLowerCase(), 'powershell.exe');
      expect(p.equals(process.cwd!, project.path), isTrue);
      expect(process.commandLine, contains('TcpListener'));
      expect(process.parentPid, pid);

      final insight = scanned.process.insight!;
      expect(insight.project?.name, 'scan-fixture');
      expect(insight.project?.marker, 'package.json');
      expect(p.equals(insight.project!.root, project.path), isTrue);
      expect(insight.category, PortCategory.project);
      expect(insight.tech.name, 'PowerShell');
    });

    test('kill refuses when the pid now belongs to a different process', () {
      final stamp = find(port)!.process.details.startStamp!;
      expect(
        win32.terminateProcess(child.pid, expectedStartStamp: stamp + 1),
        KillResult.notFound,
      );
      expect(find(port), isNotNull, reason: 'process should have been spared');
    });

    test('kill ends it and the port is free by the time it returns', () async {
      final stamp = find(port)!.process.details.startStamp;
      expect(win32.terminateProcess(child.pid, expectedStartStamp: stamp), KillResult.killed);
      expect(find(port), isNull);
      expect(await child.exitCode, isNot(0));
      // Killing it again finds nothing to kill.
      expect(win32.terminateProcess(child.pid, expectedStartStamp: stamp), KillResult.notFound);
    });
  });

  test('kill reports a pid nobody has as not found', () {
    final taken = win32.snapshotProcesses().keys.toSet();
    var free = 4000000;
    while (taken.contains(free)) {
      free += 4;
    }
    expect(win32.terminateProcess(free), KillResult.notFound);
  });

  test(
    'kill reports access denied for a process we may not touch',
    () {
      // The kernel's pid exists but can never be opened for termination by an
      // ordinary user. (The app itself never offers to kill it.)
      expect(win32.terminateProcess(4), KillResult.accessDenied);
    },
    skip: _isElevated() ? 'only meaningful without administrator rights' : null,
  );

  test('maps Windows services to the processes hosting them', () {
    final services = win32.servicesByPid();
    final processes = win32.snapshotProcesses();
    expect(services, isNotEmpty);
    // Reading the pid at the wrong offset would produce pids nobody has.
    expect(services.keys.where(processes.containsKey), hasLength(services.length));
    expect(services.values.expand((names) => names), everyElement(isNotEmpty));
  });

  test('reads version resources', () {
    final system32 = p.join(Platform.environment['SystemRoot']!, 'System32');
    expect(win32.fileDescription(p.join(system32, 'cmd.exe')), isNotEmpty);
    expect(win32.fileDescription(p.join(system32, 'no-such-file.exe')), isNull);
  });
}
