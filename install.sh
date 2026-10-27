#!/bin/sh
# Installs Port Why from its GitHub releases on Linux (x64, arm64):
#
#   curl -fsSL https://github.com/jsheely/port-why/releases/latest/download/install.sh | sh
#
# It unpacks the release's port-why-<version>-linux-<arch>.tar.gz into a
# prefix: the app in lib/port-why/, a port-why link to it in bin/,
# net.thirtytech.port_why.desktop in share/applications/, the icons in
# share/icons/hicolor/ and the README in share/doc/port-why/. To remove them
# again:
#
#   curl -fsSL https://github.com/jsheely/port-why/releases/latest/download/install.sh | sh -s -- --uninstall
#
# Environment:
#   PORTWHY_VERSION  tag to install, such as v1.2.0 (default: latest release)
#   PORTWHY_PREFIX   where to install (default: ~/.local). For every user, use
#                    /usr/local and run the script with sudo.

set -eu

repo="jsheely/port-why"
prefix="${PORTWHY_PREFIX:-$HOME/.local}"
uninstall=0

err() {
    echo "port-why install: $*" >&2
    exit 1
}

for arg in "$@"; do
    case "$arg" in
        --uninstall) uninstall=1 ;;
        *) err "unknown option: $arg (the only one is --uninstall)" ;;
    esac
done

# The files a release's tarball installs besides lib/port-why, relative to
# the prefix.
sizes="16 32 48 64 128 256 512"
files() {
    echo bin/port-why
    echo share/applications/net.thirtytech.port_why.desktop
    for size in $sizes; do
        echo "share/icons/hicolor/${size}x${size}/apps/port-why.png"
    done
}

# Tells the desktop about new or removed launchers and icons. Desktops that
# watch these folders don't need it; the tools may not be installed.
refresh() {
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database -q "$prefix/share/applications" 2>/dev/null || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1 && [ -f "$prefix/share/icons/hicolor/index.theme" ]; then
        gtk-update-icon-cache -q -t "$prefix/share/icons/hicolor" 2>/dev/null || true
    fi
}

[ "$(uname -s)" = Linux ] || err "this script is for Linux. On macOS, open the .dmg; on Windows, run the -setup.exe; both are at https://github.com/$repo/releases"

if [ "$uninstall" = 1 ]; then
    removed=0
    for f in $(files); do
        if [ -e "$prefix/$f" ] || [ -L "$prefix/$f" ]; then
            rm -f "$prefix/$f"
            removed=1
        fi
    done
    if [ -d "$prefix/lib/port-why" ]; then
        rm -rf "$prefix/lib/port-why"
        removed=1
    fi
    rm -rf "$prefix/share/doc/port-why"
    [ "$removed" = 1 ] || err "Port Why isn't installed in $prefix"
    refresh
    echo "Removed Port Why from $prefix. Favorites in ~/.config/Port Why are kept."
    exit 0
fi

command -v curl >/dev/null 2>&1 || err "curl is required"
command -v tar >/dev/null 2>&1 || err "tar is required"
command -v sha256sum >/dev/null 2>&1 || err "sha256sum is required"

case "$(uname -m)" in
    x86_64 | amd64) arch=x64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) err "unsupported architecture: $(uname -m)" ;;
esac

if [ -n "${PORTWHY_VERSION:-}" ]; then
    tag="$PORTWHY_VERSION"
else
    # /releases/latest redirects to /releases/tag/<tag>.
    tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest")
    tag="${tag##*/}"
    [ -n "$tag" ] && [ "$tag" != latest ] || err "couldn't find the latest release"
fi

# The downloads are named after the version, without the tag's v.
name="port-why-${tag#v}-linux-$arch"
base="https://github.com/$repo/releases/download/$tag"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading Port Why $tag (linux-$arch)"
curl -fsSL -o "$tmp/$name.tar.gz" "$base/$name.tar.gz" || err "download failed: $base/$name.tar.gz"
curl -fsSL -o "$tmp/SHA256SUMS.txt" "$base/SHA256SUMS.txt" || err "couldn't download SHA256SUMS.txt"

expected=$(grep " $name.tar.gz\$" "$tmp/SHA256SUMS.txt" | cut -d' ' -f1)
[ -n "$expected" ] || err "no checksum for $name.tar.gz"
actual=$(sha256sum "$tmp/$name.tar.gz" | cut -d' ' -f1)
[ "$expected" = "$actual" ] || err "checksum mismatch for $name.tar.gz"

tar -xzf "$tmp/$name.tar.gz" -C "$tmp"
src="$tmp/$name"
[ -x "$src/lib/port-why/port_why" ] || err "$name.tar.gz has no lib/port-why/port_why"

mkdir -p "$prefix/lib" || err "can't create $prefix"
[ -w "$prefix" ] && [ -w "$prefix/lib" ] || err "can't write to $prefix; run the script with sudo, or set PORTWHY_PREFIX"

# The app beside the old one, then swapped in, so a running Port Why keeps
# the files it has open.
rm -rf "$prefix/lib/port-why.new" "$prefix/lib/port-why.old"
cp -R "$src/lib/port-why" "$prefix/lib/port-why.new"
[ -d "$prefix/lib/port-why" ] && mv "$prefix/lib/port-why" "$prefix/lib/port-why.old"
mv "$prefix/lib/port-why.new" "$prefix/lib/port-why"
rm -rf "$prefix/lib/port-why.old"

for f in $(files); do
    mkdir -p "$(dirname "$prefix/$f")"
    rm -f "$prefix/$f.new"
    cp -P "$src/$f" "$prefix/$f.new"
    mv -f "$prefix/$f.new" "$prefix/$f"
done
# The launcher starts Port Why by its full path, so it works whether or not
# <prefix>/bin is on the session's PATH.
desktop="$prefix/share/applications/net.thirtytech.port_why.desktop"
sed "s|^Exec=port-why|Exec=\"$prefix/lib/port-why/port_why\"|" "$desktop" > "$desktop.new"
mv -f "$desktop.new" "$desktop"
mkdir -p "$prefix/share/doc/port-why"
cp "$src"/share/doc/port-why/* "$prefix/share/doc/port-why/"
refresh

echo "Installed Port Why $tag to $prefix/lib/port-why, with $prefix/bin/port-why to start it"
echo "Start it from your app launcher (Port Why), or run port-why."

# The libraries Port Why links (GTK 3 and the rest). EGL and OpenGL ES, which
# it loads when it starts, don't show here.
if command -v ldd >/dev/null 2>&1; then
    missing=$(ldd "$prefix/lib/port-why/port_why" 2>/dev/null |
        awk '/not found/ && !seen[$1]++ { printf "%s%s", sep, $1; sep = " " }')
    if [ -n "$missing" ]; then
        echo "Warning: Port Why needs libraries that aren't installed: $missing"
        echo "  On Debian or Ubuntu: sudo apt install libgtk-3-0 libepoxy0 libegl1 libgles2"
        echo "  On Fedora: sudo dnf install gtk3 libepoxy libglvnd-egl libglvnd-gles"
    fi
fi

case ":$PATH:" in
    *":$prefix/bin:"*) ;;
    *) echo "Note: $prefix/bin is not on your PATH. To run port-why from a terminal, add it:
  export PATH=\"$prefix/bin:\$PATH\"" ;;
esac
