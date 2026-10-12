import '../models.dart';
import 'port_repository.dart';
import 'scan.dart';

/// The half of a repository every operating system shares: turning what a
/// scan found into rows, and remembering what was worked out about each
/// process between scans.
abstract class ScanningPortRepository implements PortRepository {
  /// What we worked out about each live process, so the disk (and whatever
  /// else the scanner has to ask) is only consulted once per process rather
  /// than on every poll.
  final _known = <String, _Known>{};

  @override
  bool get isSupported => true;

  /// One pass over the machine, off the UI isolate.
  Future<List<ScannedPort>> scanPorts(ScanRequest request);

  @override
  Future<List<PortEntry>> scan({bool includeUdp = false, bool fresh = false}) async {
    if (fresh) _known.clear();
    final scanned = await scanPorts(
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
          process.keepDetails ? process.details : null,
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

  static ProcessInsight _fallbackInsight(ProcessDetails details) => ProcessInsight(
    tech: TechInfo(name: details.name),
    category: PortCategory.app,
  );
}

class _Known {
  const _Known(this.insight, this.details);

  final ProcessInsight insight;

  /// Set for a process whose details the scanner will not send again.
  final ProcessDetails? details;
}
