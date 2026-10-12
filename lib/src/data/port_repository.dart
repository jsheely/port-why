import '../models.dart';
import 'posix/posix_port_repository.dart';
import 'windows/windows_port_repository.dart';

/// Where the UI gets its ports from, and how it acts on them.
abstract interface class PortRepository {
  /// False on platforms with no scanner.
  bool get isSupported;

  /// The operating system the ports belong to, which decides how the UI
  /// words what it cannot see or will not kill.
  HostOs get os;

  /// Every open port right now. With [fresh], anything remembered about
  /// processes from earlier scans is thrown away and worked out again.
  Future<List<PortEntry>> scan({bool includeUdp = false, bool fresh = false});

  /// Kills the process that owns [entry].
  Future<KillResult> kill(PortEntry entry);

  /// Opens [directory] in the system file manager. False if it is gone.
  Future<bool> openFolder(String directory);
}

PortRepository createPortRepository() => switch (HostOs.current) {
  HostOs.windows => WindowsPortRepository(),
  final os? => PosixPortRepository(os),
  null => const UnsupportedPortRepository(),
};

class UnsupportedPortRepository implements PortRepository {
  const UnsupportedPortRepository();

  @override
  bool get isSupported => false;

  @override
  HostOs get os => HostOs.linux;

  @override
  Future<List<PortEntry>> scan({bool includeUdp = false, bool fresh = false}) async =>
      const [];

  @override
  Future<KillResult> kill(PortEntry entry) async => KillResult.failed;

  @override
  Future<bool> openFolder(String directory) async => false;
}
