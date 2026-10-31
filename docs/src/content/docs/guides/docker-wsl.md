---
title: Docker & WSL
description: Trace forwarded ports to their actual process or container.
---

Windows attributes every port forwarded from WSL to one process,
`wslrelay.exe`, and Docker Desktop's to `com.docker.backend.exe`. For those
ports the app asks each running WSL distribution what is really listening
(`ss` and `/proc`, as root) and which container publishes what (`docker ps`):

- a process in WSL is shown with its own name, pid, command line and folder
  (as a `\\wsl.localhost\...` path Explorer can open);
- a Docker container is shown by name, with its image and, for Compose, the
  project name and folder. Its card stops the container rather than killing a
  process.

This only happens when a relayed port appears or changes, so ordinary polling
never starts a WSL command. A distribution that is not running is never
started.

On macOS and Linux, Docker is asked directly. A port held by `docker-proxy`
or by Docker Desktop (or, on Linux, by a process of another user's that
cannot be seen) is looked up in `docker ps` and shown as the container
publishing it, under the same rule: only when such a port appears or changes.
