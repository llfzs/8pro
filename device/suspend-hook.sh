#!/bin/sh
# Suspend/resume hook for Xiaomi Pad 8 Pro
# Disables/enables display around suspend to prevent glitches

case "$1" in
	hibernate|suspend)
		# Turn off backlight
		echo 0 > /sys/class/backlight/*/brightness 2>/dev/null
		;;
	thaw|resume)
		# Restore backlight
		echo 2048 > /sys/class/backlight/*/brightness 2>/dev/null
		# Reset touchscreen
		echo 1 > /sys/class/i2c-dev/i2c-8/device/8-0038/reset 2>/dev/null
		;;
esac
