# Xiaomi Pad 8 Pro — B 槽刷入指南

核心原则：只动 B 槽分区，A 槽安卓 100% 保留，随时 `fastboot set_active a` 切回。

## 前置准备：备份原厂分区

```bash
adb devices  # 确认设备连接且已 root

# 备份 vbmeta（恢复安卓 AVB 必须）
adb shell su -c "dd if=/dev/block/by-name/vbmeta_a of=/sdcard/vbmeta_a_stock.img"
adb pull /sdcard/vbmeta_a_stock.img .

# 备份 boot（A 槽原厂内核）
adb shell su -c "dd if=/dev/block/by-name/boot_a of=/sdcard/boot_a_stock.img"
adb pull /sdcard/boot_a_stock.img .

# 备份 dtbo（A 槽原厂设备树）
adb shell su -c "dd if=/dev/block/by-name/dtbo_a of=/sdcard/dtbo_a_stock.img"
adb pull /sdcard/dtbo_a_stock.img .

# 验证备份完整
ls -lh vbmeta_a_stock.img boot_a_stock.img dtbo_a_stock.img
```

## 第一步：最小测试（串口 + UFS，不刷 rootfs）

只测内核能否启动、串口是否有输出，不需要 rootfs（bootargs 为 `init=/bin/sh`）。

```bash
adb reboot bootloader

# 只禁用 B 槽 AVB，A 槽不受影响
fastboot flash vbmeta_b --disable-verity --disable-verification vbmeta.img

# 刷 Linux boot 到 B 槽
fastboot flash boot_b boot.img

# 切到 B 槽启动
fastboot set_active b
fastboot reboot
```

串口接线（UART14，GPIO 42/43），波特率 115200，观察是否有 earlycon 输出。

测试完毕切回安卓：
```bash
fastboot set_active a
fastboot reboot
```

## 第二步：完整系统测试（需要修改 boot.img cmdline）

当串口确认工作后，测试完整 Linux 系统。需要修改 boot.img 的 cmdline，把根分区从 userdata 改为 system_b。

### 1. 解包 boot.img

```bash
# 安装工具
sudo apt install android-tools-mkbootimg

# 解包
unpackbootimg -i boot.img -o /tmp/boot
```

### 2. 修改 cmdline

```bash
# 查看原始 cmdline
cat /tmp/boot/boot.img-cmdline

# 修改：root=/dev/block/by-name/userdata → root=/dev/block/by-name/system_b
sed -i 's|root=/dev/block/by-name/userdata|root=/dev/block/by-name/system_b|' /tmp/boot/boot.img-cmdline
```

### 3. 重新打包 boot_b.img

```bash
mkbootimg \
  --kernel /tmp/boot/boot.img-kernel \
  --ramdisk /tmp/boot/boot.img-ramdisk \
  --dtb /tmp/boot/boot.img-dtb \
  --cmdline "$(cat /tmp/boot/boot.img-cmdline)" \
  --base 0x00000000 \
  --kernel_offset 0x00008000 \
  --ramdisk_offset 0x01000000 \
  --tags_offset 0x00000100 \
  --pagesize 4096 \
  -o boot_b.img
```

### 4. 刷入

```bash
adb reboot bootloader

# B 槽 AVB（已在第一步刷过则跳过）
fastboot flash vbmeta_b --disable-verity --disable-verification vbmeta.img

# B 槽 boot（修改过 cmdline 的版本）
fastboot flash boot_b boot_b.img

# B 槽 system 分区作为 Linux rootfs
fastboot flash system_b rootfs.img

# 切到 B 槽启动
fastboot set_active b
fastboot reboot
```

### 5. 切回安卓

```bash
fastboot set_active a
fastboot reboot
```

A 槽的系统、数据、设置完全不变，无需重刷任何东西。

## 恢复原厂（如果 A 槽 AVB 被意外修改）

```bash
adb reboot bootloader
fastboot flash vbmeta_a vbmeta_a_stock.img
fastboot flash boot_a boot_a_stock.img
fastboot flash dtbo_a dtbo_a_stock.img
fastboot set_active a
fastboot reboot
```

## 注意事项

- **system 分区容量有限**（4~6GB），仅适合基础系统，后续可挂载 userdata 独立目录扩展
- **固件已内置**到 rootfs，不依赖安卓 vendor 分区
- **userdata 完全隔离**，此方案不写入 userdata，安卓数据完好
- **零变砖风险**：B 槽启动失败，切回 A 槽即可正常使用
