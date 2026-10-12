import 'package:flutter_test/flutter_test.dart';
import 'package:port_why/src/data/docker.dart';
import 'package:port_why/src/data/posix/linux_proc.dart' as linux;
import 'package:port_why/src/data/posix/macos_tools.dart' as macos;
import 'package:port_why/src/data/posix/posix_scan.dart';
import 'package:port_why/src/data/scan.dart';
import 'package:port_why/src/detect/project_detector.dart';
import 'package:port_why/src/models.dart';
import 'package:port_why/src/state/ports_controller.dart';

import 'support.dart';

/// What the scanners on macOS and Linux make of what those systems print.
/// None of this touches the machine it runs on.
void main() {
  group('/proc/net on Linux', () {
    const heading =
        '  sl  local_address rem_address   st tx_queue rx_queue tr tm->when '
        'retrnsmt   uid  timeout inode\n';

    test('reads listening sockets, their owner and their inode', () {
      final sockets = linux.parseProcNet(
        '$heading'
        '   0: 0100007F:1538 00000000:0000 0A 00000000:00000000 00:00000000 00000000   999        0 23456 1 0000000000000000 100 0 0 10 0\n'
        '   1: 00000000:0016 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 1234 1 0000000000000000 100 0 0 10 0\n'
        // An established connection, which is not a listener.
        '   2: 0100007F:C350 0100007F:1538 01 00000000:00000000 00:00000000 00000000  1000        0 9999 1 0000000000000000 20 4 30 10 -1\n',
        Protocol.tcp,
      );
      expect(
        [for (final s in sockets) (s.address, s.port, s.uid, s.inode)],
        [('127.0.0.1', 5432, 999, 23456), ('0.0.0.0', 22, 0, 1234)],
      );
    });

    test('reads IPv6 addresses, and IPv4 ones behind an IPv6 socket', () {
      final sockets = linux.parseProcNet(
        '$heading'
        '   0: 00000000000000000000000001000000:0BB8 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 777 1 0000000000000000 100 0 0 10 0\n'
        '   1: 00000000000000000000000000000000:1F90 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 778 1 0000000000000000 100 0 0 10 0\n'
        '   2: 0000000000000000FFFF00000100007F:2382 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 779 1 0000000000000000 100 0 0 10 0\n',
        Protocol.tcp,
      );
      expect(
        [for (final s in sockets) (s.address, s.port)],
        [('::1', 3000), ('::', 8080), ('127.0.0.1', 9090)],
      );
    });

    test('takes every bound UDP socket, whatever its state', () {
      final sockets = linux.parseProcNet(
        '$heading'
        '  512: 00000000:14E9 00000000:0000 07 00000000:00000000 00:00000000 00000000   108        0 4321 2 0000000000000000 0\n',
        Protocol.udp,
      );
      expect([for (final s in sockets) (s.address, s.port)], [('0.0.0.0', 5353)]);
    });
  });

  group('lsof and ps on macOS', () {
    test('reads listeners from lsof, a field to a line', () {
      final sockets = macos.parseLsofSockets(
        'p812\ncControlCe\nf9\ntIPv4\nPTCP\nn*:7000\nf10\ntIPv6\nPTCP\nn*:7000\n'
        'p4127\ncnode\nf23\ntIPv6\nPTCP\nn[::1]:5173\nf24\ntIPv4\nPTCP\nn127.0.0.1:5173\n'
        // UDP: bound, bound to no port yet, and connected.
        'p900\ncmDNSRespo\nf6\ntIPv4\nPUDP\nn*:5353\nf7\ntIPv4\nPUDP\nn*:*\n'
        'f8\ntIPv4\nPUDP\nn192.168.1.5:50000->1.2.3.4:443\n',
      );
      expect(
        [for (final s in sockets) (s.pid, s.protocol, s.address, s.port)],
        [
          (812, Protocol.tcp, '0.0.0.0', 7000),
          (812, Protocol.tcp, '::', 7000),
          (4127, Protocol.tcp, '::1', 5173),
          (4127, Protocol.tcp, '127.0.0.1', 5173),
          (900, Protocol.udp, '0.0.0.0', 5353),
          (900, Protocol.udp, '192.168.1.5', 50000),
        ],
      );
    });

    test('reads the process table, spaces in paths and all', () {
      final table = macos.parsePs(
        '    1     0     0 Thu Oct  1 08:00:01 2026 /sbin/launchd\n'
        ' 4127   530   501 Sun Oct 11 14:03:22 2026 /opt/homebrew/Cellar/node/24.1.0/bin/node\n'
        '  615     1   501 Sat Oct 10 09:15:00 2026 /Applications/Visual Studio Code.app/Contents/MacOS/Electron\n',
      );
      expect(table.keys, [1, 4127, 615]);
      final node = table[4127]!;
      expect(node.parentPid, 530);
      expect(node.uid, 501);
      expect(node.name, 'node');
      expect(node.startedAt, DateTime(2026, 10, 11, 14, 3, 22));
      expect(table[1]!.startedAt, DateTime(2026, 10, 1, 8, 0, 1));
      expect(table[615]!.name, 'Electron');
      expect(macos.bundleName(table[615]!.executable), 'Visual Studio Code');
      expect(macos.bundleName(node.executable), isNull);
    });

    test('reads command lines and working folders by pid', () {
      expect(
        macos.parsePsArguments(' 4127 node /Users/me/shop/node_modules/.bin/vite --port 5173\n  615 /Applications/Visual Studio Code.app/Contents/MacOS/Electron\n'),
        {
          4127: 'node /Users/me/shop/node_modules/.bin/vite --port 5173',
          615: '/Applications/Visual Studio Code.app/Contents/MacOS/Electron',
        },
      );
      expect(
        macos.parseLsofFolders('p4127\nfcwd\nn/Users/me/shop\np615\nfcwd\nn/\n'),
        {4127: '/Users/me/shop', 615: '/'},
      );
    });
  });

  group('rows', () {
    final detector = ProjectDetector(environment: const {'HOME': '/home/me'});

    PosixSnapshot snapshot({bool keepDetails = false}) => PosixSnapshot(
      ownUid: 1000,
      userNames: const {0: 'root', 1000: 'me'},
      keepDetails: keepDetails,
      sockets: const [
        BoundSocket(protocol: Protocol.tcp, address: '::1', port: 5173, pid: 4127, uid: 1000, inode: 11),
        BoundSocket(protocol: Protocol.tcp, address: '127.0.0.1', port: 5173, pid: 4127, uid: 1000, inode: 12),
        // Nobody we can see holds these two.
        BoundSocket(protocol: Protocol.tcp, address: '0.0.0.0', port: 5432, uid: 0, inode: 21),
        BoundSocket(protocol: Protocol.tcp, address: '::', port: 5432, uid: 0, inode: 22),
      ],
      processes: const {
        4127: PosixProcess(
          pid: 4127,
          name: 'node',
          parentPid: 530,
          uid: 1000,
          exePath: '/usr/bin/node',
          commandLine: 'node /home/me/code/shop/node_modules/.bin/vite --port 5173',
          cwd: '/home/me/code/shop',
          startStamp: 9000,
        ),
        530: PosixProcess(pid: 530, name: 'bash', uid: 1000, commandLine: '-bash'),
      },
    );

    test('one per port and owner, with both address families together', () {
      final ports = assemblePorts(const ScanRequest(), snapshot(), HostOs.linux, projects: detector);
      expect(ports, hasLength(2));

      final vite = ports.first;
      expect(vite.port, 5173);
      expect(vite.addresses, ['127.0.0.1', '::1']);
      expect(vite.process.details.pid, 4127);
      expect(vite.process.details.parentName, 'bash');
      expect(vite.process.details.restricted, isFalse);
      expect(vite.process.insight!.tech.name, 'Vite');
      expect(vite.process.insight!.tech.runtime, 'Node.js');
      expect(vite.process.insight!.project?.name, 'shop');
      expect(vite.process.insight!.category, PortCategory.project);
    });

    test('a socket nobody can be found for says whose it is', () {
      final hidden = assemblePorts(const ScanRequest(), snapshot(), HostOs.linux, projects: detector).last;
      expect(hidden.port, 5432);
      expect(hidden.addresses, ['0.0.0.0', '::']);
      expect(hidden.process.details.pid, 0);
      expect(hidden.process.details.name, 'owned by root');
      expect(hidden.process.details.restricted, isTrue);
      expect(hidden.process.insight!.category, PortCategory.system);
    });

    test('skips detection for processes the caller already knows', () {
      final first = assemblePorts(const ScanRequest(), snapshot(), HostOs.linux, projects: detector).first;
      final again = assemblePorts(
        ScanRequest(knownProcesses: {first.process.key}),
        snapshot(),
        HostOs.linux,
        projects: detector,
      ).first;
      expect(again.process.key, first.process.key);
      expect(again.process.insight, isNull);
    });

    test('on macOS a process keeps its key when its folder is not read again', () {
      final first = assemblePorts(const ScanRequest(), snapshot(keepDetails: true), HostOs.macos, projects: detector).first;
      expect(first.process.keepDetails, isTrue);
      expect(first.process.key, isNot(contains('/home/me')));
    });

    test('a port Docker holds is traced to the container publishing it', () async {
      final ports = assemblePorts(const ScanRequest(), snapshot(), HostOs.linux, projects: detector);
      var asked = 0;
      Future<List<PublishedContainer>?> containers() async {
        asked++;
        return parseContainers(
          '3f9a1c2b7d10\x1forders-db-1\x1fpostgres:17\x1f0.0.0.0:5432->5432/tcp, :::5432->5432/tcp\x1forders\x1f/nowhere/orders\n',
        );
      }

      final traced = await traceContainers(const ScanRequest(), ports, containers);
      expect(asked, 1);
      final database = traced.last.process;
      expect(database.details.container?.name, 'orders-db-1');
      expect(database.details.pid, 0);
      expect(database.keepDetails, isTrue);
      expect(database.insight!.tech.name, 'PostgreSQL');
      expect(database.insight!.project?.name, 'orders');
      expect(database.insight!.project?.marker, ProjectInfo.composeMarker);
      // The dev server is nobody's relay, and was left as it was.
      expect(traced.first.process.details.pid, 4127);

      // Once the caller knows the answer, Docker is not asked again.
      final again = await traceContainers(
        ScanRequest(knownProcesses: {database.key}),
        assemblePorts(const ScanRequest(), snapshot(), HostOs.linux, projects: detector),
        containers,
      );
      expect(asked, 1);
      expect(again.last.process.key, database.key);
    });

    test('an answer Docker never gave is not remembered', () async {
      final ports = assemblePorts(const ScanRequest(), snapshot(), HostOs.linux, projects: detector);
      final traced = await traceContainers(const ScanRequest(), ports, () async => null);
      expect(traced.last.process.remember, isFalse);
      expect(traced.last.process.details.name, 'owned by root');
    });
  });

  test('arguments holding spaces are quoted, so they split back the same', () {
    const arguments = ['node', '/home/me/my app/server.js', '--port', '3000'];
    final line = joinArguments(arguments);
    expect(line, 'node "/home/me/my app/server.js" --port 3000');
    expect(splitCommandLine(line), arguments);
  });

  group('where projects live on macOS and Linux', () {
    final linuxHome = ProjectDetector(environment: const {'HOME': '/home/me'});
    final macHome = ProjectDetector(environment: const {'HOME': '/Users/me'});

    test('in and around a home folder', () {
      expect(linuxHome.isProjectTerritory('/home/me/code/shop'), isTrue);
      expect(linuxHome.isProjectTerritory('/home/me'), isFalse);
      expect(linuxHome.isProjectTerritory('/home'), isFalse);
      expect(linuxHome.isProjectTerritory('/home/me/.nvm/versions/node'), isFalse);
      expect(linuxHome.isProjectTerritory('/home/me/snap/code/190'), isFalse);
      expect(linuxHome.isProjectTerritory('/home/someone-else/site'), isTrue);
      expect(macHome.isProjectTerritory('/Users/me/Developer/shop'), isTrue);
      expect(macHome.isProjectTerritory('/Users/me/Library/Application Support/Code'), isFalse);
      expect(macHome.isProjectTerritory('/Users/me/Applications/Tool.app/Contents'), isFalse);
    });

    test('not where the system and its packages are installed', () {
      for (final folder in const [
        '/',
        '/usr/lib/node_modules/npm',
        '/tmp/scratch',
        '/var/www/html',
        '/Applications/Docker.app/Contents/Resources',
        '/System/Library/CoreServices',
        '/private/tmp/scratch',
        '/opt/homebrew/lib/node_modules/npm',
      ]) {
        expect(macHome.isProjectTerritory(folder), isFalse, reason: folder);
      }
      expect(linuxHome.isProjectTerritory('/opt/acme/api'), isTrue);
      expect(linuxHome.isProjectTerritory('/srv/site'), isTrue);
      expect(macHome.isProjectTerritory('/Volumes/Work/shop'), isTrue);
    });

    test('a home folder somewhere unusual is still a home folder', () {
      final detector = ProjectDetector(environment: const {'HOME': '/data/people/me'});
      expect(detector.isProjectTerritory('/data/people/me'), isFalse);
      expect(detector.isProjectTerritory('/data/people/me/.cache/thing'), isFalse);
      expect(detector.isProjectTerritory('/data/people/me/code/shop'), isTrue);
    });
  });

  group('killing on macOS and Linux', () {
    PortsController controllerFor(HostOs os, List<PortEntry> entries) =>
        PortsController(FakePortRepository(entries)..os = os, ownPid: 4242);

    test('is blocked for init, the app itself and what cannot be seen', () async {
      final controller = controllerFor(HostOs.linux, [
        entry(port: 22, pid: 0, name: 'owned by root', restricted: true),
        entry(port: 111, pid: 1, name: 'systemd'),
        entry(port: 50000, pid: 4242, name: 'port_why'),
        // Pids this low are ordinary processes away from Windows.
        entry(port: 3000, pid: 3, name: 'node'),
      ]);
      addTearDown(controller.dispose);
      await controller.refresh();
      String? reason(int port) =>
          controller.killBlockedReason(controller.entries.firstWhere((e) => e.port == port));

      expect(reason(22), contains('only root can see'));
      expect(reason(111), 'Linux cannot run without systemd');
      expect(reason(50000), contains('Port Why itself'));
      expect(reason(3000), isNull);
      expect(controller.restrictedProcessCount, 1);
    });

    test('a container is stopped whether or not its process can be seen', () async {
      final controller = controllerFor(HostOs.macos, [
        entry(
          port: 5432,
          pid: 0,
          name: 'orders-db-1',
          container: const ContainerInfo(id: '3f9a1c2b7d10', name: 'orders-db-1', image: 'postgres:17'),
        ),
      ]);
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.killBlockedReason(controller.entries.single), isNull);
    });
  });
}
