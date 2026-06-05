# xiaomi-pad-8pro-linux

基于以下参考仓库，为 Xiaomi Pad 8 Pro 创建的 Linux 支持项目骨架：

- https://github.com/adontoo/device_xiaomi_sm8750_OFRP
- https://github.com/AviderMin/ofrp_device_xiaomi_piano
- https://github.com/CypressFjord/Build_Piano_ROM
- https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/

本项目目标：
- 汇总参考仓库中的设备树、补丁和构建脚本，搭建面向 Xiaomi Pad 8 Pro 的 Linux 构建流程。
- 提供可复制的克隆与构建脚本，方便在 CI 或本地复现。

快速开始：

1. 克隆本仓库：

```bash
git clone <this-repo-url>
cd xiaomi-pad-8pro-linux
```

2. 下载参考仓库与依赖：

```bash
./scripts/clone_deps.sh
```

3. 构建（示例脚本）：

```bash
./scripts/build.sh
```

目录说明：
- `device/`：设备树、补丁与说明占位
- `scripts/`：克隆与构建辅助脚本
- `docs/`：开发与调试文档

后续：请提供设备具体型号、内核版本和目标根文件系统信息，我会继续填充设备树和补丁。

**刷机与测试（fastboot）**

生成的产物位于 `out/artifacts`，主要文件说明：

- `boot.img`：使用 `mkbootimg`/`abootimg` 打包的 Android boot image（若 CI 无法生成会提供 `boot.img.tar.gz` 与单独的 `Image`/`ramdisk`）。
- `rootfs.img`：ext4（raw 或 sparse）镜像，可作为 `system` 分区刷写。
- `system_a.img` / `system_b.img`：若设备为 A/B 分区，会复制 `rootfs.img` 以便分别刷写。

安全提醒：刷机会清除设备数据并且需要解锁 Bootloader。务必先备份数据并在测试设备上验证。某些设备还需要 AVB/vbmeta 签名或特殊分区布局。

本地验证（示例命令）

1) 临时引导测试 `boot.img`（不会刷写）：

```bash
fastboot boot out/artifacts/boot.img
```

2) 刷写 `boot` 分区：

```bash
fastboot flash boot out/artifacts/boot.img
```

3) 刷写 `system`（注意分区名与是否为 sparse）：

```bash
# 如果设备使用 A/B
fastboot flash system_a out/artifacts/system_a.img
fastboot flash system_b out/artifacts/system_b.img

# 或单槽设备
fastboot flash system out/artifacts/rootfs.img
```

如果 `rootfs.img` 是 raw ext4 且 fastboot 要求 sparse，可尝试在有 `img2simg` 的主机上将 raw 转为 sparse：

```bash
# 主机上（若已安装 img2simg）
img2simg out/artifacts/rootfs.img.raw out/artifacts/rootfs.img
```

更多：若设备无法启动，请提供 `logcat`、`dmesg` 或 fastboot 返回错误，我会继续协助诊断。

**CI 默认参数**

本仓库的 GitHub Actions workflow 为 `workflow_dispatch`，已提供可选输入并设置了常用默认值：

- `BOOT_CMDLINE`（默认）：`console=ttyMSM0,115200n8 rootwait androidboot.hardware=qcom`
- `BOOT_BASE`（默认）：`0x10000000`

你可以在 Actions → Run workflow 时覆盖这些参数，或把自定义 `RAMDISK_PATH` 填入以使用仓库中的 ramdisk 文件。
