# 刷机与调试指南 - Xiaomi Pad 8 Pro (piano) Linux

## 目录
1. [前置准备](#前置准备)
2. [解锁 Bootloader](#解锁-bootloader)
3. [刷入设备](#刷入设备)
4. [ADB 调试](#adb-调试)
5. [串口调试](#串口调试)
6. [常见问题排查](#常见问题排查)
7. [救砖指南](#救砖指南)

---

## 前置准备

### 硬件
- Xiaomi Pad 8 Pro (piano) - 已解锁 BL
- USB 3.0 Type-C 数据线
- 电脑（Linux 推荐）

### 软件
```bash
sudo apt install android-tools-adb android-tools-fastboot
```

### 构建产物
```bash
./scripts/build.sh all
```
产物位于：
```
build/output/
├── boot.img        # 启动镜像（内核 + initramfs + DTB）
├── vbmeta.img      # AVB 验证已禁用
└── rootfs.img      # Alpine Linux 根文件系统
```

---

## 解锁 Bootloader

> **警告**：解锁 BL 会清空所有数据，请先备份！

1. 开启「开发者选项」：设置 → 关于平板 → 连续点击「MIUI 版本」
2. 开启「OEM 解锁」和「USB 调试」
3. 绑定小米账号（设置 → 开发者选项 → 设备解锁状态 → 绑定账号）
4. 下载小米解锁工具：https://www.miui.com/unlock/
5. 进入 fastboot：关机后按住 `音量下 + 电源`
6. 连接电脑，运行解锁工具
7. 等待 168 小时（7天）后再次执行解锁

---

## 刷入设备

### 完整刷入

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

### A/B 设备说明

piano 是 A/B 设备，建议首次只刷一个槽位：

```bash
# 查看当前槽位
fastboot getvar current-slot

# 刷入指定槽位（保留另一个为原厂系统）
fastboot flash boot_a build/output/boot.img
fastboot flash vbmeta_a --disable-verity --disable-verification build/output/vbmeta.img
fastboot flash userdata build/output/rootfs.img
fastboot set_active a
fastboot reboot

# 切回原生安卓
fastboot set_active b && fastboot reboot
```

---

## ADB 调试

```bash
adb devices
adb shell
adb shell dmesg

# USB 网络 SSH
sudo ip addr add 172.16.42.2/24 dev usb0
ssh root@172.16.42.1
```

---

## 串口调试

### 硬件
- USB 转 TTL 串口模块（3.3V）
- TX: GPIO4, RX: GPIO5, GND: 任意 GND 测试点

### 软件
```bash
sudo picocom -b 115200 /dev/ttyUSB0
```

### 关键检查点
1. `Booting Linux on physical CPU`
2. `Machine model: Xiaomi Pad 8 Pro`
3. `console [ttyMSM0] enabled`
4. `VFS: Mounted root`

---

## 常见问题排查

### 黑屏无反应
```bash
file build/output/boot.img
abootimg -i build/output/boot.img
```
- 确认 cmdline 中 console 参数正确
- 尝试简化 cmdline：`console=ttyMSM0,115200n8`

### 找不到根文件系统
- 在 initramfs shell 中检查：`ls /dev/block/by-name/`
- 确认已刷 userdata 分区

### WiFi 不工作
- 检查固件：`ls /lib/firmware/ath12k/`
- 从安卓提取：`adb pull /vendor/firmware/ath12k/ firmware/wifi/`

---

## 救砖指南

### 能进 fastboot
```bash
fastboot flash boot boot_orig.img
fastboot reboot
```

### 能进 9008 (EDL)
1. 使用工程线进入 9008 模式
2. 使用 MiFlash 刷入原厂固件
3. 原厂固件：https://miuirom.org/tablets/xiaomi-pad-8-pro

---

## 命令速查

```bash
# 构建
./scripts/build.sh deps        # 安装依赖
./scripts/build.sh firmware    # 提取固件
./scripts/build.sh kernel      # 编译内核
./scripts/build.sh boot        # 构建 boot.img
./scripts/build.sh vbmeta      # 生成 vbmeta.img
./scripts/build.sh rootfs      # 构建 rootfs
./scripts/build.sh all         # 全部构建
./scripts/build.sh clean       # 清理

# fastboot
fastboot devices
fastboot flash boot boot.img
fastboot flash userdata rootfs.img
fastboot reboot

# ADB
adb devices
adb shell
adb push local remote
adb pull remote local
```
