/// What the Docker CLI can say about who publishes a port.
///
/// On Windows it is reached through WSL (see windows/wsl.dart); on macOS and
/// Linux it is run directly.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../detect/tech_detector.dart';
import '../models.dart';
import 'scan.dart';

/// ASCII unit separator: cannot appear in a name, image or path.
const _field = '\x1f';

/// A running container and the host ports it publishes.
class PublishedContainer {
  const PublishedContainer({required this.info, this.publishedPorts = const {}});

  final ContainerInfo info;
  final Set<int> publishedPorts;
}

/// Host TCP ports from `docker ps` output such as
/// `127.0.0.1:8123->8123/tcp, :::9000-9002->9000-9002/tcp, 9009/tcp`.
Set<int> publishedPorts(String ports) {
  final result = <int>{};
  for (final match in RegExp(r':(\d+)(?:-(\d+))?->[\d-]+/tcp').allMatches(ports)) {
    final first = int.parse(match[1]!);
    final last = match[2] == null ? first : int.parse(match[2]!);
    for (var port = first; port <= last && port - first < 1024; port++) {
      result.add(port);
    }
  }
  return result;
}

/// `ghcr.io/acme/api:1.2` becomes `api`.
String imageShortName(String image) {
  final withoutDigest = image.split('@').first;
  final name = withoutDigest.split('/').last;
  return name.split(':').first;
}

/// What a container is and which project it belongs to.
///
/// The image says what a container is. [fromProcess], what the process inside
/// looks like, says more when it is a runtime we can read (node running
/// Next.js).
ProcessInsight containerInsight(ContainerInfo container, {TechInfo? fromProcess}) {
  final fromImage = const TechDetector().detect(
    pid: 0,
    processName: imageShortName(container.image),
  );
  final tech =
      fromProcess != null && (fromProcess.icon != null || fromImage.icon == null)
      ? fromProcess
      : fromImage;

  final composeProject = container.composeProject;
  return ProcessInsight(
    tech: withFallbackIcon(tech, 'docker'),
    project: composeProject == null
        ? null
        : ProjectInfo(
            name: composeProject,
            root: container.directory ?? '',
            marker: ProjectInfo.composeMarker,
          ),
    category: composeProject == null ? PortCategory.app : PortCategory.project,
  );
}

const _psFormat =
    '{{.ID}}$_field{{.Names}}$_field{{.Image}}$_field{{.Ports}}$_field'
    '{{.Label "com.docker.compose.project"}}$_field'
    '{{.Label "com.docker.compose.project.working_dir"}}';

/// Parses `docker ps --no-trunc --format` [_psFormat].
List<PublishedContainer> parseContainers(String output) => [
  for (final line in const LineSplitter().convert(output))
    if (line.split(_field) case [
      final id,
      final name,
      final image,
      final ports,
      final project,
      final folder,
      ...,
    ])
      PublishedContainer(
        publishedPorts: publishedPorts(ports),
        info: ContainerInfo(
          id: id,
          name: name,
          image: image,
          composeProject: project.isEmpty ? null : project,
          directory: folder.isNotEmpty && Directory(folder).existsSync()
              ? folder
              : null,
        ),
      ),
];

/// The running containers, or null if Docker did not answer in time. Empty
/// when there is no Docker here, or none we are allowed to ask.
Future<List<PublishedContainer>?> runningContainers() async {
  final docker = _dockerCli();
  if (docker == null) return const [];
  final result = await _run(docker, const [
    'ps',
    '--no-trunc',
    '--format',
    _psFormat,
  ], timeout: const Duration(seconds: 3));
  if (result == null) return null;
  return result.exitCode == 0 ? parseContainers(result.stdout) : const [];
}

/// Stops a container through the Docker CLI on this machine.
Future<KillResult> stopContainer(String containerId) async {
  final docker = _dockerCli();
  if (docker == null) return KillResult.failed;
  final found = await _run(docker, [
    'inspect',
    containerId,
  ], timeout: const Duration(seconds: 5));
  if (found == null) return KillResult.failed;
  if (found.exitCode != 0) return KillResult.notFound;
  final stopped = await _run(docker, [
    'stop',
    '-t',
    '3',
    containerId,
  ], timeout: const Duration(seconds: 25));
  return stopped?.exitCode == 0 ? KillResult.killed : KillResult.failed;
}

/// An app started from the Dock or a launcher gets a bare PATH, so the usual
/// places are tried as well.
String? _dockerCli() {
  final home = Platform.environment['HOME'];
  final folders = [
    ...?Platform.environment['PATH']?.split(':'),
    '/usr/local/bin',
    '/opt/homebrew/bin',
    '/usr/bin',
    if (home != null) '$home/.docker/bin',
    '/Applications/Docker.app/Contents/Resources/bin',
  ];
  for (final folder in folders) {
    if (folder.isEmpty) continue;
    final candidate = '$folder/docker';
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

Future<({int exitCode, String stdout})?> _run(
  String executable,
  List<String> arguments, {
  required Duration timeout,
}) async {
  final Process process;
  try {
    process = await Process.start(executable, arguments);
  } on ProcessException {
    return null;
  }
  final output = process.stdout.transform(utf8.decoder).join();
  unawaited(process.stderr.drain<void>());

  const timedOut = -0x7fffffff;
  final exitCode = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      process.kill();
      return timedOut;
    },
  );
  if (exitCode == timedOut) return null;
  return (exitCode: exitCode, stdout: await output);
}
