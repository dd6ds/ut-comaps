#!/usr/bin/env bash
# Fetch the CoMaps sources at a pinned commit (shallow + partial clone).
# The patches in patches/ are made against this commit; to move on, change
# COMAPS_REF, run this script and check that scripts/apply-patches.sh still works.
# Usage: clickable script source   (or: ./scripts/fetch-source.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="source/comaps"
URL="${COMAPS_GIT_URL:-https://codeberg.org/comaps/comaps.git}"
# Mirror fallback: COMAPS_GIT_URL=https://github.com/comaps/comaps.git
REF="${COMAPS_REF:-27ea5a9b92b266abe6d1b690e02ad5c89bf95217}"

if [ ! -d "$SRC/.git" ]; then
    mkdir -p "$SRC"
    git -C "$SRC" init -q
    git -C "$SRC" remote add origin "$URL"
fi

if [ "$(git -C "$SRC" rev-parse -q --verify HEAD 2>/dev/null || true)" = "$REF" ]; then
    echo "[ut-comaps] Sources already at $REF."
else
    echo "[ut-comaps] Fetching $URL @ $REF (several GB with submodules) ..."
    git -C "$SRC" fetch --depth 1 --filter=blob:limit=128k origin "$REF"
    # Drop earlier patches before switching the commit.
    git -C "$SRC" reset -q --hard
    git -C "$SRC" clean -qfd
    git -C "$SRC" checkout -q --detach FETCH_HEAD
fi
git -C "$SRC" submodule update --init --recursive --depth 1

echo "[ut-comaps] Source checkout done: $(git -C "$SRC" rev-parse --short HEAD)"
