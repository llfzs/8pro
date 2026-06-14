#!/bin/bash
# Minimal packaging helper for CI
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$DIR/build"
OUT="$DIR/out"

mkdir -p "$OUT"

# copy kernel boot image(s)
if [ -f "$BUILD/output/boot.img" ]; then
    cp "$BUILD/output/boot.img" "$OUT/boot.img" || true
    cp "$BUILD/output/boot.img" "$OUT/boot_piano.img" || true
fi

# copy rootfs
if [ -f "$BUILD/output/rootfs.img" ]; then
    cp "$BUILD/output/rootfs.img" "$OUT/rootfs.img" || true
fi

echo "packaged artifacts into $OUT"
