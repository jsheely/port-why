/// What a scan hands back, whichever operating system did the scanning.
library;

import '../models.dart';

/// What the scan should cover. Sent to the scanning isolate.
class ScanRequest {
  const ScanRequest({this.includeUdp = false, this.knownProcesses = const {}});

  final bool includeUdp;

  /// Keys of processes the caller already holds an insight for. Working out a
  /// project and framework touches the disk, so it is done once per process
  /// rather than on every poll.
  final Set<String> knownProcesses;
}

/// The inferred, cacheable half of a row.
class ProcessInsight {
  const ProcessInsight({required this.tech, required this.category, this.project});

  final TechInfo tech;
  final ProjectInfo? project;
  final PortCategory category;
}

class ScannedProcess {
  const ScannedProcess({
    required this.key,
    required this.details,
    this.insight,
    this.keepDetails = false,
    this.remember = true,
  });

  /// Identifies this process instance in this working directory, or, for a
  /// port held by a relay, the forwarding socket.
  final String key;
  final ProcessDetails details;

  /// Null when the caller said it already knows this key.
  final ProcessInsight? insight;

  /// True when [details] cost something to find: what is behind a relay (a
  /// process in WSL, a container) takes a round trip to learn, and on macOS
  /// so does any process's folder and command line. The caller keeps such
  /// details along with the insight instead of expecting them on every scan.
  final bool keepDetails;

  /// False when the lookup could not be completed and should be tried again.
  final bool remember;
}

class ScannedPort {
  const ScannedPort({
    required this.protocol,
    required this.port,
    required this.addresses,
    required this.process,
    this.openedAt,
  });

  final Protocol protocol;
  final int port;
  final List<String> addresses;
  final DateTime? openedAt;
  final ScannedProcess process;

  ScannedPort withProcess(ScannedProcess process) => ScannedPort(
    protocol: protocol,
    port: port,
    addresses: addresses,
    openedAt: openedAt,
    process: process,
  );
}

/// IPv4 before IPv6, then in order.
List<String> sortedAddresses(Iterable<String> bound) {
  final addresses = bound.toSet().toList();
  int rank(String address) => address.contains(':') ? 1 : 0;
  addresses.sort((a, b) {
    final byFamily = rank(a).compareTo(rank(b));
    return byFamily != 0 ? byFamily : a.compareTo(b);
  });
  return addresses;
}

/// [tech] with [icon] standing in when it has none of its own.
TechInfo withFallbackIcon(TechInfo tech, String icon) => tech.icon != null
    ? tech
    : TechInfo(name: tech.name, via: tech.via, runtime: tech.runtime, icon: icon);
