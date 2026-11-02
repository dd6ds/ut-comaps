#!/usr/bin/env bash
# Build the Maliit input context plugin for Qt6 (on-screen keyboard support).
#
# Why: Lomiri exports QT_IM_MODULE=maliit. Native UT apps (Qt5) load the Qt5
# maliit plugin, which talks to maliit-server over D-Bus. Qt6 has no such
# plugin, and Lomiri offers no Wayland text-input protocol to clients, so a
# Qt6 app gets no keyboard at all. Ubuntu Noble does not package the Qt6
# variant, and a prebuilt one from newer Debian cannot be used: the plugin uses
# private Qt API (QPlatformInputContext) and must match the Qt version exactly
# (Noble: Qt 6.4.2).
#
# Source: maliit-framework 2.3.0 + the Debian/UBports patch series, which adds
# Qt6 support and the UBports D-Bus socket location used by UT's maliit-server.
#
# Usage: scripts/build-maliit-qt6.sh [output-dir]   (default /opt/maliit-qt6)
# Result: <output-dir>/libmaliitplatforminputcontextplugin.so
set -euo pipefail

OUT="${1:-/opt/maliit-qt6}"
VERSION="2.3.0"
DEBIAN_REV="${MALIIT_DEBIAN_REV:-2.3.0-11}"
POOL="https://deb.debian.org/debian/pool/main/m/maliit-framework"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cd "$WORK"
echo "[maliit-qt6] Fetching maliit-framework $VERSION + Debian $DEBIAN_REV patches ..."
curl -fsSLO "$POOL/maliit-framework_${VERSION}.orig.tar.gz"
curl -fsSLO "$POOL/maliit-framework_${DEBIAN_REV}.debian.tar.xz"
tar xf "maliit-framework_${VERSION}.orig.tar.gz"
SRC="$(find . -maxdepth 1 -type d -name 'framework-*' -o -maxdepth 1 -type d -name 'maliit-framework-*' | head -1)"
[ -n "$SRC" ] || { echo "[maliit-qt6] ERROR: source dir not found" >&2; exit 1; }
tar xf "maliit-framework_${DEBIAN_REV}.debian.tar.xz" -C "$SRC"

cd "$SRC"
while read -r p; do
    case "$p" in ''|'#'*) continue ;; esac
    echo "[maliit-qt6] patch $p"
    patch -p1 --forward --quiet < "debian/patches/$p"
done < debian/patches/series

cmake -S . -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_WITH_QT6=ON \
    -Denable-docs=OFF -Denable-tests=OFF -Denable-examples=OFF \
    -Denable-glib=OFF -Denable-xcb=OFF -Denable-wayland=OFF \
    -Denable-hwkeyboard=OFF -Denable-dbus-activation=OFF \
    -Denable-qt-inputcontext=ON
cmake --build build --target maliitplatforminputcontextplugin

PLUGIN="$(find build -name 'libmaliitplatforminputcontextplugin.so' | head -1)"
[ -n "$PLUGIN" ] || { echo "[maliit-qt6] ERROR: plugin not built" >&2; exit 1; }
mkdir -p "$OUT"
install -m 644 "$PLUGIN" "$OUT/"
echo "[maliit-qt6] Installed $OUT/$(basename "$PLUGIN")"
