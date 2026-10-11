import 'dart:io';

import '../models.dart';
import 'windows/windows_port_repository.dart';

/// Where the UI gets its ports from, and how it acts on them.
abstract interface class PortRepository {
  /// False on platforms with no scanner yet.
  bool get isSupported;

  /// Every open port right now. With [fresh], anything remembered about
  /// processes from earlier scans is thrown away and worked out again.
  Future<List<PortEntry>> scan({bool includeUdp = false, bool fresh = false});

  /// Kills the process that owns [entry].
  Future<KillResult> kill(PortEntry entry);

  /// Opens [directory] in the system file manager. False if it is gone.
  Future<bool> openFolder(String directory);
}

PortRepository createPortRepository() => Platform.isWindows
    ? WindowsPortRepository()
    : const UnsupportedPortRepository();

class UnsupportedPortRepository implements PortRepository {
  const UnsupportedPortRepository();

  @override
  bool get isSupported => false;

  @override
  Future<List<PortEntry>> scan({bool includeUdp = false, bool fresh = false}) async =>
      const [];

  @override
  Future<KillResult> kill(PortEntry entry) async => KillResult.failed;

  @override
  Future<bool> openFolder(String directory) async => false;
}
