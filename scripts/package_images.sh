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

# 新增：统一把所有镜像拷贝到 artifacts 目录
mkdir -p "$OUT/artifacts"
cp "$OUT"/*.img "$OUT/artifacts/" 2>/dev/null || true

echo "packaged artifacts into $OUT"
