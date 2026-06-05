#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# 默认值（可通过环境变量覆盖）
KERNEL_DIR="${KERNEL_DIR:-$ROOT_DIR/third_party/linux-kernel}"
ARCH="${ARCH:-arm64}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
NUM_JOBS="${NUM_JOBS:-$(nproc || echo 4)}"
DEFCONFIG="${DEFCONFIG:-defconfig}"

if [ ! -d "$KERNEL_DIR" ]; then
  echo "找不到内核源码目录: $KERNEL_DIR"
  echo "请设置 KERNEL_DIR 指向 third_party 中的内核源码。"
  exit 1
fi

echo "构建内核:"
echo "  KERNEL_DIR=$KERNEL_DIR"
echo "  ARCH=$ARCH"
echo "  CROSS_COMPILE=$CROSS_COMPILE"

cd "$KERNEL_DIR"

echo "清理旧的构建产物（不会删除配置）..."
make ARCH=$ARCH O=build mrproper || true

echo "创建默认配置: $DEFCONFIG"
if [ -f "arch/$ARCH/configs/$DEFCONFIG" ]; then
  make ARCH=$ARCH O=build $DEFCONFIG
else
  echo "警告: 未找到指定 defconfig，使用现有配置或手动提供。"
fi

echo "开始编译，使用 $NUM_JOBS 个并行任务..."
make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE O=build -j$NUM_JOBS

echo "编译完成。产物目录: $KERNEL_DIR/build/"
ls -la build/ || true

echo "生成 dtbs（如果有）..."
make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE O=build dtbs -j$NUM_JOBS || true

echo "提示：将内核镜像（Image/Image.gz）与 DTB 部署到引导分区或打包为 Android boot image。"
