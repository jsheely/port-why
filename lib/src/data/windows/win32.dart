/// Thin `dart:ffi` layer over the handful of Win32 calls the scanner needs.
///
/// All struct layouts and offsets below are for 64-bit Windows (x64 / ARM64),
/// the only Windows targets Flutter builds for.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../models.dart';

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _ntdll = DynamicLibrary.open('ntdll.dll');
final _iphlpapi = DynamicLibrary.open('iphlpapi.dll');
final _advapi32 = DynamicLibrary.open('advapi32.dll');
final _version = DynamicLibrary.open('version.dll');

typedef _ExtendedTableNative =
    Uint32 Function(Pointer<Uint8>, Pointer<Uint32>, Int32, Uint32, Int32, Uint32);
typedef _ExtendedTableDart =
    int Function(Pointer<Uint8>, Pointer<Uint32>, int, int, int, int);

final _getExtendedTcpTable = _iphlpapi
    .lookupFunction<_ExtendedTableNative, _ExtendedTableDart>(
      'GetExtendedTcpTable',
    );
final _getExtendedUdpTable = _iphlpapi
    .lookupFunction<_ExtendedTableNative, _ExtendedTableDart>(
      'GetExtendedUdpTable',
    );

final _openProcess = _kernel32
    .lookupFunction<
      IntPtr Function(Uint32, Int32, Uint32),
      int Function(int, int, int)
    >('OpenProcess');
final _closeHandle = _kernel32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
final _readProcessMemory = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, IntPtr, Pointer<Uint8>, IntPtr, Pointer<IntPtr>),
      int Function(int, int, Pointer<Uint8>, int, Pointer<IntPtr>)
    >('ReadProcessMemory');
final _queryFullProcessImageName = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<Utf16>, Pointer<Uint32>),
      int Function(int, int, Pointer<Utf16>, Pointer<Uint32>)
    >('QueryFullProcessImageNameW');
final _getProcessTimes = _kernel32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<Uint64>,
        Pointer<Uint64>,
        Pointer<Uint64>,
        Pointer<Uint64>,
      ),
      int Function(
        int,
        Pointer<Uint64>,
        Pointer<Uint64>,
        Pointer<Uint64>,
        Pointer<Uint64>,
      )
    >('GetProcessTimes');
final _terminateProcess = _kernel32
    .lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>(
      'TerminateProcess',
    );
final _waitForSingleObject = _kernel32
    .lookupFunction<Uint32 Function(IntPtr, Uint32), int Function(int, int)>(
      'WaitForSingleObject',
    );
final _createToolhelp32Snapshot = _kernel32
    .lookupFunction<IntPtr Function(Uint32, Uint32), int Function(int, int)>(
      'CreateToolhelp32Snapshot',
    );
final _process32First = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>),
      int Function(int, Pointer<Uint8>)
    >('Process32FirstW');
final _process32Next = _kernel32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>),
      int Function(int, Pointer<Uint8>)
    >('Process32NextW');

final _ntQueryInformationProcess = _ntdll
    .lookupFunction<
      Int32 Function(IntPtr, Int32, Pointer<Uint8>, Uint32, Pointer<Uint32>),
      int Function(int, int, Pointer<Uint8>, int, Pointer<Uint32>)
    >('NtQueryInformationProcess');

final _openSCManager = _advapi32
    .lookupFunction<
      IntPtr Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
      int Function(Pointer<Utf16>, Pointer<Utf16>, int)
    >('OpenSCManagerW');
final _closeServiceHandle = _advapi32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
      'CloseServiceHandle',
    );
final _enumServicesStatusEx = _advapi32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Int32,
        Uint32,
        Uint32,
        Pointer<Uint8>,
        Uint32,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Utf16>,
      ),
      int Function(
        int,
        int,
        int,
        int,
        Pointer<Uint8>,
        int,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Uint32>,
        Pointer<Utf16>,
      )
    >('EnumServicesStatusExW');

final _getFileVersionInfoSize = _version
    .lookupFunction<
      Uint32 Function(Pointer<Utf16>, Pointer<Uint32>),
      int Function(Pointer<Utf16>, Pointer<Uint32>)
    >('GetFileVersionInfoSizeW');
final _getFileVersionInfo = _version
    .lookupFunction<
      Int32 Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Uint8>),
      int Function(Pointer<Utf16>, int, int, Pointer<Uint8>)
    >('GetFileVersionInfoW');
final _verQueryValue = _version
    .lookupFunction<
      Int32 Function(
        Pointer<Uint8>,
        Pointer<Utf16>,
        Pointer<Pointer<Uint8>>,
        Pointer<Uint32>,
      ),
      int Function(
        Pointer<Uint8>,
        Pointer<Utf16>,
        Pointer<Pointer<Uint8>>,
        Pointer<Uint32>,
      )
    >('VerQueryValueW');

const _errorInsufficientBuffer = 122;
const _afInet = 2;
const _afInet6 = 23;
const _tcpTableOwnerModuleListener = 6;
const _udpTableOwnerModule = 2;

const _processTerminate = 0x0001;
const _processVmRead = 0x0010;
const _processQueryLimitedInformation = 0x1000;
const _synchronize = 0x00100000;

const _processBasicInformation = 0;
const _processWow64Information = 26;
const _processCommandLineInformation = 60;
const _statusInfoLengthMismatch = 0xC0000004 - 0x100000000;

/// 100ns ticks between the FILETIME epoch (1601) and the Unix epoch (1970).
const _fileTimeUnixOffset = 116444736000000000;

DateTime? fileTimeToDateTime(int fileTime) {
  if (fileTime <= 0) return null;
  return DateTime.fromMicrosecondsSinceEpoch(
    (fileTime - _fileTimeUnixOffset) ~/ 10,
    isUtc: true,
  ).toLocal();
}

// ---------------------------------------------------------------------------
// Open ports
// ---------------------------------------------------------------------------

/// One bound local endpoint, straight from the IP helper tables.
class Endpoint {
  const Endpoint({
    required this.protocol,
    required this.address,
    required this.port,
    required this.pid,
    this.createdAt,
  });

  final Protocol protocol;
  final String address;
  final int port;
  final int pid;
  final DateTime? createdAt;
}

/// Byte layout of one row of an `MIB_*TABLE_OWNER_MODULE` table.
class _RowLayout {
  const _RowLayout({
    required this.size,
    required this.address,
    required this.addressLength,
    required this.port,
    required this.pid,
    required this.created,
  });

  final int size;
  final int address;
  final int addressLength;
  final int port;
  final int pid;
  final int created;

  // MIB_TCPROW_OWNER_MODULE
  static const tcp4 = _RowLayout(
    size: 160,
    address: 4,
    addressLength: 4,
    port: 8,
    pid: 20,
    created: 24,
  );
  // MIB_TCP6ROW_OWNER_MODULE
  static const tcp6 = _RowLayout(
    size: 192,
    address: 0,
    addressLength: 16,
    port: 20,
    pid: 52,
    created: 56,
  );
  // MIB_UDPROW_OWNER_MODULE
  static const udp4 = _RowLayout(
    size: 160,
    address: 0,
    addressLength: 4,
    port: 4,
    pid: 8,
    created: 16,
  );
  // MIB_UDP6ROW_OWNER_MODULE
  static const udp6 = _RowLayout(
    size: 176,
    address: 0,
    addressLength: 16,
    port: 20,
    pid: 24,
    created: 32,
  );
}

/// Every listening TCP socket, IPv4 and IPv6.
List<Endpoint> tcpListeners() => [
  ..._readTable(Protocol.tcp, _afInet, _RowLayout.tcp4),
  ..._readTable(Protocol.tcp, _afInet6, _RowLayout.tcp6),
];

/// Every bound UDP socket, IPv4 and IPv6.
List<Endpoint> udpEndpoints() => [
  ..._readTable(Protocol.udp, _afInet, _RowLayout.udp4),
  ..._readTable(Protocol.udp, _afInet6, _RowLayout.udp6),
];

List<Endpoint> _readTable(Protocol protocol, int family, _RowLayout layout) {
  final query = protocol == Protocol.tcp
      ? _getExtendedTcpTable
      : _getExtendedUdpTable;
  final tableClass = protocol == Protocol.tcp
      ? _tcpTableOwnerModuleListener
      : _udpTableOwnerModule;

  return using((arena) {
    final size = arena<Uint32>();
    var status = query(nullptr, size, 0, family, tableClass, 0);
    // The table can grow between the sizing call and the real one, so retry.
    for (var i = 0; i < 4 && status == _errorInsufficientBuffer; i++) {
      final capacity = size.value + 4096;
      final buffer = arena<Uint8>(capacity);
      size.value = capacity;
      status = query(buffer, size, 0, family, tableClass, 0);
      if (status == 0) {
        return _parseTable(buffer.asTypedList(capacity), protocol, layout);
      }
    }
    return const [];
  });
}

List<Endpoint> _parseTable(Uint8List bytes, Protocol protocol, _RowLayout layout) {
  final data = ByteData.sublistView(bytes);
  final count = data.getUint32(0, Endian.little);
  final rows = <Endpoint>[];
  // The row array is 8-byte aligned (rows contain a LARGE_INTEGER), so it
  // starts at offset 8, after dwNumEntries and padding.
  for (var i = 0; i < count; i++) {
    final row = 8 + i * layout.size;
    if (row + layout.size > bytes.length) break;
    final address = InternetAddress.fromRawAddress(
      Uint8List.sublistView(
        bytes,
        row + layout.address,
        row + layout.address + layout.addressLength,
      ),
    );
    rows.add(
      Endpoint(
        protocol: protocol,
        address: address.address,
        // The port sits in the low 16 bits in network byte order.
        port: data.getUint16(row + layout.port, Endian.big),
        pid: data.getUint32(row + layout.pid, Endian.little),
        createdAt: fileTimeToDateTime(
          data.getInt64(row + layout.created, Endian.little),
        ),
      ),
    );
  }
  return rows;
}

// ---------------------------------------------------------------------------
// Processes
// ---------------------------------------------------------------------------

/// Parent pid and image name for one process, from a Toolhelp snapshot.
typedef ProcessSummary = ({int parentPid, String name});

/// A snapshot of every process on the machine, keyed by pid. This works for
/// processes we are not allowed to open.
Map<int, ProcessSummary> snapshotProcesses() {
  const th32csSnapProcess = 0x2;
  const entrySize = 568; // sizeof(PROCESSENTRY32W)
  const invalidHandle = -1;

  final snapshot = _createToolhelp32Snapshot(th32csSnapProcess, 0);
  if (snapshot == invalidHandle || snapshot == 0) return const {};

  return using((arena) {
    final entry = arena<Uint8>(entrySize);
    final view = ByteData.sublistView(entry.asTypedList(entrySize));
    view.setUint32(0, entrySize, Endian.little); // dwSize
    final result = <int, ProcessSummary>{};
    try {
      var more = _process32First(snapshot, entry);
      while (more != 0) {
        result[view.getUint32(8, Endian.little)] = (
          parentPid: view.getUint32(32, Endian.little),
          name: (entry + 44).cast<Utf16>().toDartString(),
        );
        more = _process32Next(snapshot, entry);
      }
    } finally {
      _closeHandle(snapshot);
    }
    return result;
  });
}

/// What could be read directly out of one process.
class ProcessProbe {
  const ProcessProbe({
    this.exePath,
    this.commandLine,
    this.cwd,
    this.startStamp,
    this.restricted = false,
  });

  final String? exePath;
  final String? commandLine;
  final String? cwd;
  final int? startStamp;
  final bool restricted;

  static const denied = ProcessProbe(restricted: true);
}

/// Reads the image path, command line, working directory and start time of
/// [pid]. Fields the OS will not give us are left null.
ProcessProbe probeProcess(int pid) {
  // The working directory lives in the target's memory, which needs VM_READ.
  // Fall back to the limited right, which still yields path and command line.
  var canReadMemory = true;
  var handle = _openProcess(
    _processQueryLimitedInformation | _processVmRead,
    0,
    pid,
  );
  if (handle == 0) {
    canReadMemory = false;
    handle = _openProcess(_processQueryLimitedInformation, 0, pid);
  }
  if (handle == 0) return ProcessProbe.denied;

  try {
    return ProcessProbe(
      exePath: _imagePath(handle),
      commandLine: _commandLine(handle),
      cwd: canReadMemory ? _workingDirectory(handle) : null,
      startStamp: _creationTime(handle),
      restricted: !canReadMemory,
    );
  } finally {
    _closeHandle(handle);
  }
}

String? _imagePath(int handle) => using((arena) {
  const capacity = 32768;
  final buffer = arena<Uint16>(capacity).cast<Utf16>();
  final length = arena<Uint32>()..value = capacity;
  if (_queryFullProcessImageName(handle, 0, buffer, length) == 0) return null;
  return buffer.toDartString(length: length.value);
});

int? _creationTime(int handle) => using((arena) {
  final times = arena<Uint64>(4);
  if (_getProcessTimes(handle, times, times + 1, times + 2, times + 3) == 0) {
    return null;
  }
  return times.value;
});

String? _commandLine(int handle) => using((arena) {
  final returned = arena<Uint32>();
  var capacity = 4096;
  for (var i = 0; i < 2; i++) {
    final buffer = arena<Uint8>(capacity);
    final status = _ntQueryInformationProcess(
      handle,
      _processCommandLineInformation,
      buffer,
      capacity,
      returned,
    );
    if (status == _statusInfoLengthMismatch && returned.value > capacity) {
      capacity = returned.value;
      continue;
    }
    if (status < 0) return null;
    // The buffer holds a UNICODE_STRING whose Buffer points further into it.
    final length = buffer.cast<Uint16>().value;
    final text = (buffer + 8).cast<Pointer<Utf16>>().value;
    if (text == nullptr) return null;
    return text.toDartString(length: length ~/ 2).trim();
  }
  return null;
});

/// Reads `PEB->ProcessParameters->CurrentDirectory.DosPath` from the target.
String? _workingDirectory(int handle) => using((arena) {
  final info = arena<Uint8>(48);

  // A 32-bit process on 64-bit Windows keeps its live parameters in a second,
  // 32-bit PEB with narrower pointers.
  var status = _ntQueryInformationProcess(
    handle,
    _processWow64Information,
    info,
    8,
    nullptr,
  );
  final peb32 = status >= 0 ? info.cast<IntPtr>().value : 0;
  if (peb32 != 0) {
    final parameters = _readUint(handle, peb32 + 0x10, 4);
    if (parameters == null) return null;
    final header = _readMemory(handle, parameters + 0x24, 8);
    if (header == null) return null;
    final view = ByteData.sublistView(header);
    return _readUtf16(
      handle,
      view.getUint32(4, Endian.little),
      view.getUint16(0, Endian.little),
    );
  }

  status = _ntQueryInformationProcess(
    handle,
    _processBasicInformation,
    info,
    48,
    nullptr,
  );
  if (status < 0) return null;
  final peb = (info + 8).cast<IntPtr>().value;
  final parameters = _readUint(handle, peb + 0x20, 8);
  if (parameters == null) return null;
  final header = _readMemory(handle, parameters + 0x38, 16);
  if (header == null) return null;
  final view = ByteData.sublistView(header);
  return _readUtf16(
    handle,
    view.getInt64(8, Endian.little),
    view.getUint16(0, Endian.little),
  );
});

Uint8List? _readMemory(int handle, int address, int length) {
  if (address == 0 || length <= 0) return null;
  return using((arena) {
    final buffer = arena<Uint8>(length);
    final read = arena<IntPtr>();
    if (_readProcessMemory(handle, address, buffer, length, read) == 0 ||
        read.value != length) {
      return null;
    }
    return Uint8List.fromList(buffer.asTypedList(length));
  });
}

int? _readUint(int handle, int address, int width) {
  final bytes = _readMemory(handle, address, width);
  if (bytes == null) return null;
  final view = ByteData.sublistView(bytes);
  final value = width == 4
      ? view.getUint32(0, Endian.little)
      : view.getInt64(0, Endian.little);
  return value == 0 ? null : value;
}

String? _readUtf16(int handle, int address, int byteLength) {
  if (byteLength <= 0 || byteLength.isOdd) return null;
  final bytes = _readMemory(handle, address, byteLength);
  if (bytes == null) return null;
  return String.fromCharCodes(bytes.buffer.asUint16List(0, byteLength ~/ 2));
}

// ---------------------------------------------------------------------------
// Services and file metadata
// ---------------------------------------------------------------------------

/// Display names of the running Windows services, grouped by host process.
Map<int, List<String>> servicesByPid() {
  const scManagerEnumerateService = 0x0004;
  const scEnumProcessInfo = 0;
  const serviceWin32 = 0x30;
  const serviceActive = 1;
  const entrySize = 56; // sizeof(ENUM_SERVICE_STATUS_PROCESSW)

  final manager = _openSCManager(nullptr, nullptr, scManagerEnumerateService);
  if (manager == 0) return const {};

  return using((arena) {
    try {
      final needed = arena<Uint32>();
      final count = arena<Uint32>();
      final resume = arena<Uint32>();
      _enumServicesStatusEx(
        manager,
        scEnumProcessInfo,
        serviceWin32,
        serviceActive,
        nullptr,
        0,
        needed,
        count,
        resume,
        nullptr,
      );
      if (needed.value == 0) return const {};

      final capacity = needed.value + 8192;
      final buffer = arena<Uint8>(capacity);
      resume.value = 0;
      final ok = _enumServicesStatusEx(
        manager,
        scEnumProcessInfo,
        serviceWin32,
        serviceActive,
        buffer,
        capacity,
        needed,
        count,
        resume,
        nullptr,
      );
      if (ok == 0) return const {};

      final result = <int, List<String>>{};
      for (var i = 0; i < count.value; i++) {
        final entry = buffer + i * entrySize;
        final displayName = (entry + 8).cast<Pointer<Utf16>>().value;
        // dwProcessId is the eighth DWORD of the embedded
        // SERVICE_STATUS_PROCESS, which follows the two name pointers.
        final pid = (entry + 16 + 28).cast<Uint32>().value;
        if (pid == 0 || displayName == nullptr) continue;
        result.putIfAbsent(pid, () => []).add(displayName.toDartString());
      }
      return result;
    } finally {
      _closeServiceHandle(manager);
    }
  });
}

/// The `FileDescription` from an executable's version resource, e.g.
/// "Node.js JavaScript Runtime".
String? fileDescription(String path) => using((arena) {
  final pathPtr = path.toNativeUtf16(allocator: arena);
  final size = _getFileVersionInfoSize(pathPtr, arena<Uint32>());
  if (size == 0) return null;
  final block = arena<Uint8>(size);
  if (_getFileVersionInfo(pathPtr, 0, size, block) == 0) return null;

  final value = arena<Pointer<Uint8>>();
  final length = arena<Uint32>();
  bool query(String subBlock) =>
      _verQueryValue(
            block,
            subBlock.toNativeUtf16(allocator: arena),
            value,
            length,
          ) !=
          0 &&
      length.value > 0;

  String hex(int word) => word.toRadixString(16).padLeft(4, '0');
  final translations = <String>[];
  if (query(r'\VarFileInfo\Translation')) {
    final words = value.value.cast<Uint16>();
    for (var i = 0; i + 1 < length.value ~/ 2; i += 2) {
      translations.add('${hex(words[i])}${hex(words[i + 1])}');
    }
  }
  translations.addAll(const ['040904b0', '040904e4', '04090000']);

  for (final translation in translations) {
    if (query('\\StringFileInfo\\$translation\\FileDescription')) {
      final text = value.value.cast<Utf16>().toDartString().trim();
      if (text.isNotEmpty) return text;
    }
  }
  return null;
});

// ---------------------------------------------------------------------------
// Killing
// ---------------------------------------------------------------------------

/// Terminates [pid] and waits briefly for it to exit so its ports are released
/// by the time this returns.
///
/// When [expectedStartStamp] is given, the process is only killed if it is
/// still the same instance, so a recycled pid is never hit by mistake.
KillResult terminateProcess(int pid, {int? expectedStartStamp}) {
  final handle = _openProcess(
    _processTerminate | _processQueryLimitedInformation | _synchronize,
    0,
    pid,
  );
  if (handle == 0) {
    return snapshotProcesses().containsKey(pid)
        ? KillResult.accessDenied
        : KillResult.notFound;
  }
  try {
    if (expectedStartStamp != null &&
        _creationTime(handle) != expectedStartStamp) {
      return KillResult.notFound;
    }
    // A process that has exited stays openable for as long as anyone (usually
    // its parent) still holds a handle to it. Terminating it then fails, but
    // the truthful answer is that it was already gone.
    if (_hasExited(handle)) return KillResult.notFound;
    if (_terminateProcess(handle, 1) == 0) {
      return _hasExited(handle) ? KillResult.notFound : KillResult.failed;
    }
    _waitForSingleObject(handle, 3000);
    return KillResult.killed;
  } finally {
    _closeHandle(handle);
  }
}

/// A process handle becomes signalled the moment the process exits.
bool _hasExited(int handle) => _waitForSingleObject(handle, 0) == 0;
