#!/bin/sh
# /etc/pm/sleep.d/20-xiaomi-pad8pro-suspend
# Xiaomi Pad 8 Pro 休眠/唤醒外设复位钩子

case "$1" in
    pre)
        # 进入休眠前：关闭触控、WiFi、节省功耗
        echo "0" > /sys/class/backlight/backlight/bl_power
        modprobe -r ath12k_pci || true
        ;;
    post)
        # 唤醒后：恢复背光、重新加载无线驱动
        echo "0" > /sys/class/backlight/backlight/bl_power
        modprobe ath12k_pci || true
        # 触发触摸屏重新初始化
        echo 1 > /sys/bus/i2c/devices/0-0038/reset
        sleep 0.1
        echo 0 > /sys/bus/i2c/devices/0-0038/reset
        ;;
esac