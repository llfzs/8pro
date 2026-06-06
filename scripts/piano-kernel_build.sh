#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# Configurable variables
KERNEL_REPO="${KERNEL_REPO:-https://github.com/code002-2/sm8750-mainline.git}"
KERNEL_BRANCH="${KERNEL_BRANCH:-main}"
# Prefer CI-provided path; default to third_party/kernel to match CI layout
KERNEL_DIR="${KERNEL_DIR:-third_party/kernel}"
PKGDIR="${PKGDIR:-$ROOT_DIR/out/linux-package}"

echo "==> Piano-style kernel build: repo=$KERNEL_REPO branch=$KERNEL_BRANCH"

# ccache + clang setup
export CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache}"
export CCACHE_MAXSIZE="10G"
mkdir -p "$CCACHE_DIR"
export CC="ccache clang"
export CXX="ccache clang++"
export AR="llvm-ar"
export NM="llvm-nm"
export OBJCOPY="llvm-objcopy"
export OBJDUMP="llvm-objdump"
export READELF="llvm-readelf"
export STRIP="llvm-strip"

# use existing kernel dir if present (CI may have already cloned there)
if [ -d "$KERNEL_DIR" ] && [ -d "$KERNEL_DIR/.git" ]; then
  echo "Using existing kernel at $KERNEL_DIR"
  cd "$KERNEL_DIR"
else
  rm -rf "$KERNEL_DIR"
  git clone --depth 1 --branch "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_DIR"
  cd "$KERNEL_DIR"
fi

# try to pick an existing config from repo root or ../configs
CONFIG_PATH=""
if [ -n "${KERNEL_CONFIG_PATH:-}" ] && [ -f "${KERNEL_CONFIG_PATH}" ]; then
  CONFIG_PATH="${KERNEL_CONFIG_PATH}"
fi
if [ -z "$CONFIG_PATH" ]; then
  CONFIG_PATH=$(find "$ROOT_DIR" -maxdepth 2 -name "config*.aarch64" 2>/dev/null | head -n1 || true)
fi
if [ -n "$CONFIG_PATH" ] && [ -f "$CONFIG_PATH" ]; then
  echo "Using kernel config: $CONFIG_PATH"
  cp "$CONFIG_PATH" .config
else
  echo "No external config found. Will attempt 'make defconfig' if supported by this kernel tree."
  if [ -f Makefile ] && grep -q "defconfig" Makefile; then
    echo "Kernel Makefile supports defconfig; running 'make defconfig ARCH=arm64'"
    make defconfig ARCH=arm64
  else
    echo "当前内核源码不包含 'defconfig' 目标。请提供一个配置文件并设置 KERNEL_CONFIG_PATH 环境变量，或在仓库中添加一个可被脚本找到的 config*.aarch64 文件。"
    echo "示例：cp configs/config-postmarketos-qcom-sm8750.aarch64 $PWD/.config 或 设置 KERNEL_CONFIG_PATH=/path/to/config"
    exit 1
  fi
fi

echo "Building kernel with clang..."
make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1
_kernel_version="$(make kernelrelease -s)"

echo "Collecting artifacts into $PKGDIR"
mkdir -p "$PKGDIR/boot"
ARCH=arm64
if [ -f "arch/$ARCH/boot/Image.gz" ]; then
  install -Dm644 "arch/$ARCH/boot/Image.gz" "$PKGDIR/boot/Image.gz"
elif [ -f "arch/$ARCH/boot/Image" ]; then
  gzip -c "arch/$ARCH/boot/Image" > "$PKGDIR/boot/Image.gz"
fi

# install dtb if present
DTB=$(find arch/$ARCH/boot/dts -name '*.dtb' | head -n1 || true)
if [ -n "$DTB" ]; then
  install -Dm644 "$DTB" "$PKGDIR/boot/$(basename $DTB)"
fi

install -Dm644 .config "$PKGDIR/boot/config-${_kernel_version}" || true
install -Dm644 System.map "$PKGDIR/boot/System.map-${_kernel_version}" || true

# prepare zImage+dtb similar to reference project
cd "$PKGDIR/boot"
if [ -f Image.gz ] && ls *.dtb 1> /dev/null 2>&1; then
  DTB_FILE=$(ls *.dtb | head -n1)
  cat Image.gz "$DTB_FILE" > Image.gz-dtb
  mv Image.gz-dtb zImage_piano || true
  echo "Created zImage_piano"
else
  echo "Image.gz or DTB missing; skipping zImage_piano creation"
fi

# call mkbootimg to create boot images (use env BOOT_CMDLINE / BOOT_BASE)
cd "$ROOT_DIR"
if [ -x ./mkbootimg ] || command -v mkbootimg >/dev/null 2>&1; then
  MKBOOTIMG=${MKBOOTIMG:-$(command -v mkbootimg || echo ./mkbootimg)}
  if [ -f "$PKGDIR/boot/zImage_piano" ]; then
    CMDLINE="${BOOT_CMDLINE:-root=PARTLABEL=linux rootwait rw}"
    BASE="${BOOT_BASE:-0x00000000}"
    echo "Generating boot images with mkbootimg"
    "$MKBOOTIMG" --kernel "$PKGDIR/boot/zImage_piano" --cmdline "$CMDLINE" --base "$BASE" --kernel_offset 0x00008000 --tags_offset 0x01e00000 --pagesize 4096 --id -o "$ROOT_DIR/out/boot_piano.img" || true
  else
    echo "No zImage_piano found; skipping mkbootimg step"
  fi
else
  echo "mkbootimg not available; skipping boot packaging"
fi

echo "Kernel build finished. Artifacts in $PKGDIR and out/"
