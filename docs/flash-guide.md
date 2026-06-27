# Xiaomi Pad 8 Pro — 备份与恢复指南

## 备份原厂分区

```bash
adb devices  # 确认设备连接

# 备份 vbmeta
adb shell su -c "dd if=/dev/block/by-name/vbmeta of=/sdcard/vbmeta_stock.img"
adb pull /sdcard/vbmeta_stock.img ./vbmeta_stock.img

# 备份 boot (A 槽)
adb shell su -c "dd if=/dev/block/by-name/boot_a of=/sdcard/boot_a_stock.img"
adb pull /sdcard/boot_a_stock.img ./boot_a_stock.img

# 备份 dtbo (A 槽)
adb shell su -c "dd if=/dev/block/by-name/dtbo_a of=/sdcard/dtbo_a_stock.img"
adb pull /sdcard/dtbo_a_stock.img ./dtbo_a_stock.img

# 验证
ls -lh vbmeta_stock.img boot_a_stock.img dtbo_a_stock.img
```

## 刷入 Linux 测试（方案 C，不刷 rootfs）

```bash
adb reboot bootloader

fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img
fastboot flash boot_b boot.img
fastboot set_active b
fastboot reboot
```

串口参数：115200n8，ttyMSM0

## 恢复安卓

```bash
adb reboot bootloader

fastboot flash vbmeta vbmeta_stock.img
fastboot flash boot_a boot_a_stock.img
fastboot flash dtbo_a dtbo_a_stock.img
fastboot set_active a
fastboot reboot
```
