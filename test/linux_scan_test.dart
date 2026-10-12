@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:port_why/src/data/posix/posix_scan.dart';
import 'package:port_why/src/data/scan.dart';
import 'package:port_why/src/models.dart';

/// These read the real /proc against real sockets and processes.
void main() {
  Future<ScannedPort?> find(int port, {Protocol protocol = Protocol.tcp, bool udp = false}) async {
    for (final scanned in await scanPosix(ScanRequest(includeUdp: udp), HostOs.linux)) {
      if (scanned.port == port && scanned.protocol == protocol) return scanned;
    }
    return null;
  }

  test('finds a port this process opens, with our pid, path and folder', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    final scanned = await find(server.port);
    expect(scanned, isNotNull, reason: 'port ${server.port} not reported');
    expect(scanned!.addresses, ['127.0.0.1']);

    final process = scanned.process.details;
    expect(process.pid, pid);
    expect(process.exePath, Platform.resolvedExecutable);
    expect(process.cwd, Directory.current.path);
    expect(process.commandLine, isNotEmpty);
    expect(process.restricted, isFalse);
    expect(process.startStamp, isNotNull);
    expect(process.parentName, isNotNull);
    final age = DateTime.now().difference(process.startedAt!);
    expect(age.inSeconds, inInclusiveRange(0, 600));

    await server.close();
    expect(await find(server.port), isNull, reason: 'closed port still reported');
  });

  test('a listener on every interface reports the address it is bound to', () async {
    final server = await ServerSocket.bind(InternetAddress.anyIPv6, 0, v6Only: false);
    addTearDown(server.close);
    expect((await find(server.port))?.addresses, ['::']);
  });

  test('reports UDP only when asked', () async {
    final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(socket.close);
    expect(await find(socket.port, protocol: Protocol.udp), isNull);
    final scanned = await find(socket.port, protocol: Protocol.udp, udp: true);
    expect(scanned?.process.details.pid, pid);
  });

  test('skips detection for processes the caller already knows', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final first = (await find(server.port))!;
    expect(first.process.insight, isNotNull);

    final again = (await scanPosix(
      ScanRequest(knownProcesses: {first.process.key}),
      HostOs.linux,
    )).firstWhere((s) => s.port == server.port);
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
      // than the system temp directory because nothing under /tmp is ever
      // treated as a project.
      project = Directory('${Directory.current.path}/build/scan_fixture_$pid')
        ..createSync(recursive: true);
      File('${project.path}/package.json')
          .writeAsStringSync('{"name": "scan-fixture", "dependencies": {"flask": "^3"}}');
      child = await Process.start('python3', [
        '-c',
        'import socket, sys, time\n'
            's = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen()\n'
            'print(s.getsockname()[1]); sys.stdout.flush(); time.sleep(120)',
      ], workingDirectory: project.path);
      port = int.parse(
        await child.stdout.transform(utf8.decoder).transform(const LineSplitter()).first,
      );
    });

    tearDown(() async {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode;
      project.deleteSync(recursive: true);
    });

    test('reads its working folder and command line, and names its project', () async {
      final scanned = (await find(port))!;
      final process = scanned.process.details;
      expect(process.pid, child.pid);
      expect(process.name, startsWith('python3'));
      expect(process.cwd, project.path);
      expect(process.commandLine, contains('socket.socket()'));
      expect(process.parentPid, pid);

      final insight = scanned.process.insight!;
      expect(insight.project?.name, 'scan-fixture');
      expect(insight.project?.marker, 'package.json');
      expect(insight.project?.root, project.path);
      expect(insight.category, PortCategory.project);
      expect(insight.tech.runtime ?? insight.tech.name, 'Python');
    });

    test('kill refuses when the pid now belongs to a different process', () async {
      final stamp = (await find(port))!.process.details.startStamp!;
      expect(
        await terminateProcess(child.pid, HostOs.linux, expectedStartStamp: stamp + 1),
        KillResult.notFound,
      );
      expect(await find(port), isNotNull, reason: 'process should have been spared');
    });

    test('kill ends it and the port is free by the time it returns', () async {
      final stamp = (await find(port))!.process.details.startStamp;
      expect(
        await terminateProcess(child.pid, HostOs.linux, expectedStartStamp: stamp),
        KillResult.killed,
      );
      expect(await find(port), isNull);
      expect(await child.exitCode, isNot(0));
      // Killing it again finds nothing to kill.
      expect(
        await terminateProcess(child.pid, HostOs.linux, expectedStartStamp: stamp),
        KillResult.notFound,
      );
    });
  }, skip: Process.runSync('which', ['python3']).exitCode == 0 ? null : 'needs python3');

  test('kill reports a pid nobody has as not found', () async {
    expect(await terminateProcess(4194000, HostOs.linux), KillResult.notFound);
  });

  test(
    'kill reports access denied for a process we may not touch',
    () async {
      expect(await terminateProcess(1, HostOs.linux), KillResult.accessDenied);
    },
    skip: Process.runSync('id', ['-u']).stdout.toString().trim() == '0'
        ? 'only meaningful without root'
        : null,
  );
}
