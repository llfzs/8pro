#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# Configurable env vars
KERNEL_DIR="${KERNEL_DIR:-third_party/kernel}"
OUT_DIR="${OUT_DIR:-out}"
ART_DIR="${ART_DIR:-$OUT_DIR/artifacts}"
BOOT_CMDLINE="${BOOT_CMDLINE:-}" 
BOOT_BASE="${BOOT_BASE:-}"
BOOT_PAGESIZE="${BOOT_PAGESIZE:-}"
RAMDISK_PATH="${RAMDISK_PATH:-}">
MKBOOTIMG_ARGS="${MKBOOTIMG_ARGS:-}"

mkdir -p "$ART_DIR"

# locate kernel Image
if [ -f "$KERNEL_DIR/arch/arm64/boot/Image" ]; then
  KERNEL_IMAGE="$KERNEL_DIR/arch/arm64/boot/Image"
elif [ -f "$KERNEL_DIR/arch/arm64/boot/Image.gz" ]; then
  KERNEL_IMAGE="$KERNEL_DIR/arch/arm64/boot/Image.gz"
else
  echo "Kernel Image not found in $KERNEL_DIR; skipping boot image creation"
  KERNEL_IMAGE=""
fi

# prepare ramdisk: use provided RAMDISK_PATH or create a minimal one
if [ -n "$KERNEL_IMAGE" ]; then
  if [ -n "$RAMDISK_PATH" ] && [ -f "$RAMDISK_PATH" ]; then
    RAMDISK_IMG="$RAMDISK_PATH"
  else
    RAMDIR=$(mktemp -d)
    mkdir -p "$RAMDIR"/sbin
    cat > "$RAMDIR/init" <<'EOF'
#!/bin/sh
exec /sbin/init || exec /bin/sh
EOF
    chmod +x "$RAMDIR/init"
    (cd "$RAMDIR" && find . | cpio -o -H newc | gzip > "$OUT_DIR/ramdisk.img")
    rm -rf "$RAMDIR"
    RAMDISK_IMG="$OUT_DIR/ramdisk.img"
  fi

  # try mkbootimg then abootimg
  if command -v mkbootimg >/dev/null 2>&1; then
    CMD=(mkbootimg --kernel "$KERNEL_IMAGE" --ramdisk "$RAMDISK_IMG")
    [ -n "$BOOT_CMDLINE" ] && CMD+=(--cmdline "$BOOT_CMDLINE")
    [ -n "$BOOT_BASE" ] && CMD+=(--base "$BOOT_BASE")
    [ -n "$BOOT_PAGESIZE" ] && CMD+=(--pagesize "$BOOT_PAGESIZE")
    [ -n "$MKBOOTIMG_ARGS" ] && CMD+=( $MKBOOTIMG_ARGS )
    CMD+=(--output "$ART_DIR/boot.img")
    echo "Running: ${CMD[*]}"
    ${CMD[@]} || echo "mkbootimg failed (continuing)"
  elif command -v abootimg >/dev/null 2>&1; then
    echo "Using abootimg to create boot image"
    abootimg --create "$ART_DIR/boot.img" --kernel "$KERNEL_IMAGE" --ramdisk "$RAMDISK_IMG" --cmdline "$BOOT_CMDLINE" || echo "abootimg failed"
  else
    echo "mkbootimg/abootimg not found; packaging kernel+ramdisk as tarball instead"
    tar -C "$OUT_DIR" -czf "$ART_DIR/boot.img.tar.gz" "ramdisk.img" || true
    if [ -n "$KERNEL_IMAGE" ]; then
      cp "$KERNEL_IMAGE" "$ART_DIR/" || true
    fi
  fi
fi

# create ext4 rootfs image from out/rootfs and generate A/B images
if [ -d "$OUT_DIR/rootfs" ]; then
  SIZE_BYTES=$(du -sb "$OUT_DIR/rootfs" | cut -f1)
  SIZE_MB=$(( (SIZE_BYTES / 1024 / 1024) + 200 ))
  ROOTFS_IMG_RAW="$ART_DIR/rootfs.img.raw"
  dd if=/dev/zero of="$ROOTFS_IMG_RAW" bs=1M count=$SIZE_MB status=progress || true
  mkfs.ext4 -F "$ROOTFS_IMG_RAW"
  MNT=$(mktemp -d)
  sudo mount -o loop "$ROOTFS_IMG_RAW" "$MNT"
  sudo cp -a "$OUT_DIR/rootfs/." "$MNT/"
  sync
  sudo umount "$MNT"
  rmdir "$MNT"

  # try to convert to Android sparse if tool available
  if command -v img2simg >/dev/null 2>&1; then
    img2simg "$ROOTFS_IMG_RAW" "$ART_DIR/rootfs.img"
    echo "Created sparse rootfs.img"
  else
    # fallback: keep raw image and also provide system_a/system_b copies
    cp "$ROOTFS_IMG_RAW" "$ART_DIR/rootfs.img"
    echo "img2simg not found; produced raw ext4 rootfs.img"
  fi

  # produce system_a/system_b images (duplicate)
  cp "$ART_DIR/rootfs.img" "$ART_DIR/system_a.img"
  cp "$ART_DIR/rootfs.img" "$ART_DIR/system_b.img"
else
  echo "out/rootfs not found; skipping rootfs image creation"
fi

echo "Artifacts placed in $ART_DIR"
