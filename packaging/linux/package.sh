#!/usr/bin/env bash
# Packages Port Why for Linux:
#
#   package.sh <bundle> <version> <name>
#
# <bundle> is what `flutter build linux --release` made
# (build/linux/<arch>/release/bundle), <version> the version it was built as
# (1.2.0, or 1.2.0-dev.abc1234 for a build that isn't a release) and <name>
# the downloads' name without an extension (port-why-1.2.0-linux-x64).
# Writes, in the current directory:
#
#   <name>.tar.gz       a prefix tree to unpack into ~/.local or /usr/local
#                       (install.sh at the repository's root does that)
#   <name>.deb          when NFPM names nfpm: packages that install the same
#   <name>.rpm          tree under /usr (nfpm.yaml)
#   <name>.pkg.tar.zst
#
# The tree: the bundle in lib/port-why (Flutter finds its lib/ and data/
# next to the binary, even through a symlink), bin/port-why linking to it,
# and the launcher, icons and README under share/.
set -euo pipefail

[ $# -eq 3 ] || { echo "usage: $0 <bundle> <version> <name>" >&2; exit 2; }
bundle=$1 version=$2 name=$3
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
sizes=(16 32 48 64 128 256 512)

[ -x "$bundle/port_why" ] || { echo "package.sh: no port_why in $bundle" >&2; exit 1; }

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
tree="$stage/$name"
mkdir -p "$tree/lib" "$tree/bin"
cp -R "$bundle" "$tree/lib/port-why"
ln -s ../lib/port-why/port_why "$tree/bin/port-why"
install -Dm644 "$here/net.thirtytech.port_why.desktop" "$tree/share/applications/net.thirtytech.port_why.desktop"
for size in "${sizes[@]}"; do
    install -Dm644 "$here/../icons/$size.png" "$tree/share/icons/hicolor/${size}x${size}/apps/port-why.png"
done
install -Dm644 "$root/README.md" "$tree/share/doc/port-why/README.md"
tar -czf "$name.tar.gz" -C "$stage" "$name"
echo "Wrote $name.tar.gz"

if [ -n "${NFPM:-}" ]; then
    case "$(uname -m)" in
        x86_64 | amd64) goarch=amd64 ;;
        aarch64 | arm64) goarch=arm64 ;;
        *) echo "package.sh: no packages for $(uname -m)" >&2; exit 1 ;;
    esac
    # nfpm reads the tree relative to the directory it runs in.
    out=$(pwd)
    for format in deb rpm archlinux; do
        v="$version"
        case "$format" in
            # Arch's pkgver can't hold a "-", and nfpm drops a pre-release
            # from it: 1.2.0-dev.abc1234 goes in as 1.2.0dev.abc1234, which
            # pacman orders before 1.2.0. deb and rpm get 1.2.0~dev.abc1234.
            archlinux) file="$name.pkg.tar.zst" v="${v/-/}" ;;
            *) file="$name.$format" ;;
        esac
        (cd "$tree" && VERSION="$v" ARCH=$goarch \
            "$NFPM" package --config "$here/nfpm.yaml" --packager "$format" --target "$out/$file")
        echo "Wrote $file"
    done
fi
