# Xiaomi Pad 8 Pro - Linux 移植

SM8750-AB (Snapdragon 8 Elite) | postmarketOS 流程

## 构建

**GitHub Actions 自动构建（推荐）：**

push 到 `main` 分支或手动触发，Actions 自动编译内核 + 打包 rootfs，产物在 Actions → Artifacts 下载 `boot.img` 和 `rootfs.img`。

**本地构建：**

```bash
sudo ./scripts/build.sh all
```

## 输出

| 文件 | 说明 |
|------|------|
| `boot.img` | Linux 内核 + initramfs（屏幕+串口双控制台） |
| `rootfs.img` | Alpine Linux 根文件系统（含桌面基础包） |

## 刷入

```bash
adb reboot bootloader
fastboot flash boot boot.img
fastboot flash userdata rootfs.img
fastboot set_active a
fastboot reboot
```

## 屏幕输出

启动后屏幕会显示内核日志和登录提示（framebuffer console），同时串口 UART 也有输出。

## WiFi/蓝牙

构建时需通过 ADB 连接设备提取固件：
```bash
adb pull /lib/firmware/ath12k/ build/firmware/wifi/
adb pull /lib/firmware/qcom/   build/firmware/gpu/
```

## 前提

- 解锁 Bootloader（MiUnlockTool）
- x86_64 Linux 主机 或 GitHub Actions

## 驱动状态

| 组件 | 状态 |
|------|------|
| CPU | ✅ 主线支持 |
| UFS 存储 | ✅ |
| USB | ✅ |
| 屏幕显示 | ✅ framebuffer console |
| GPU (Adreno 830) | 🟡 freedreno |
| 触摸屏 | 🟡 需确认 IC |
| WiFi (WCN7850) | 🟡 需固件 |
| 蓝牙 | 🟡 需固件 |
| 传感器 | ✅ |
| 摄像头 | ❌ |
