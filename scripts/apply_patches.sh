#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

KERNEL_DIR="${KERNEL_DIR:-$ROOT_DIR/third_party/linux-kernel}"
PATCH_DIR="${PATCH_DIR:-$ROOT_DIR/device/patches}"

if [ ! -d "$KERNEL_DIR" ]; then
  echo "找不到内核源码目录: $KERNEL_DIR"
  exit 1
fi

if [ ! -d "$PATCH_DIR" ]; then
  echo "没有补丁目录，创建一个： $PATCH_DIR"
  mkdir -p "$PATCH_DIR"
  echo "请把补丁放到 $PATCH_DIR 下，脚本会按文件名排序应用。"
  exit 0
fi

cd "$KERNEL_DIR"

for p in $(ls "$PATCH_DIR"/*.patch 2>/dev/null | sort); do
  echo "应用补丁: $p"
  git apply --index "$p" || { echo "补丁应用失败: $p"; exit 1; }
done

echo "所有补丁已应用（若有）。请检查 git 状态以确认变更。"
