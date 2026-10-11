import 'dart:io';
import 'dart:isolate';

import '../../models.dart';
import '../port_repository.dart';
import 'win32.dart' as win32;
import 'windows_scan.dart';
import 'wsl.dart' as wsl;

class WindowsPortRepository implements PortRepository {
  /// What we worked out about each live process, so the disk (and WSL) is
  /// only consulted once per process rather than on every poll.
  final _known = <String, _Known>{};

  @override
  bool get isSupported => true;

  @override
  Future<List<PortEntry>> scan({bool includeUdp = false, bool fresh = false}) async {
    if (fresh) _known.clear();
    final scanned = await _scanInBackground(
      ScanRequest(includeUdp: includeUdp, knownProcesses: _known.keys.toSet()),
    );

    final alive = <String>{};
    final entries = <String, PortEntry>{};
    for (final port in scanned) {
      final process = port.process;
      alive.add(process.key);

      var known = _known[process.key];
      if (known == null) {
        known = _Known(
          process.insight ?? _fallbackInsight(process.details),
          process.isBehindRelay ? process.details : null,
        );
        if (process.remember) _known[process.key] = known;
      }

      final entry = PortEntry(
        protocol: port.protocol,
        port: port.port,
        addresses: port.addresses,
        openedAt: port.openedAt,
        process: known.details ?? process.details,
        tech: known.insight.tech,
        project: known.insight.project,
        category: known.insight.category,
      );
      // Two relays can front the same listener (WSL's on ::1 and Docker
      // Desktop's on ::); once traced to one owner they are one row.
      entries.update(
        entry.id,
        (existing) => _merged(existing, entry),
        ifAbsent: () => entry,
      );
    }
    _known.removeWhere((key, _) => !alive.contains(key));
    return entries.values.toList();
  }

  @override
  Future<KillResult> kill(PortEntry entry) async {
    final process = entry.process;
    final distro = process.distro;
    if (distro == null) {
      return _killInBackground(process.pid, process.startStamp);
    }

    final container = process.container;
    final result = container != null
        ? await wsl.stopContainer(distro, container.id)
        : await wsl.killWslProcess(distro, process.pid, process.startStamp);
    // The relay notices a moment after the Linux side lets go. Wait for that,
    // so the port is free on Windows by the time we say it is.
    if (result == KillResult.killed) await _waitUntilClosed(entry.port);
    return result;
  }

  @override
  Future<bool> openFolder(String directory) async {
    if (!await Directory(directory).exists()) return false;
    await Process.start('explorer.exe', [directory], mode: ProcessStartMode.detached);
    return true;
  }

  static Future<void> _waitUntilClosed(int port) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      if (!win32.tcpListeners().any((endpoint) => endpoint.port == port)) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  static PortEntry _merged(PortEntry a, PortEntry b) {
    final earliest = switch ((a.openedAt, b.openedAt)) {
      (final x?, final y?) => x.isBefore(y) ? x : y,
      (final x, final y) => x ?? y,
    };
    return PortEntry(
      protocol: a.protocol,
      port: a.port,
      addresses: {...a.addresses, ...b.addresses}.toList()..sort(),
      openedAt: earliest,
      process: a.process,
      tech: a.tech,
      project: a.project,
      category: a.category,
    );
  }

  // These are static so the closures handed to the isolate capture only their
  // arguments and never drag this object across with them.
  static Future<List<ScannedPort>> _scanInBackground(ScanRequest request) =>
      Isolate.run(() => scanMachine(request));

  static Future<KillResult> _killInBackground(int pid, int? startStamp) =>
      Isolate.run(() => win32.terminateProcess(pid, expectedStartStamp: startStamp));

  static ProcessInsight _fallbackInsight(ProcessDetails details) => ProcessInsight(
    tech: TechInfo(name: details.name),
    category: PortCategory.app,
  );
}

class _Known {
  const _Known(this.insight, this.details);

  final ProcessInsight insight;

  /// Set for a process found behind a relay, which a plain scan cannot see.
  final ProcessDetails? details;
}
