/// Looks inside running WSL distributions to find what is really listening
/// behind a port.
///
/// Windows only ever sees `wslrelay.exe` there: the relay that forwards
/// `localhost` into the WSL virtual machine. Every distribution shares one
/// network stack but has its own process ids, so each running distribution is
/// asked in turn and only the one that owns a listener can name it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models.dart';
import '../docker.dart';

export '../docker.dart' show imageShortName, publishedPorts;

/// ASCII unit separator: cannot appear in a path, name or command line.
const _field = '\x1f';

/// Runs as root inside a distribution and prints one record per line:
///
///  * `L` a raw `ss` line for each listening TCP socket,
///  * `P` each process owning one: pid, start time, exe, cwd, cwd as a
///    Windows path, container id, command line,
///  * `C` each running Docker container: id, name, image, ports, compose
///    project, compose folder, compose folder as a Windows path.
///
/// Root is needed to see listeners owned by other users, docker-proxy among
/// them. Nothing here changes any state.
const _inspectScript = r'''
S=$(printf '\037')
command -v ss >/dev/null 2>&1 && {
  self=$(readlink /proc/self/ns/mnt)
  ss -H -ltnp 2>/dev/null | sed "s/^/L$S/"
  for pid in $(ss -H -ltnp 2>/dev/null | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u); do
    [ -d /proc/$pid ] || continue
    exe=$(readlink /proc/$pid/exe 2>/dev/null)
    cwd=$(readlink /proc/$pid/cwd 2>/dev/null)
    # A different mount namespace means a container: its paths are its own.
    host=
    if [ -n "$cwd" ] && [ "$(readlink /proc/$pid/ns/mnt 2>/dev/null)" = "$self" ]; then
      host=$(wslpath -w "$cwd" 2>/dev/null)
    fi
    start=$(sed 's/.*) //' /proc/$pid/stat 2>/dev/null | cut -d' ' -f20)
    cid=$(grep -o -E '[0-9a-f]{64}' /proc/$pid/cgroup 2>/dev/null | head -n 1)
    cmd=$(tr '\0\n' '  ' < /proc/$pid/cmdline 2>/dev/null)
    printf 'P%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
      "$S" "$pid" "$S" "$start" "$S" "$exe" "$S" "$cwd" "$S" "$host" "$S" "$cid" "$S" "$cmd"
  done
}
command -v docker >/dev/null 2>&1 && {
  fmt='{{.ID}}'"$S"'{{.Names}}'"$S"'{{.Image}}'"$S"'{{.Ports}}'"$S"'{{.Label `com.docker.compose.project`}}'"$S"'{{.Label `com.docker.compose.project.working_dir`}}'
  timeout 3 docker ps --no-trunc --format "$fmt" 2>/dev/null |
    while IFS="$S" read -r id name image ports project dir; do
      host=
      [ -n "$dir" ] && [ -d "$dir" ] && host=$(wslpath -w "$dir" 2>/dev/null)
      printf 'C%s%s%s%s%s%s%s%s%s%s%s%s%s%s\n' \
        "$S" "$id" "$S" "$name" "$S" "$image" "$S" "$ports" "$S" "$project" "$S" "$dir" "$S" "$host"
    done
}
exit 0
''';

/// A process that owns a listening socket inside a distribution.
class WslProcess {
  const WslProcess({
    required this.pid,
    this.startTicks,
    this.exe,
    this.cwd,
    this.hostCwd,
    this.containerId,
    this.commandLine,
  });

  final int pid;

  /// Start time in clock ticks since boot; with [pid], identifies the process.
  final int? startTicks;
  final String? exe;
  final String? cwd;
  final String? hostCwd;
  final String? containerId;
  final String? commandLine;

  /// The executable's file name, falling back to the first word of the
  /// command line.
  String get name {
    final path = exe ?? commandLine?.trim().split(' ').first;
    if (path == null || path.isEmpty) return 'pid $pid';
    return p.posix.basename(path.replaceFirst(RegExp(r' \(deleted\)$'), ''));
  }
}

/// A running container and the host ports it publishes.
class WslContainer {
  const WslContainer({
    required this.info,
    required this.distro,
    this.publishedPorts = const {},
  });

  final ContainerInfo info;

  /// The distribution whose Docker CLI reported it.
  final String distro;
  final Set<int> publishedPorts;
}

/// Everything one distribution told us.
class WslReport {
  const WslReport({
    required this.distro,
    this.listeners = const {},
    this.processes = const {},
    this.containers = const [],
  });

  final String distro;

  /// Listening TCP port to the pids holding it. Empty for sockets that belong
  /// to another distribution's processes.
  final Map<int, Set<int>> listeners;
  final Map<int, WslProcess> processes;
  final List<WslContainer> containers;
}

/// What turned out to be behind a relayed port.
class WslOwner {
  const WslOwner({required this.distro, this.process, this.container});

  final String distro;

  /// Null when only the container is known (its process lives in a
  /// distribution we cannot look inside, such as Docker Desktop's).
  final WslProcess? process;
  final ContainerInfo? container;

  /// True when the listener is Docker's port forwarder rather than the
  /// service itself, so the process says nothing about what is running.
  bool get isDockerProxy => process?.name == 'docker-proxy';

  ProcessDetails toProcessDetails() {
    final process = this.process;
    final container = this.container;
    return ProcessDetails(
      pid: process?.pid ?? 0,
      name: process?.name ?? container?.name ?? distro,
      exePath: process?.exe,
      commandLine: process?.commandLine,
      cwd: process?.cwd,
      // A container's process reports paths inside the container, and the
      // proxy's own folder is irrelevant; neither is somewhere to open.
      hostCwd: container == null ? process?.hostCwd : null,
      startStamp: process?.startTicks,
      distro: distro,
      container: container,
    );
  }
}

/// Finds who owns TCP [port], looking across every distribution's report.
WslOwner? ownerOf(int port, List<WslReport> reports) {
  for (final report in reports) {
    for (final pid in report.listeners[port] ?? const <int>{}) {
      final process = report.processes[pid];
      if (process == null) continue;
      final container = process.name == 'docker-proxy'
          ? _publisherOf(port, report.containers)
          : _containerWithId(process.containerId, report.containers);
      return WslOwner(
        distro: report.distro,
        process: process,
        container: container?.info,
      );
    }
  }
  // No distribution can see the process, but a Docker engine may still say
  // which container publishes the port (Docker Desktop keeps its containers
  // in a distribution of its own).
  for (final report in reports) {
    final container = _publisherOf(port, report.containers);
    if (container != null) {
      return WslOwner(distro: container.distro, container: container.info);
    }
  }
  return null;
}

WslContainer? _publisherOf(int port, List<WslContainer> containers) {
  for (final container in containers) {
    if (container.publishedPorts.contains(port)) return container;
  }
  return null;
}

WslContainer? _containerWithId(String? id, List<WslContainer> containers) {
  if (id == null) return null;
  for (final container in containers) {
    if (container.info.id == id) return container;
  }
  return null;
}

/// Parses the output of [_inspectScript].
WslReport parseWslReport(String distro, String output) {
  final listeners = <int, Set<int>>{};
  final processes = <int, WslProcess>{};
  final containers = <WslContainer>[];
  String? text(String field) => field.isEmpty ? null : field;

  for (final line in const LineSplitter().convert(output)) {
    final fields = line.split(_field);
    switch (fields.first) {
      case 'L' when fields.length >= 2:
        // LISTEN 0 4096 127.0.0.1:5432 0.0.0.0:* users:(("name",pid=1,fd=8))
        final columns = fields[1].trim().split(RegExp(r'\s+'));
        if (columns.length < 4) continue;
        final local = columns[3];
        final port = int.tryParse(local.substring(local.lastIndexOf(':') + 1));
        if (port == null) continue;
        final pids = listeners.putIfAbsent(port, () => {});
        for (final match in RegExp(r'pid=(\d+)').allMatches(fields[1])) {
          pids.add(int.parse(match[1]!));
        }
      case 'P' when fields.length >= 8:
        final pid = int.tryParse(fields[1]);
        if (pid == null) continue;
        processes[pid] = WslProcess(
          pid: pid,
          startTicks: int.tryParse(fields[2]),
          exe: text(fields[3]),
          cwd: text(fields[4]),
          hostCwd: text(fields[5]),
          containerId: text(fields[6]),
          commandLine: text(fields[7].trim()),
        );
      case 'C' when fields.length >= 8:
        final declaredFolder = fields[6];
        containers.add(
          WslContainer(
            distro: distro,
            publishedPorts: publishedPorts(fields[4]),
            info: ContainerInfo(
              id: fields[1],
              name: fields[2],
              image: fields[3],
              composeProject: text(fields[5]),
              // Compose run from Windows records a Windows path, which is
              // already something Explorer can open.
              directory:
                  text(fields[7]) ??
                  (p.windows.isAbsolute(declaredFolder) &&
                          !declaredFolder.startsWith('/')
                      ? declaredFolder
                      : null),
            ),
          ),
        );
    }
  }
  return WslReport(
    distro: distro,
    listeners: listeners,
    processes: processes,
    containers: containers,
  );
}

/// The outcome of asking every running distribution.
typedef WslInspection = ({List<WslReport> reports, bool complete});

/// Inspects every running distribution at once. [complete] is false when any
/// of them (or WSL itself) failed to answer in time, in which case an
/// unattributed port may simply not have been looked up.
Future<WslInspection> inspectWsl() async {
  final distros = await runningDistros();
  if (distros == null) return (reports: const <WslReport>[], complete: false);
  final reports = await Future.wait(distros.map(inspectDistro));
  return (
    reports: reports.nonNulls.toList(),
    complete: !reports.contains(null),
  );
}

/// Names of the distributions that are running right now, or null if WSL
/// could not be asked. Never starts one: only running ones can hold a port.
Future<List<String>?> runningDistros() async {
  final result = await _run('wsl.exe', const [
    '--list',
    '--running',
    '--quiet',
  ], timeout: const Duration(seconds: 4));
  if (result == null) return null;
  // Older builds ignore WSL_UTF8 and answer in UTF-16.
  final bytes = result.stdout;
  final text = bytes.contains(0)
      ? String.fromCharCodes([
          for (var i = 0; i + 1 < bytes.length; i += 2)
            bytes[i] | bytes[i + 1] << 8,
        ])
      : utf8.decode(bytes, allowMalformed: true);
  return [
    for (final line in const LineSplitter().convert(text))
      // Anything else on stdout is a message ("no running distributions").
      if (_distroName.hasMatch(line.trim()) &&
          // Docker Desktop's own distributions hold no user processes and
          // have none of the tools the inspection needs.
          !line.trim().startsWith('docker-desktop'))
        line.trim(),
  ];
}

final _distroName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

/// Inspects one distribution, or null if it did not answer.
Future<WslReport?> inspectDistro(String distro) async {
  final result = await _runScript(
    distro,
    _inspectScript,
    timeout: const Duration(seconds: 6),
  );
  if (result == null || result.exitCode != 0) return null;
  return parseWslReport(distro, utf8.decode(result.stdout, allowMalformed: true));
}

/// Ends a process inside [distro]: politely first, then by force. With
/// [startTicks], only if it is still the same process.
Future<KillResult> killWslProcess(String distro, int pid, int? startTicks) async {
  final result = await _runScript(distro, '''
pid=$pid
[ -d /proc/\$pid ] || exit 3
want=${startTicks ?? ''}
if [ -n "\$want" ] && [ "\$(sed 's/.*) //' /proc/\$pid/stat 2>/dev/null | cut -d' ' -f20)" != "\$want" ]; then exit 3; fi
kill -TERM \$pid 2>/dev/null || exit 4
i=0
while [ \$i -lt 15 ]; do
  [ -d /proc/\$pid ] || exit 0
  sleep 0.2
  i=\$((i + 1))
done
kill -KILL \$pid 2>/dev/null
sleep 0.3
[ -d /proc/\$pid ] && exit 4
exit 0
''', timeout: const Duration(seconds: 10));
  return _killResult(result?.exitCode);
}

/// Stops a Docker container through the Docker CLI inside [distro].
Future<KillResult> stopContainer(String distro, String containerId) async {
  // The id is spliced into a shell script, so insist it looks like one.
  if (!RegExp(r'^[0-9a-f]{12,64}$').hasMatch(containerId)) {
    return KillResult.failed;
  }
  final result = await _runScript(distro, '''
docker inspect $containerId >/dev/null 2>&1 || exit 3
timeout 25 docker stop -t 3 $containerId >/dev/null 2>&1 || exit 4
exit 0
''', timeout: const Duration(seconds: 30));
  return _killResult(result?.exitCode);
}

KillResult _killResult(int? exitCode) => switch (exitCode) {
  0 => KillResult.killed,
  3 => KillResult.notFound,
  _ => KillResult.failed,
};

typedef _Output = ({int exitCode, List<int> stdout});

/// Feeds [script] to `sh` on stdin, which sidesteps every quoting rule
/// between Dart, the Windows command line and the Linux shell.
Future<_Output?> _runScript(
  String distro,
  String script, {
  required Duration timeout,
}) => _run(
  'wsl.exe',
  ['-d', distro, '-u', 'root', '-e', 'sh', '-s'],
  stdin: script,
  timeout: timeout,
);

Future<_Output?> _run(
  String executable,
  List<String> arguments, {
  String? stdin,
  required Duration timeout,
}) async {
  final Process process;
  try {
    process = await Process.start(
      executable,
      arguments,
      environment: const {'WSL_UTF8': '1'},
    );
  } on ProcessException {
    return null; // WSL is not installed.
  }

  final output = process.stdout.fold(<int>[], (all, chunk) => all..addAll(chunk));
  unawaited(process.stderr.drain<void>());
  if (stdin != null) process.stdin.add(utf8.encode(stdin));
  // Closing fails if the process has already gone; its exit code says why.
  unawaited(process.stdin.close().then<void>((_) {}, onError: (_) {}));

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
