#!/usr/bin/env bash
# Build CoMaps (desktop target) inside the noble/arm64 container.
# Runs via: clickable build  (which passes the install dir as $1)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
INSTALL="${1:-${INSTALL_DIR:-}}"

SRC="source/comaps"
if [ ! -d "$SRC" ]; then
    echo "[ut-comaps] Sources missing. Run 'clickable script source' first." >&2
    exit 1
fi

# 0) Ubuntu Touch integration (appearance, language) on top of CoMaps.
scripts/apply-patches.sh

# 1) Configure the repository (creates python venv with the right protobuf,
#    generates countries strings etc.). See docs/INSTALL.md of CoMaps.
cd "$SRC"
if [ "${COMAPS_SKIP_PYTHON_VENV:-0}" = "1" ]; then
    export SKIP_PYTHON_VENV=1
fi
./configure.sh

# 1b) Symbol skins (data/symbols/<dpi>/<style>/symbols.png|sdf). They are not in
#     git; without them the map has no POI icons ("unknown symbol" warnings).
#     generate_symbols.sh silently exits 0 when optipng is missing, so check.
if ! ls data/symbols/xhdpi/light/symbols.png >/dev/null 2>&1; then
    command -v optipng >/dev/null || { echo "[ut-comaps] ERROR: optipng missing (needed for symbols)" >&2; exit 1; }
    echo "[ut-comaps] Generating symbol skins ..."
    tools/unix/generate_symbols.sh
fi
for s in light dark; do
    if [ ! -f "data/symbols/xhdpi/$s/symbols.png" ]; then
        echo "[ut-comaps] ERROR: data/symbols/xhdpi/$s/symbols.png was not generated." >&2
        exit 1
    fi
done

# 2) Build the desktop app, release flavour.
#    tools/unix/build_omim.sh puts the result into ../omim-build-release
#    (i.e. source/omim-build-release).
echo "[ut-comaps] Building desktop target (this takes a long time under qemu emulation) ..."
tools/unix/build_omim.sh -r desktop

# 3) Locate the binary (sibling of the checkout).
cd "$ROOT"
BIN=""
for p in source/omim-build-release/CoMaps source/omim-build-release/desktop; do
    if [ -x "$p" ]; then BIN="$p"; break; fi
done
if [ -z "$BIN" ]; then
    echo "[ut-comaps] ERROR: built binary not found in source/omim-build-release." >&2
    exit 1
fi
echo "[ut-comaps] Built binary: $BIN"

# 4) Assemble the click (into clickable's install dir if given).
export COMAPS_BIN="$BIN"
scripts/package.sh "$INSTALL"
