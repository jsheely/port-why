---
title: Development
description: Build, test, and release the Flutter desktop application.
---

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) with
desktop support for the system you are on. Each system builds its own app, on
that system:

```
flutter run                       # development, on whichever system this is
flutter build windows --release   # build\windows\x64\runner\Release\port_why.exe
flutter build macos --release     # build/macos/Build/Products/Release/Port Why.app
flutter build linux --release     # build/linux/x64/release/bundle/port_why
flutter test
```

To try the UI with made-up ports instead of your own (this is how the
screenshots above were taken):

```
flutter run -t tool/demo.dart
```

The app icon is drawn by `tool/make_icon.ps1`, which rewrites the Windows
`.ico`, the macOS asset catalog and the PNGs in `packaging/icons`; edit the
script and re-run it to change the icon. The installers' artwork (the Windows
wizard's sidebar and the .dmg window's background) is drawn from SVGs in
`packaging/` by `packaging/render.ps1`; run it again after either changes.

### Releasing

Pushing a version tag builds every download above and publishes them as the
release of that version:

```
git tag v1.2.0
git push origin v1.2.0
```

The tag sets the version the app is built as, whatever `pubspec.yaml` says.
`.github/workflows/release.yml` builds each system on a GitHub runner of the
same kind, so each processor gets a native build rather than a cross-compiled
one. It runs the tests there first, and checks each binary is for the
processor its file name says. Then the scripts in `packaging/` make each
system's installer: `windows/package.ps1` with Inno Setup, `macos/package.sh`
with dmgbuild, and `linux/package.sh` with nfpm. Linux builds on Ubuntu 22.04
so it runs on Debian 12 and RHEL 9 too. Run the workflow by hand from the
Actions tab to build without releasing: the downloads are attached to that run
instead. To sign and notarize the .dmg, give the repository the `MACOS_*`
secrets that `packaging/macos/package.sh` lists.

## Documentation site

The Astro Starlight site lives in `docs/`. With Node.js 22.23.4 or newer installed:

```sh
cd docs
npm ci
npm run dev
```

Run `npm run build` to check and generate the static site, including search. Run `npm run preview` to inspect the production output. Content lives in `src/content/docs/`; navigation and hosting options live in `astro.config.mjs`.

