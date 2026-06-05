echo "示例构建流程（占位）。请根据目标内核和交叉编译链修改此脚本。"
#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "高层构建脚本：按顺序克隆依赖、提取设备文件、应用补丁、构建内核并准备 rootfs"

./scripts/clone_deps.sh

./scripts/extract_third_party.sh

# 应用补丁（需要将 KERNEL_DIR 指向 third_party 中的内核源码）
./scripts/apply_patches.sh || true

# 构建内核（需要设置 KERNEL_DIR 和 CROSS_COMPILE）
./scripts/build_kernel.sh || true

# 创建 Debian rootfs（可选）
./scripts/setup_debian_rootfs.sh || true

echo "构建流程结束（占位）。请根据实际内核源码路径与交叉编译链调整环境变量。"
