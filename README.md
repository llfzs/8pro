# Xiaomi Pad 8 Pro - Linux 移植

SM8750-AB (Snapdragon 8 Elite) | 构建与 CI 操作说明

## 快速概览（推荐）

- **自动/手动构建（推荐）**: 使用 GitHub Actions。仓库包含两个 workflow：
	- `ci.yml`：手动触发（`workflow_dispatch`），支持传入 `KERNEL_REPO` / `KERNEL_BRANCH` / `KERNEL_PATH` / `BOOT_CMDLINE` / `BOOT_BASE` / `RAMDISK_PATH`。该流程使用预配置的缓存（apt、ccache、内核源码、kout），并设置 `SKIP_DEPS=1` 来避免脚本重复安装依赖。
	- `build.yml`：`push` 到 `main` 时自动触发（也可手动），行为与 `ci.yml` 类似但更自包含。

## 在 GitHub Actions 上运行（手动触发）

1. 打开仓库的 Actions → 选择 "Build Xiaomi Pad 8 Pro"（`ci.yml`）。
2. 点击 "Run workflow"，根据需要填写：`KERNEL_REPO` / `KERNEL_BRANCH` / `KERNEL_PATH` / `BOOT_CMDLINE` / `BOOT_BASE` / `RAMDISK_PATH`。
3. 提交，等待 workflow 完成。产物会在 `out/`（CI 打包）或 workflow release 中生成。

## 本地构建（Ubuntu/Debian）

建议在 x86_64 Ubuntu 环境下运行。示例依赖（可一次性安装）：

```bash
sudo apt-get update -qq
sudo apt-get install -y \
	gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
	device-tree-compiler bc bison flex libssl-dev libncurses-dev \
	python3 python3-pip wget curl cpio gzip e2fsprogs xz-utils \
	qemu-user-static debootstrap abootimg android-tools-fastboot build-essential zlib1g-dev parted ccache
```

常用构建命令：

```bash
# 安装系统级依赖（只需要一次）
sudo ./scripts/build.sh deps

# 单项构建
sudo ./scripts/build.sh kernel   # 仅编译内核
sudo ./scripts/build.sh boot     # 仅构建 boot.img
sudo ./scripts/build.sh rootfs   # 仅构建 rootfs.img

# 全量构建
sudo ./scripts/build.sh all
```

说明：脚本支持环境变量 `SKIP_DEPS=1` 跳过依赖安装（CI 中已设置）。

## CI 加速与缓存

- CI 已配置 `actions/cache` 来缓存：
	- 仓库内的 `.apt-cache`（避免重复下载 .deb）
	- `~/.ccache`（ccache）
	- 内核源码（`third_party/kernel`）和构建输出 (`build/kout`、`build/modules`)。 
- 我们在 workflow 中启用了 `ccache` 并将 `CCACHE_DIR` 指向工作目录，以便在后续运行复用编译缓存。

## 产物与打包

- 本地构建产物：`build/output/boot.img`、`build/output/rootfs.img`。
- CI 打包产物（用于 release）：`out/boot_piano.img`、`out/artifacts_all.tar.gz`（包含需要的文件）。
- 我添加了 `scripts/package_images.sh` 来把 `build/output/*` 拷贝到 `out/`，以配合 CI 的打包步骤。

## chroot 与 qemu

- 构建 rootfs 时脚本会尝试使用 `qemu-aarch64-static` 进行 `chroot` 安装包（apk）。若 `qemu-aarch64-static` 不存在，脚本会跳过 chroot，首次启动时需手工安装。
- 在 CI 环境中，`chroot` 需要 `sudo` 权限；脚本已在需要时使用 `sudo` 来避免 "Operation not permitted" 错误。

## 固件提取

- 若仓库内没有固件，脚本会尝试通过 ADB 从设备提取：
	```bash
	adb pull /lib/firmware/ath12k/ firmware/wifi/
	adb pull /lib/firmware/qcom/ firmware/gpu/
	adb pull /lib/firmware/qca/  firmware/bt/
	```

## 刷入设备

```bash
adb reboot bootloader
fastboot flash boot build/output/boot.img
fastboot flash userdata build/output/rootfs.img
fastboot set_active a
fastboot reboot
```

## 故障排查（常见）

- chroot 报 `Operation not permitted`：确保在 CI/主机上以 root/sudo 运行，且已安装 `qemu-aarch64-static`。
- 找不到交叉编译器 `aarch64-linux-gnu-gcc`：请安装交叉编译器包或在 CI 中使用带有交叉编译器的运行器/镜像。
- 无 WiFi/Bluetooth：请将相应固件放入 `firmware/` 目录或使用 ADB 提取。

---

