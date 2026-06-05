#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "创建 third_party 目录并克隆参考仓库..."
mkdir -p third_party
cd third_party

repos=(
  "https://github.com/adontoo/device_xiaomi_sm8750_OFRP.git"
  "https://github.com/AviderMin/ofrp_device_xiaomi_piano.git"
  "https://github.com/CypressFjord/Build_Piano_ROM.git"
  "https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux.git"
)

for r in "${repos[@]}"; do
  name=$(basename "$r" .git)
  if [ -d "$name" ]; then
    echo "仓库 $name 已存在，拉取更新..."
    (cd "$name" && git pull --ff-only || true)
  else
    git clone "$r"
  fi
done

echo "参考仓库已下载到 third_party/ 下。"
