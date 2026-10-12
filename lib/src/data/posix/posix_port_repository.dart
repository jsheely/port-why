import 'dart:io';
import 'dart:isolate';

import '../../models.dart';
import '../docker.dart' as docker;
import '../scan.dart';
import '../scanning_port_repository.dart';
import 'posix_scan.dart';

/// Ports on macOS and Linux.
class PosixPortRepository extends ScanningPortRepository {
  PosixPortRepository(this.os);

  @override
  final HostOs os;

  @override
  Future<List<ScannedPort>> scanPorts(ScanRequest request) =>
      _scanInBackground(request, os);

  @override
  Future<KillResult> kill(PortEntry entry) {
    final process = entry.process;
    final container = process.container;
    if (container != null) return docker.stopContainer(container.id);
    // Nothing to aim at: the process is one we cannot see.
    if (process.pid <= 0) return Future.value(KillResult.accessDenied);
    return terminateProcess(process.pid, os, expectedStartStamp: process.startStamp);
  }

  @override
  Future<bool> openFolder(String directory) async {
    if (!await Directory(directory).exists()) return false;
    try {
      await Process.start(os == HostOs.macos ? '/usr/bin/open' : 'xdg-open', [
        directory,
      ], mode: ProcessStartMode.detached);
    } on ProcessException {
      // No file manager to hand it to.
      return false;
    }
    return true;
  }

  // Static so the closure handed to the isolate captures only its arguments
  // and never drags this object across with it.
  static Future<List<ScannedPort>> _scanInBackground(ScanRequest request, HostOs os) =>
      Isolate.run(() => scanPosix(request, os));
}
