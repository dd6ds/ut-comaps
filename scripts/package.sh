#!/usr/bin/env bash
# Assemble the click directory and, when run on its own, build the .click.
# Called by scripts/build-comaps.sh with COMAPS_BIN set to the built binary.
#   $1 = target directory (clickable's install dir). Without it the click is
#        assembled in build/click and packed with "click build".
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="source/comaps"
BIN="${COMAPS_BIN:?COMAPS_BIN not set}"
CLICK_DIR="${1:-build/click}"
STANDALONE=0
[ -z "${1:-}" ] && STANDALONE=1
VERSION="${COMAPS_VERSION:-0.1.0}"
ARCH="${CLICK_ARCH:-arm64}"
FRAMEWORK="${COMAPS_FRAMEWORK:-ubuntu-touch-24.04-1.x}"

echo "[ut-comaps] Assembling click directory in $CLICK_DIR ..."
rm -rf "$CLICK_DIR"
mkdir -p "$CLICK_DIR/lib" "$CLICK_DIR/data"

# --- Click metadata and hooks (all paths are relative to the click root) -----
sed -e "s/@CLICK_VERSION@/$VERSION/" \
    -e "s/@CLICK_ARCH@/$ARCH/" \
    -e "s/@CLICK_FRAMEWORK@/$FRAMEWORK/" \
    manifest.in.json > "$CLICK_DIR/manifest.json"
cp ut-comaps.desktop ut-comaps.apparmor icons/ut-comaps.svg "$CLICK_DIR/"
install -m 755 launch/comaps "$CLICK_DIR/comaps"
# The 2404.x AppArmor profile forbids exec of /usr/bin/*; the launcher needs
# mkdir, so ship coreutils' mkdir inside the click (exec there is allowed).
install -D -m 755 "$(command -v mkdir)" "$CLICK_DIR/bin/mkdir"
install -m 755 "$BIN" "$CLICK_DIR/comaps.bin"

# --- App resources (drules, fonts, symbols, classificator, World.mwm, ...) ---
# Trim folders you do not need, e.g. COMAPS_DATA_EXCLUDE="test_data:vulkan_shaders".
EXCLUDES="${COMAPS_DATA_EXCLUDE:-}"
echo "[ut-comaps] Copying app data from $SRC/data ..."
rsync -a --delete \
    $(for e in ${EXCLUDES//:/ }; do echo "--exclude=$e"; done) \
    "$SRC/data/" "$CLICK_DIR/data/"

# --- Qt plugins --------------------------------------------------------------
PLUGINS=""
for d in /usr/lib/aarch64-linux-gnu/qt6/plugins /usr/lib/qt6/plugins; do
    [ -d "$d" ] && PLUGINS="$d" && break
done
if [ -z "$PLUGINS" ]; then
    echo "[ut-comaps] ERROR: Qt6 plugin directory not found." >&2
    exit 1
fi
mkdir -p "$CLICK_DIR/lib/plugins"
for p in platforms platforminputcontexts imageformats iconengines \
         wayland-shell-integration wayland-graphics-integration-client \
         wayland-decoration-client position; do
    [ -d "$PLUGINS/$p" ] && cp -a "$PLUGINS/$p" "$CLICK_DIR/lib/plugins/"
done

# --- Runtime libraries (Qt6 and its deps) ------------------------------------
# Bundles every shared library the binary and the plugins need, except those
# the phone must provide itself: the C runtime and everything that talks to
# the GPU and the compositor (libhybris EGL/GLES, Wayland, DRM). Copies of those
# from the container would break rendering or the session.
is_system_lib() {
    case "$(basename "$1")" in
        ld-linux*|libc.so*|libm.so*|libdl.so*|librt.so*|libpthread.so*|libresolv.so*|\
        libstdc++.so*|libgcc_s.so*|\
        libEGL*|libGL*|libGLES*|libGLX*|libGLdispatch*|libOpenGL*|libgbm*|libdrm*|\
        libwayland-*|libhybris*|libandroid*|\
        libdbus-1.so*|libsystemd.so*|libudev.so*)
            return 0 ;;
    esac
    return 1
}
declare -A SEEN=()
copy_libs() {
    local lib
    for lib in $(ldd "$@" 2>/dev/null | awk '$2 == "=>" && $3 ~ /^\// {print $3}' | sort -u); do
        [ -n "${SEEN[$lib]:-}" ] && continue
        SEEN[$lib]=1
        is_system_lib "$lib" && continue
        cp -Ln "$lib" "$CLICK_DIR/lib/"
        copy_libs "$lib"
    done
}
echo "[ut-comaps] Bundling shared libraries ..."
mapfile -t PLUGIN_SOS < <(find "$CLICK_DIR/lib/plugins" -name '*.so')
copy_libs "$CLICK_DIR/comaps.bin" "${PLUGIN_SOS[@]}"
echo "[ut-comaps] Bundled $(ls "$CLICK_DIR/lib" | grep -c '\.so') libraries."

# --- Build the click (clickable does this itself) -----------------------------
if [ "$STANDALONE" = "1" ]; then
    echo "[ut-comaps] Running click build ..."
    (cd build && click build click)
    echo "[ut-comaps] Done. Package: $(ls build/*.click)"
fi
