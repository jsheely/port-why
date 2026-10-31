---
title: Troubleshooting
description: Understand permissions, missing process details, and detection limits.
---

- Without administrator rights, Windows hides the folder and command line of
  system and other users' processes, and refuses to kill them. Those cards say
  so; run Port Why as administrator to see and act on them.
- Linux shows every port to everyone but only tells root which process holds
  one of another user's, so those cards name the owning user and nothing more.
  macOS does not show them at all: without root, only your own processes'
  ports are listed. Run Port Why as root to see the rest.
- macOS and Linux do not record when a port was opened, so cards there show no
  age and sorting by "Opened" has nothing to go on: the list falls back to
  port number, lowest first.
- Only on Windows does the app draw its own title bar. macOS and Linux keep
  the system's, and fall back to their own fonts for the two Windows faces the
  design is drawn in.
- Project and framework names are inferred, so they can be wrong for unusual
  setups. A card's details show the evidence (command line and folder).
- Tracing into WSL needs `ss` in the distribution (and `docker` for
  containers). Docker Desktop containers are only named when a running
  distribution has Docker's WSL integration enabled; otherwise their ports
  still show as Docker Desktop. A relayed port nothing can be found behind
  stays labelled WSL and cannot be killed from here, since killing the relay
  would cut off every WSL port.
