#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOTFS_DIR="${ROOTFS_DIR:-$ROOT_DIR/out/rootfs}"
DEBIAN_SUITE="${DEBIAN_SUITE:-bookworm}"
ARCH="${ARCH:-arm64}"
MIRROR="${MIRROR:-http://deb.debian.org/debian}"

mkdir -p "$ROOTFS_DIR"

echo "准备 Debian 根文件系统（需要 root 权限并且主机安装 debootstrap）。"

echo "目标目录: $ROOTFS_DIR"

echo "如果需要在 x86 主机上 chroot ARM64，需要安装 qemu-user-static 并注册 binfmt。"

if ! command -v debootstrap >/dev/null 2>&1; then
  echo "未找到 debootstrap，请先安装（例如：sudo apt install debootstrap qemu-user-static）。"
  exit 1
fi

sudo debootstrap --arch=$ARCH $DEBIAN_SUITE "$ROOTFS_DIR" $MIRROR

echo "基础 Debian rootfs 已创建在 $ROOTFS_DIR。可 chroot 进行定制或打包为镜像。"
