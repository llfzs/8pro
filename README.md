# Xiaomi Pad 8 Pro - Linux 移植

SM8750-AB (Snapdragon 8 Elite) | 构建与 CI 操作说明

## 快速概览

本项目为小米 Pad 8 Pro 提供 Linux 内核构建与 rootfs 打包，支持本地构建和 GitHub Actions CI。

### CI Workflow

| Workflow | 触发方式 | 功能 |
|----------|----------|------|
| `build-kernel.yml` | push to main / 手动 | 编译内核，发布 `kernel-latest` release |
| `build-rootfs.yml` | push to main / 手动 | 下载预编译内核，生成 boot.img + vbmeta.img + rootfs.img |

## 在 GitHub Actions 上运行（手动触发）

1. 打开仓库的 **Actions** → 选择 "Build Kernel" 或 "Build Rootfs"。
2. 点击 **Run workflow**，根据需要填写参数：
   - `build-rootfs.yml` 支持 `kernel_tag` 参数指定内核 release tag（默认 `kernel-latest`）
3. 提交，等待 workflow 完成。产物会在对应 release 中生成。

## 本地构建（Ubuntu/Debian）

建议在 x86_64 Ubuntu 环境下运行。

### 安装依赖

```bash
sudo apt-get update -qq
sudo apt-get install -y \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
    device-tree-compiler bc bison flex libssl-dev libelf-dev \
    python3 python3-pip wget curl cpio gzip e2fsprogs xz-utils \
    qemu-user-static build-essential zlib1g-dev parted
```

### 构建命令

```bash
# 安装系统级依赖（只需要一次）
sudo ./scripts/build.sh deps

# 单项构建
sudo ./scripts/build.sh kernel       # 仅编译内核
sudo ./scripts/build.sh boot         # 仅构建 boot.img
sudo ./scripts/build.sh vbmeta       # 仅生成 vbmeta.img（禁用 AVB）
sudo ./scripts/build.sh rootfs       # 仅构建 rootfs.img

# 全量构建（内核 + boot + vbmeta + rootfs）
sudo ./scripts/build.sh all
```

说明：脚本支持环境变量 `SKIP_DEPS=1` 跳过依赖安装（CI 中已设置）。

## 产物

| 文件 | 说明 |
|------|------|
| `build/output/boot.img` | Android boot image（内核 + initramfs + DTB） |
| `build/output/vbmeta.img` | AVB 验证已禁用的 vbmeta |
| `build/output/rootfs.img` | Alpine Linux 根文件系统（ext4） |
| `build/output/kernel-artifacts.tar.gz` | 内核产物压缩包（CI 用） |

## CI 加速与缓存

- CI 已配置 `actions/cache` 来缓存 BusyBox 静态二进制
- `build-kernel.yml` 会将内核产物发布到 `kernel-latest` release
- `build-rootfs.yml` 自动从 release 下载内核产物，避免重复编译

## chroot 与 qemu

- 构建 rootfs 时脚本会尝试使用 `qemu-aarch64-static` 进行 `chroot` 安装包（apk）。
- 若 `qemu-aarch64-static` 不存在，脚本会跳过 chroot，首次启动时需手工安装。
- chroot 期间会安装以下软件：openrc、NetworkManager、openssh、bluez、mesa 等。

## 固件

项目内已预置必要的非自由固件（`firmware/` 目录）：
- **WiFi**: ath12k / WCN7850
- **蓝牙**: qca
- **GPU**: qcom a680

若仓库内没有固件，脚本会尝试通过 ADB 从设备提取：
```bash
adb pull /vendor/firmware/ath12k/ firmware/wifi/
adb pull /vendor/firmware/qcom/   firmware/gpu/
adb pull /vendor/firmware/qca/    firmware/bt/
```

## 刷入设备

**⚠️ 刷机前必须先解锁 Bootloader（通过 MiUnlockTool）**

```bash
adb reboot bootloader

# 禁用 AVB 验证（必须）
fastboot flash vbmeta --disable-verity --disable-verification build/output/vbmeta.img

# 刷入系统
fastboot flash boot build/output/boot.img
fastboot flash userdata build/output/rootfs.img
fastboot set_active a
fastboot reboot
```

## 安全说明

- rootfs 默认 root 密码为 `pad8pro`，**首次登录后请立即修改**：`passwd`
- SSH 默认禁止空密码登录和 root 密码登录
- 建议配置 SSH key 认证后禁用密码登录

## 故障排查

| 问题 | 解决方案 |
|------|----------|
| chroot 报 `Operation not permitted` | 确保以 root/sudo 运行，且已安装 `qemu-aarch64-static` |
| 找不到交叉编译器 `aarch64-linux-gnu-gcc` | 执行 `sudo apt install gcc-aarch64-linux-gnu` |
| 无 WiFi/Bluetooth | 检查 `firmware/` 目录是否包含对应固件 |
| 刷入后无法启动 | 确认已刷 vbmeta 禁用 AVB，检查串口日志 |
| initramfs 进入紧急 shell | 块设备未就绪，检查 UFS 驱动是否正确加载 |

## 硬件信息

- **SoC**: Snapdragon 8 Elite (SM8750-AB)
- **显示**: 11.2" 3200x2136 DSI LCD
- **GPU**: Adreno 830 (freedreno / a680)
- **WiFi**: WCN7850 (ath12k, PCIe)
- **蓝牙**: WCN7850 (btqca, GENI UART)
- **触控**: Novatek nt36532 (SPI)
- **存储**: UFS (KIOXIA)

## License

本项目基于 GPL-2.0 许可证发布。详见 [LICENSE](LICENSE)。
