import 'dart:io';
import 'dart:isolate';

import '../../models.dart';
import '../scan.dart';
import '../scanning_port_repository.dart';
import 'win32.dart' as win32;
import 'windows_scan.dart';
import 'wsl.dart' as wsl;

class WindowsPortRepository extends ScanningPortRepository {
  @override
  HostOs get os => HostOs.windows;

  // Static, here and below, so the closures handed to the isolate capture
  // only their arguments and never drag this object across with them.
  @override
  Future<List<ScannedPort>> scanPorts(ScanRequest request) =>
      _scanInBackground(request);

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

  static Future<List<ScannedPort>> _scanInBackground(ScanRequest request) =>
      Isolate.run(() => scanMachine(request));

  static Future<KillResult> _killInBackground(int pid, int? startStamp) =>
      Isolate.run(() => win32.terminateProcess(pid, expectedStartStamp: startStamp));
}
