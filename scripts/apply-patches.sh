#!/usr/bin/env bash
# Apply patches/*.patch to source/comaps. Safe to run again: patches that are
# already in place are skipped.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="source/comaps"
for patch in patches/*.patch; do
    [ -e "$patch" ] || continue
    name="$(basename "$patch")"
    if git -C "$SRC" apply --reverse --check "$PWD/$patch" 2>/dev/null; then
        echo "[ut-comaps] Patch already applied: $name"
    elif git -C "$SRC" apply --check "$PWD/$patch"; then
        git -C "$SRC" apply "$PWD/$patch"
        echo "[ut-comaps] Patch applied: $name"
    else
        echo "[ut-comaps] ERROR: $name does not apply to $(git -C "$SRC" rev-parse --short HEAD)." >&2
        echo "            Use the pinned COMAPS_REF from scripts/fetch-source.sh or update the patch." >&2
        exit 1
    fi
done
