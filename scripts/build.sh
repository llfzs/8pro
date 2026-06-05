echo "示例构建流程（占位）。请根据目标内核和交叉编译链修改此脚本。"
#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "高层构建脚本：按顺序克隆依赖、提取设备文件、应用补丁、构建内核并准备 rootfs"

./scripts/clone_deps.sh

./scripts/extract_third_party.sh

# 应用补丁（保持兼容）
./scripts/apply_patches.sh || true

# 使用 Piano 项目相似的构建流程：内核编译 -> 打包 boot -> 生成 rootfs 镜像
echo "运行 piano-style 内核构建"
chmod +x ./scripts/piano-kernel_build.sh
./scripts/piano-kernel_build.sh || true

echo "打包 rootfs 和 boot 镜像"
chmod +x ./scripts/package_images.sh
./scripts/package_images.sh || true

echo "构建流程结束。产物位于 out/ 和 out/artifacts/。"
