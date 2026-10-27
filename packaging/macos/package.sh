#!/usr/bin/env bash
# Packages Port Why for macOS:
#
#   package.sh <Port Why.app> <name>
#
# <Port Why.app> is what `flutter build macos --release` made
# (build/macos/Build/Products/Release/Port Why.app) and <name> the
# download's name without an extension (port-why-1.2.0-macos-universal).
# Writes <name>.dmg in the current directory, holding Port Why.app and a link
# to /Applications over a background (dmg.py, which needs python3 and
# network access for pip to fetch dmg-requirements.txt).
#
# Signing, from the environment, when the repository has these secrets:
#
#   MACOS_CERT_P12          base64 of a "Developer ID Application"
#                           certificate and key, exported as .p12
#   MACOS_CERT_PASSWORD     the .p12's password
#   MACOS_SIGNING_IDENTITY  optional; the identity to sign with. Default:
#                           the first Developer ID Application identity in
#                           the certificate
#   MACOS_NOTARY_APPLE_ID   the Apple ID to notarize with
#   MACOS_NOTARY_TEAM_ID    its team ID
#   MACOS_NOTARY_PASSWORD   an app-specific password for that Apple ID
#
# Without MACOS_CERT_P12 the app keeps the ad hoc signature Flutter's build
# gives it, which Apple silicon needs to run it at all; Gatekeeper then
# blocks the first launch until the user allows it. Without the three
# MACOS_NOTARY_* values a Developer ID build is signed but not notarized.
set -euo pipefail

[ $# -eq 2 ] || { echo "usage: $0 <Port Why.app> <name>" >&2; exit 2; }
src=$1 name=$2
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)

[ -d "$src/Contents/MacOS" ] || { echo "package.sh: $src isn't an app bundle" >&2; exit 1; }

stage=$(mktemp -d)
keychain=""
cleanup() {
    [ -n "$keychain" ] && security delete-keychain "$keychain" 2>/dev/null
    rm -rf "$stage"
}
trap cleanup EXIT

app="$stage/Port Why.app"
ditto "$src" "$app"

identity="-"
if [ -n "${MACOS_CERT_P12:-}" ]; then
    keychain="$stage/signing.keychain-db"
    keychain_password=$(uuidgen)
    echo "$MACOS_CERT_P12" | base64 --decode > "$stage/cert.p12"
    security create-keychain -p "$keychain_password" "$keychain"
    security set-keychain-settings -lut 21600 "$keychain"
    security unlock-keychain -p "$keychain_password" "$keychain"
    security import "$stage/cert.p12" -k "$keychain" -P "${MACOS_CERT_PASSWORD:-}" \
        -T /usr/bin/codesign -T /usr/bin/security
    rm "$stage/cert.p12"
    security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
    # Search the new keychain as well as the usual ones, one argument each.
    # shellcheck disable=SC2046
    security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')
    identity="${MACOS_SIGNING_IDENTITY:-}"
    if [ -z "$identity" ]; then
        identity=$(security find-identity -v -p codesigning "$keychain" |
            sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)
    fi
    [ -n "$identity" ] || { echo "package.sh: no Developer ID Application identity in MACOS_CERT_P12" >&2; exit 1; }
    echo "Signing with $identity"
    # The frameworks first, then the bundle, which seals them. The hardened
    # runtime and a secure timestamp are what notarization asks for; the
    # entitlements are the release build's (no sandbox, so the app can run
    # lsof and ps and see other processes).
    sign=(codesign --force --options runtime --timestamp --sign "$identity")
    for framework in "$app"/Contents/Frameworks/*.framework; do
        "${sign[@]}" "$framework"
    done
    "${sign[@]}" --entitlements "$root/macos/Runner/Release.entitlements" "$app"
else
    echo "No MACOS_CERT_P12: keeping the build's ad hoc signature"
fi
codesign --verify --deep --strict --verbose=2 "$app"

# The disk image: the app and a link to drag it onto, laid out over
# dmg-background.png by dmg.py with the pinned dmgbuild.
python3 -m venv "$stage/venv"
"$stage/venv/bin/pip" install --quiet --disable-pip-version-check --require-hashes \
    -r "$here/dmg-requirements.txt"
rm -f "$name.dmg"
"$stage/venv/bin/python" "$here/dmg.py" "$app" "$name.dmg"

if [ "$identity" != "-" ]; then
    codesign --force --timestamp --sign "$identity" "$name.dmg"
    if [ -n "${MACOS_NOTARY_APPLE_ID:-}" ] && [ -n "${MACOS_NOTARY_TEAM_ID:-}" ] && [ -n "${MACOS_NOTARY_PASSWORD:-}" ]; then
        echo "Notarizing $name.dmg"
        notary=(--apple-id "$MACOS_NOTARY_APPLE_ID" --team-id "$MACOS_NOTARY_TEAM_ID"
            --password "$MACOS_NOTARY_PASSWORD")
        xcrun notarytool submit "$name.dmg" "${notary[@]}" --wait --timeout 30m \
            --output-format json > "$stage/notary.json" || true
        cat "$stage/notary.json"
        status=$(plutil -extract status raw "$stage/notary.json" 2>/dev/null || echo unknown)
        if [ "$status" != Accepted ]; then
            # Apple's log says which file failed and why.
            id=$(plutil -extract id raw "$stage/notary.json" 2>/dev/null || true)
            [ -n "$id" ] && xcrun notarytool log "$id" "${notary[@]}" || true
            echo "package.sh: notarization ended with status $status" >&2
            exit 1
        fi
        xcrun stapler staple "$name.dmg"
        xcrun stapler validate "$name.dmg"
    else
        echo "No MACOS_NOTARY_* credentials: signed but not notarized"
    fi
fi
echo "Wrote $name.dmg"
