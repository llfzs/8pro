#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
THIRD_DIR="$ROOT_DIR/third_party"
DEVICE_DIR="$ROOT_DIR/device"

mkdir -p "$DEVICE_DIR/device-tree/dts"
mkdir -p "$DEVICE_DIR/kernel/patches"
mkdir -p "$DEVICE_DIR/kernel/configs"

echo "扫描 $THIRD_DIR 中的参考仓库，提取与 sm8750 / piano 相关的 DTS、补丁与配置..."

if [ ! -d "$THIRD_DIR" ]; then
  echo "third_party 目录不存在，请先运行 ./scripts/clone_deps.sh"
  exit 1
fi

# 搜索常见文件类型并复制
find "$THIRD_DIR" -type f \( -iname "*.dts" -o -iname "*.dtsi" -o -iname "*.dtb" \) | while read -r f; do
  # 仅提取与 sm8750 或 piano 相关的文件（名称或路径包含关键词）
  if echo "$f" | grep -Eqi "sm8750|piano|xiaomi|piano"; then
    echo "复制 DTS/DTB: $f"
    cp -a "$f" "$DEVICE_DIR/device-tree/dts/" || true
  fi
done

# 复制补丁（*.patch 或 */patches/*）
find "$THIRD_DIR" -type f \( -iname "*.patch" -o -iname "*.diff" \) | while read -r p; do
  if echo "$p" | grep -Eqi "sm8750|piano|xiaomi|patch"; then
    echo "复制补丁: $p"
    cp -a "$p" "$DEVICE_DIR/kernel/patches/" || true
  fi
done

# 复制内核配置或 defconfig
find "$THIRD_DIR" -type f -iname "*defconfig*" | while read -r c; do
  echo "复制配置: $c"
  cp -a "$c" "$DEVICE_DIR/kernel/configs/" || true
done

echo "提取完成。请检查 device/ 下的文件并手动验证。"
