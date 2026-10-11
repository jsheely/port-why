import 'dart:io';
import 'dart:isolate';

import '../../models.dart';
import '../port_repository.dart';
import 'win32.dart' as win32;
import 'windows_scan.dart';

class WindowsPortRepository implements PortRepository {
  /// What we worked out about each live process, so the disk is only read
  /// once per process rather than on every poll.
  final _insights = <String, ProcessInsight>{};

  @override
  bool get isSupported => true;

  @override
  Future<List<PortEntry>> scan({bool includeUdp = false, bool fresh = false}) async {
    if (fresh) _insights.clear();
    final scanned = await _scanInBackground(
      ScanRequest(
        includeUdp: includeUdp,
        knownProcesses: _insights.keys.toSet(),
      ),
    );

    final alive = <String>{};
    final entries = <PortEntry>[];
    for (final port in scanned) {
      final process = port.process;
      alive.add(process.key);
      final insight = _insights[process.key] ??=
          process.insight ?? _fallbackInsight(process.details);
      entries.add(
        PortEntry(
          protocol: port.protocol,
          port: port.port,
          addresses: port.addresses,
          openedAt: port.openedAt,
          process: process.details,
          tech: insight.tech,
          project: insight.project,
          category: insight.category,
        ),
      );
    }
    _insights.removeWhere((key, _) => !alive.contains(key));
    return entries;
  }

  @override
  Future<KillResult> kill(PortEntry entry) =>
      _killInBackground(entry.process.pid, entry.process.startStamp);

  @override
  Future<bool> openFolder(String directory) async {
    if (!await Directory(directory).exists()) return false;
    await Process.start('explorer.exe', [directory], mode: ProcessStartMode.detached);
    return true;
  }

  // These are static so the closures handed to the isolate capture only their
  // arguments and never drag this object across with them.
  static Future<List<ScannedPort>> _scanInBackground(ScanRequest request) =>
      Isolate.run(() => scanWindows(request));

  static Future<KillResult> _killInBackground(int pid, int? startStamp) =>
      Isolate.run(() => win32.terminateProcess(pid, expectedStartStamp: startStamp));

  static ProcessInsight _fallbackInsight(ProcessDetails details) => ProcessInsight(
    tech: TechInfo(name: details.name),
    category: PortCategory.app,
  );
}
