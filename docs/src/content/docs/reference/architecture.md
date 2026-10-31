---
title: How scanning works
description: Native port scanning and shared framework detection.
---

The machine is read on a background isolate, every two seconds. How depends on
the system.

**Windows**, in-process through `dart:ffi` (no `netstat` or PowerShell
subprocesses):

| What | Where it comes from |
| --- | --- |
| Ports, owning pid, bind time | `GetExtendedTcpTable` / `GetExtendedUdpTable` |
| Executable, command line, start time | `QueryFullProcessImageName`, `NtQueryInformationProcess` |
| Working folder | the target process's PEB (`ReadProcessMemory`) |
| Service names | the service control manager |

**Linux**, straight out of `/proc`, again with no subprocesses:

| What | Where it comes from |
| --- | --- |
| Ports, owning user | `/proc/net/tcp`, `tcp6`, `udp`, `udp6` |
| Owning pid | whichever process's `/proc/<pid>/fd` holds the socket |
| Executable, command line, working folder, start time | `/proc/<pid>/exe`, `cmdline`, `cwd`, `stat` |

**macOS**, which has no `/proc`, by running the tools it ships with:

| What | Where it comes from |
| --- | --- |
| Ports, owning pid | `lsof -iTCP -sTCP:LISTEN` (and `-iUDP`) |
| Executable, start time, parent | `ps` |
| Command line, working folder | `ps` and `lsof -d cwd`, once per process rather than on every poll |

Everywhere, what the process *is* comes from the same two detectors:

| What | Where it comes from |
| --- | --- |
| Project name | nearest manifest above the working folder: `package.json`, `pubspec.yaml`, `*.csproj`, `Cargo.toml`, `pyproject.toml`, `go.mod`, `pom.xml`, ... |
| "Opened by" | runtime from the executable, tool from the command line, framework from the project's dependencies |

So a Vue app served by Vite shows as **Vue** (via Vite, on Node.js), and
`python -m uvicorn` in a project that requires FastAPI shows as **FastAPI**.
The rules live in `lib/src/detect/tech_detector.dart`; the icon for each one in
`lib/src/ui/tech_icon.dart`.

## Source layout

| Path | Holds |
| --- | --- |
| `lib/src/data/` | `PortRepository`, what every scanner shares, and Docker |
| `lib/src/data/windows/` | The Windows scanner (Win32 via FFI, WSL) |
| `lib/src/data/posix/` | The macOS and Linux scanners (`lsof` and `ps`, `/proc`) |
| `lib/src/detect/` | Project and framework detection |
| `lib/src/state/` | Polling, filtering, sorting and favorites |
| `lib/src/ui/` | The cards, control panel, title bar and theme |
| `windows/`, `macos/`, `linux/` | Each system's runner: the window the app lives in |
| `tool/` | The demo entry point and the icon script |
| `packaging/` | The installers: Inno Setup on Windows, the .dmg on macOS, the Linux packages, and their artwork |
| `install.sh` | The Linux install script, published with each release |
| `.github/workflows/` | The release build |
