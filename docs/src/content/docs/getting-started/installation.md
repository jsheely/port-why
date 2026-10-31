---
title: Installation
description: Install Port Why on Windows, macOS, or Linux.
---

Each [release](https://github.com/jsheely/port-why/releases) has an installer
and an archive for every system and processor (`<arch>` is `x64` for Intel or
AMD, `arm64` for Arm):

| System | Installer | Archive |
| --- | --- | --- |
| Windows | `port-why-<version>-windows-<arch>-setup.exe` | `port-why-<version>-windows-<arch>.zip` |
| macOS, Apple silicon and Intel | `port-why-<version>-macos-universal.dmg` | `port-why-<version>-macos-universal.zip` |
| Debian, Ubuntu | `port-why-<version>-linux-<arch>.deb` | `port-why-<version>-linux-<arch>.tar.gz` |
| Fedora, RHEL, openSUSE | `port-why-<version>-linux-<arch>.rpm` | |
| Arch Linux | `port-why-<version>-linux-<arch>.pkg.tar.zst` | |

- **Windows**: the installer puts Port Why in your user profile without
  asking for administrator rights (an administrator can choose to install it
  for everyone), adds it to the Start menu, and uninstalls from Settings >
  Apps.
- **macOS**: open the .dmg and drag Port Why to Applications.
- **Linux**: install the package with `sudo apt install ./<file>.deb`,
  `sudo dnf install ./<file>.rpm` or `sudo pacman -U <file>.pkg.tar.zst`. Or,
  without root, install the tarball into `~/.local` with the install script
  (`--uninstall` removes it again; `PORTWHY_PREFIX=/usr/local` with `sudo`
  installs it for everyone):

  ```
  curl -fsSL https://github.com/jsheely/port-why/releases/latest/download/install.sh | sh
  ```

  It needs GTK 3, EGL and OpenGL ES, and glibc 2.34: Ubuntu 22.04, Debian 12,
  Fedora 35, RHEL 9 or anything newer. The packages pull those in.

The builds are not signed, so the first time you open one, Windows
SmartScreen asks first (choose **More info**, then **Run anyway**), and macOS
refuses until you choose **Open Anyway** in System Settings > Privacy &
Security, or run `xattr -dr com.apple.quarantine "/Applications/Port Why.app"`.
Favorites are kept when you uninstall.
