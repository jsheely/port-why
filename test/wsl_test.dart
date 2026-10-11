import 'package:flutter_test/flutter_test.dart';
import 'package:port_why/src/data/windows/wsl.dart';
import 'package:port_why/src/detect/project_detector.dart';

/// Builds one record line the way the inspection script prints it.
String record(List<String> fields) => fields.join('\x1f');

const _apiId = 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';
const _postgresId = 'f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0';
const _mailId = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

/// A distribution running its own Docker engine, shaped like real output.
final _engine = [
  record(['L', 'LISTEN 0 4096 127.0.0.1:5432 0.0.0.0:* users:(("docker-proxy",pid=1187,fd=8))']),
  record(['L', 'LISTEN 0 4096 *:3000 *:* users:(("api",pid=1598,fd=32))']),
  record(['L', 'LISTEN 0 511 0.0.0.0:3001 0.0.0.0:* users:(("next-server (v",pid=1073,fd=18))']),
  record(['L', 'LISTEN 0 128 [::]:8080 [::]:* users:(("node",pid=77,fd=20),("node",pid=78,fd=20))']),
  // Held by a process in some other distribution: no users column at all.
  record(['L', 'LISTEN 0 4096 *:8025 *:*']),
  record([
    'P', '1187', '5000', '/usr/bin/docker-proxy', '/', r'\\wsl.localhost\dev\', '',
    '/usr/bin/docker-proxy -proto tcp -host-ip 127.0.0.1 -host-port 5432 -container-ip 172.18.0.3 -container-port 5432 ',
  ]),
  record(['P', '1598', '6000', '/api', '/', '', _apiId, './api --port 3000 ']),
  record(['P', '1073', '4000', '/usr/local/bin/node', '/app', '', '', 'next-server (v ']),
  record([
    'P', '77', '9000', '/usr/bin/node', '/home/me/code/shop', r'\\wsl.localhost\dev\home\me\code\shop', '',
    'node server.js ',
  ]),
  record(['C', _apiId, 'e2b-api-1', 'us-docker.pkg.dev/e2b/api/api:v0.14', '', 'e2b', '/opt/e2b', r'\\wsl.localhost\dev\opt\e2b']),
  record([
    'C', _postgresId, 'e2b-postgres-1', 'postgres:18.6-alpine', '127.0.0.1:5432->5432/tcp', 'e2b', '/opt/e2b',
    r'\\wsl.localhost\dev\opt\e2b',
  ]),
].join('\n');

/// A distribution that only has Docker Desktop's CLI: it can list containers
/// but sees none of their processes.
final _desktop = [
  record(['L', 'LISTEN 0 4096 *:8025 *:*']),
  record(['L', 'LISTEN 0 4096 *:3000 *:*']),
  record(['C', _mailId, 'mailpit', 'axllent/mailpit', '0.0.0.0:8025->8025/tcp, :::8025->8025/tcp', 'tools', r'C:\Users\me\tools', '']),
].join('\n');

void main() {
  group('parseWslReport', () {
    final report = parseWslReport('dev', _engine);

    test('maps each listening port to the pids holding it', () {
      expect(report.listeners[5432], {1187});
      expect(report.listeners[3000], {1598});
      // A process name with spaces and brackets does not derail the parse.
      expect(report.listeners[3001], {1073});
      expect(report.listeners[8080], {77, 78});
      expect(report.listeners[8025], isEmpty);
    });

    test('reads each process', () {
      final node = report.processes[77]!;
      expect(node.name, 'node');
      expect(node.cwd, '/home/me/code/shop');
      expect(node.hostCwd, r'\\wsl.localhost\dev\home\me\code\shop');
      expect(node.commandLine, 'node server.js');
      expect(node.startTicks, 9000);
      expect(node.containerId, isNull);

      final api = report.processes[1598]!;
      expect(api.name, 'api');
      expect(api.containerId, _apiId);
      // Inside a container there is no Windows path for its folder.
      expect(api.hostCwd, isNull);
    });

    test('reads each container', () {
      final postgres = report.containers.firstWhere((c) => c.info.name == 'e2b-postgres-1');
      expect(postgres.publishedPorts, {5432});
      expect(postgres.info.image, 'postgres:18.6-alpine');
      expect(postgres.info.composeProject, 'e2b');
      expect(postgres.info.directory, r'\\wsl.localhost\dev\opt\e2b');
      expect(postgres.distro, 'dev');
    });

    test('keeps a Compose folder recorded as a Windows path', () {
      final mail = parseWslReport('Ubuntu', _desktop).containers.single;
      expect(mail.info.directory, r'C:\Users\me\tools');
    });

    test('ignores malformed and unknown lines', () {
      final odd = parseWslReport('dev', 'garbage\n${record(['P', 'x'])}\n${record(['L'])}\n\n');
      expect(odd.listeners, isEmpty);
      expect(odd.processes, isEmpty);
      expect(odd.containers, isEmpty);
    });
  });

  group('ownerOf', () {
    final reports = [parseWslReport('Ubuntu', _desktop), parseWslReport('dev', _engine)];

    test('a plain process: the distribution that can name it wins', () {
      final owner = ownerOf(8080, reports)!;
      expect(owner.distro, 'dev');
      expect(owner.process!.pid, 77);
      expect(owner.container, isNull);

      final details = owner.toProcessDetails();
      expect(details.name, 'node');
      expect(details.pid, 77);
      expect(details.distro, 'dev');
      expect(details.cwd, '/home/me/code/shop');
      expect(details.hostCwd, r'\\wsl.localhost\dev\home\me\code\shop');
      expect(details.startStamp, 9000);
    });

    test('a containerised process is tied to its container by cgroup id', () {
      // Ubuntu lists port 3000 too, but only `dev` knows the process.
      final owner = ownerOf(3000, reports)!;
      expect(owner.distro, 'dev');
      expect(owner.process!.name, 'api');
      expect(owner.container!.name, 'e2b-api-1');
      expect(owner.isDockerProxy, isFalse);
      // The container's own "/" is not a folder Windows can open.
      expect(owner.toProcessDetails().hostCwd, isNull);
    });

    test('docker-proxy is traced to the container publishing the port', () {
      final owner = ownerOf(5432, reports)!;
      expect(owner.isDockerProxy, isTrue);
      expect(owner.container!.name, 'e2b-postgres-1');
      expect(owner.toProcessDetails().hostCwd, isNull);
    });

    test('with no visible process, a published port still names its container', () {
      final owner = ownerOf(8025, reports)!;
      expect(owner.process, isNull);
      expect(owner.container!.name, 'mailpit');
      expect(owner.distro, 'Ubuntu');
      final details = owner.toProcessDetails();
      expect(details.pid, 0);
      expect(details.name, 'mailpit');
    });

    test('a container process whose engine did not answer still resolves', () {
      final noDocker = parseWslReport(
        'dev',
        [
          record(['L', 'LISTEN 0 1 *:3000 *:* users:(("api",pid=5,fd=3))']),
          record(['P', '5', '1', '/api', '/', '', _apiId, './api']),
        ].join('\n'),
      );
      final owner = ownerOf(3000, [noDocker])!;
      expect(owner.process!.name, 'api');
      expect(owner.container, isNull);
    });

    test('an unknown port has no owner', () {
      expect(ownerOf(9999, reports), isNull);
      expect(ownerOf(3000, const []), isNull);
    });
  });

  test('publishedPorts reads host ports, ranges and both address families', () {
    expect(publishedPorts('127.0.0.1:8123->8123/tcp, 127.0.0.1:9000->9000/tcp, 9009/tcp'), {8123, 9000});
    expect(publishedPorts('0.0.0.0:8025->25/tcp, :::8025->25/tcp'), {8025});
    expect(publishedPorts('0.0.0.0:7000-7002->7000-7002/tcp'), {7000, 7001, 7002});
    expect(publishedPorts('0.0.0.0:53->53/udp'), isEmpty);
    expect(publishedPorts(''), isEmpty);
  });

  test('imageShortName drops the registry, tag and digest', () {
    expect(imageShortName('postgres:18.6-alpine'), 'postgres');
    expect(imageShortName('clickhouse/clickhouse-server:25.8'), 'clickhouse-server');
    expect(imageShortName('us-docker.pkg.dev/e2b-artifacts/api/api:v0.14'), 'api');
    expect(imageShortName('localhost:5000/team/web@sha256:abc'), 'web');
    expect(imageShortName('n8nio/n8n'), 'n8n');
  });

  group('project territory inside a distribution', () {
    final detector = ProjectDetector(environment: const {'USERPROFILE': r'C:\Users\me'});
    bool allowed(String linuxPath) => detector.isProjectTerritory(
      r'\\wsl.localhost\Ubuntu' + linuxPath.replaceAll('/', r'\'),
    );

    test('work folders count', () {
      expect(allowed('/home/me/code/shop'), isTrue);
      expect(allowed('/home/me/shop'), isTrue);
      expect(allowed('/root/shop'), isTrue);
      expect(allowed('/opt/e2b'), isTrue);
      expect(allowed('/srv/www'), isTrue);
      expect(allowed('/workspace'), isTrue);
    });

    test('the root, home folders and tool caches do not', () {
      expect(allowed(''), isFalse);
      expect(allowed('/home'), isFalse);
      expect(allowed('/home/me'), isFalse);
      expect(allowed('/root'), isFalse);
      expect(allowed('/home/me/.nvm/versions/node'), isFalse);
      expect(allowed('/root/.cache/x'), isFalse);
    });

    test('system directories do not', () {
      for (final path in ['/usr/lib/node_modules/npm', '/var/lib/docker', '/etc', '/tmp/x', '/snap/core']) {
        expect(allowed(path), isFalse, reason: path);
      }
    });

    test(r'the older \\wsl$ share name is understood too', () {
      expect(detector.isProjectTerritory(r'\\wsl$\Ubuntu\home\me'), isFalse);
      expect(detector.isProjectTerritory(r'\\wsl$\Ubuntu\home\me\shop'), isTrue);
    });
  });
}
