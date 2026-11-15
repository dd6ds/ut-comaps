#!/usr/bin/env bash
# Build the Qt position plugin "lomiri" against the bundled Qt6 (see
# scripts/lomiri-position/CMakeLists.txt). Needs liblomiri-location-service-dev
# from the UBports repository (Dockerfile.noble-arm64).
#   $1 = output directory for libqtposition_lomiri.so
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?output directory}"

# Plugin source with Qt6 support (3.4); it uses only the client API that the
# -dev package from the UBports 24.04-1.x repository (3.3) provides.
LLS_REF="${LLS_REF:-3.4.1}"
LLS_URL="${LLS_URL:-https://gitlab.com/ubports/development/core/lomiri-location-service.git}"
WORK="build/lomiri-position"
SRC="$WORK/src"

if [ ! -f "$SRC/qt/position/core_geo_position_info_source.cpp" ]; then
    rm -rf "$SRC"
    mkdir -p "$WORK"
    git clone -q --depth 1 --branch "$LLS_REF" "$LLS_URL" "$SRC"
fi

cmake -S scripts/lomiri-position -B "$WORK/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DLLS_SOURCE_DIR="$PWD/$SRC"
cmake --build "$WORK/build"
mkdir -p "$OUT"
install -m 644 "$WORK/build/libqtposition_lomiri.so" "$OUT/"
echo "[ut-comaps] Built $OUT/libqtposition_lomiri.so"
