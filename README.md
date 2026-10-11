# Port Why

A Windows desktop app (Flutter) that lists every open port on your machine and
answers "what is holding that open?": the process, the framework or runtime
behind it, the project it belongs to, and the folder it is running in.

- Ports are listed highest first; click any column header to sort by it.
- Filter by typing (port, project, process, folder, command line; every word
  must match), by scope (Projects / Apps / System), and optionally include UDP.
- Each row can open its folder in Explorer or kill the owning process.
- Click a row for the full command line, executable, parent process and bind
  addresses.

## Run

```
flutter run -d windows            # development
flutter build windows --release   # build\windows\x64\runner\Release\port_why.exe
flutter test
```

Shortcuts: `Ctrl+F` filter, `Esc` clear the filter, `F5` rescan from scratch.

## How it works

Everything is read in-process through `dart:ffi` (no `netstat` or PowerShell
subprocesses), on a background isolate, every two seconds.

| What | Where it comes from |
| --- | --- |
| Ports, owning pid, bind time | `GetExtendedTcpTable` / `GetExtendedUdpTable` |
| Executable, command line, start time | `QueryFullProcessImageName`, `NtQueryInformationProcess` |
| Working folder | the target process's PEB (`ReadProcessMemory`) |
| Service names | the service control manager |
| Project name | nearest manifest above the working folder: `package.json`, `pubspec.yaml`, `*.csproj`, `Cargo.toml`, `pyproject.toml`, `go.mod`, `pom.xml`, ... |
| "Opened by" | runtime from the executable, tool from the command line, framework from the project's dependencies |

So a Vue app served by Vite shows as **Vue** (via Vite, on Node.js), and
`python -m uvicorn` in a project that requires FastAPI shows as **FastAPI**.
The rules live in `lib/src/detect/tech_detector.dart`; the icon for each one in
`lib/src/ui/tech_icon.dart`.

### WSL and Docker

Windows attributes every port forwarded from WSL to one process,
`wslrelay.exe`, and Docker Desktop's to `com.docker.backend.exe`. For those
ports the app asks each running WSL distribution what is really listening
(`ss` and `/proc`, as root) and which container publishes what (`docker ps`):

- a process in WSL is shown with its own name, pid, command line and folder
  (as a `\\wsl.localhost\...` path Explorer can open);
- a Docker container is shown by name, with its image and, for Compose, the
  project name and folder. Its row stops the container rather than killing a
  process.

This only happens when a relayed port appears or changes, so ordinary polling
never starts a WSL command. A distribution that is not running is never
started.

## Limits

- Windows only. The scanner sits behind `PortRepository`, so another platform
  needs its own implementation of that interface.
- Without administrator rights, Windows hides the folder and command line of
  system and other users' processes, and refuses to kill them. Those rows say
  so; run Port Why as administrator to see and act on them.
- Project and framework names are inferred, so they can be wrong for unusual
  setups. The expanded row shows the evidence (command line and folder).
- Tracing into WSL needs `ss` in the distribution (and `docker` for
  containers). Docker Desktop containers are only named when a running
  distribution has Docker's WSL integration enabled; otherwise their ports
  still show as Docker Desktop. A relayed port nothing can be found behind
  stays labelled WSL and cannot be killed from here, since killing the relay
  would cut off every WSL port.
