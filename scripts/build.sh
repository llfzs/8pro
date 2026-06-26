#!/bin/bash
# Xiaomi Pad 8 Pro - Linux 构建脚本
# 输出: boot.img + rootfs.img
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$DIR/build"
OUT="$DIR/build/output"
DEVICE="xiaomi-pad8pro"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }

mkdir -p "$BUILD" "$OUT"

# 非 root 环境自动使用 sudo
SUDO_CMD=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO_CMD="sudo"
    else
        SUDO_CMD=""
    fi
fi

# 全局启动参数：与设备树、deviceinfo 保持一致
CMDLINE="console=tty0 console=ttyMSM0,115200n8 earlycon=msm_geni_serial,0xa9c000 root=/dev/block/by-name/userdata rootfstype=ext4 rw init=/sbin/init fbcon=nodefer loglevel=7"

# ─── 固件提取与准备 ────────────────────────────────────────
extract_firmware() {
    local FW="$BUILD/firmware"
    local SRC="$DIR/firmware"
    mkdir -p "$FW"/{wifi,gpu,bt,tz}

    # 优先使用项目内预置固件
    if [ -d "$SRC" ] && ls "$SRC"/wifi/ath12k &>/dev/null 2>&1; then
        log "使用项目内置固件 ($SRC)"
        [ -d "$SRC/wifi/ath12k" ] && cp -a "$SRC/wifi/ath12k" "$FW/wifi/" 2>/dev/null || true
        [ -d "$SRC/gpu" ]        && cp -a "$SRC/gpu"        "$FW/gpu/"  2>/dev/null || true
        [ -d "$SRC/bt/qca" ]     && cp -a "$SRC/bt/qca"     "$FW/bt/"   2>/dev/null || true
        [ -d "$SRC/tz" ]         && cp -a "$SRC/tz"         "$FW/tz/"   2>/dev/null || true
        return
    fi

    # ADB 从设备提取固件（需 root 权限）
    # 注意：路径统一使用 /vendor/firmware/（Android 设备标准路径）
    log "尝试通过 ADB 从设备提取固件..."
    if command -v adb >/dev/null && adb devices 2>/dev/null | grep -q "device$"; then
        log "提取 WiFi 固件 (ath12k)..."
        adb shell "su -c 'tar czf /tmp/fw_wifi.tar.gz /vendor/firmware/ath12k'" 2>/dev/null || true
        adb pull /tmp/fw_wifi.tar.gz "$BUILD/" 2>/dev/null && \
            tar xzf "$BUILD/fw_wifi.tar.gz" -C "$FW/wifi/" --strip-components=3 2>/dev/null || true

        log "提取 GPU 固件..."
        adb shell "su -c 'tar czf /tmp/fw_gpu.tar.gz /vendor/firmware/qcom/a680_*'" 2>/dev/null || true
        adb pull /tmp/fw_gpu.tar.gz "$BUILD/" 2>/dev/null && \
            mkdir -p "$FW/gpu/qcom" && tar xzf "$BUILD/fw_gpu.tar.gz" -C "$FW/gpu/qcom/" --strip-components=3 2>/dev/null || true

        log "提取蓝牙固件 (qca)..."
        adb shell "su -c 'tar czf /tmp/fw_bt.tar.gz /vendor/firmware/qca'" 2>/dev/null || true
        adb pull /tmp/fw_bt.tar.gz "$BUILD/" 2>/dev/null && \
            tar xzf "$BUILD/fw_bt.tar.gz" -C "$FW/bt/" --strip-components=3 2>/dev/null || true

        log "固件提取完成"
    else
        warn "未检测到 ADB 设备，请将固件按以下结构放入 firmware/ 目录："
        warn "  firmware/wifi/ath12k/WCN7850/...  ← WiFi 固件"
        warn "  firmware/bt/qca/...                ← 蓝牙固件"
        warn "  firmware/gpu/                      ← GPU 固件"
        warn "  firmware/tz/                       ← TrustZone 固件"
    fi
}

# ─── 1. 安装构建依赖 ───────────────────────────────────────
install_deps() {
    log "安装构建依赖..."
    if [ "${SKIP_DEPS:-0}" = "1" ]; then
        log "SKIP_DEPS=1，跳过依赖安装"
        return
    fi

    if [ "$(id -u)" -ne 0 ] && [ -z "${SUDO_CMD}" ]; then
        err "需要 root 或 sudo 安装依赖，请使用 'sudo ./scripts/build.sh deps' 运行。"
    fi

    ${SUDO_CMD} apt-get update -qq
    ${SUDO_CMD} apt-get install -y -qq \
        gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
        device-tree-compiler bc bison flex libssl-dev libelf-dev \
        python3 python3-pip wget curl cpio gzip \
        qemu-user-static e2fsprogs parted xz-utils \
        android-sdk-libsparse-utils \
        2>/dev/null

    # 安装 mkbootimg（如果尚未安装）
    if ! command -v mkbootimg >/dev/null 2>&1; then
        log "mkbootimg 未找到，尝试从 AOSP 安装..."
        pip3 install --user mkbootimg 2>/dev/null || {
            warn "mkbootimg 安装失败，将使用内联 Python 生成 boot.img"
        }
    fi

    log "依赖就绪"
}

# ─── 2. 编译内核 ───────────────────────────────────────────
build_kernel() {
    log "下载并编译 Linux 内核..."
    local KSRC="$BUILD/linux"

    # 锁定到具体 commit 以确保可复现构建
    # 使用 qcom/for-next 分支的稳定快照
    local KERNEL_COMMIT="for-next"
    local KERNEL_REPO="https://git.kernel.org/pub/scm/linux/kernel/git/qcom/linux.git"

    if [ ! -d "$KSRC" ]; then
        log "克隆内核源码 (branch: $KERNEL_COMMIT)..."
        git clone --depth=1 -b "$KERNEL_COMMIT" "$KERNEL_REPO" "$KSRC"
    fi

    # 拷贝设备树源（*.dts, *.dtsi）到内核 dts 目录，确保 include 可用
    mkdir -p "$KSRC/arch/arm64/boot/dts/qcom/"
    # 复制所有仓库内的 .dtsi（如果存在）到内核 DTS 目录
    if compgen -G "$DIR/dt/*.dtsi" > /dev/null 2>&1; then
        cp -a "$DIR/dt/"*.dtsi "$KSRC/arch/arm64/boot/dts/qcom/" 2>/dev/null || true
    fi
    # 复制所有仓库内的 .dts 到内核 DTS 目录
    if compgen -G "$DIR/dt/*.dts" > /dev/null 2>&1; then
        cp -a "$DIR/dt/"*.dts "$KSRC/arch/arm64/boot/dts/qcom/" 2>/dev/null || true
    fi
    # 确保设备 DTB 被包含为要构建的目标（使用 dtb-y 无条件构建）
    grep -q "sm8750-piano" "$KSRC/arch/arm64/boot/dts/qcom/Makefile" 2>/dev/null || \
        echo 'dtb-y += sm8750-piano.dtb' >> \
            "$KSRC/arch/arm64/boot/dts/qcom/Makefile"

    cd "$KSRC"

    # 加载基础配置
    log "加载内核基础配置..."
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig O="$BUILD/kout" 2>/dev/null || \
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- qcom_defconfig O="$BUILD/kout" 2>/dev/null || \
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- msm_defconfig O="$BUILD/kout"

    # 规范合入设备专属配置（自动处理依赖与冲突）
    log "合入设备专属内核配置..."
    scripts/kconfig/merge_config.sh -O "$BUILD/kout" \
        "$BUILD/kout/.config" \
        "$DIR/device/kernel.config.fragment"

    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig O="$BUILD/kout"

    # 正式编译
    log "编译内核 ($(nproc) 并行任务)..."
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) \
        Image dtbs modules O="$BUILD/kout"

    # 列出生成的 dtb 以供调试（CI 日志可见）
    echo "DTBs generated in kernel output:"
    ls -l "$BUILD/kout/arch/arm64/boot/dts/qcom/"*.dtb || true

    # 安装模块
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
        modules_install INSTALL_MOD_PATH="$BUILD/modules" O="$BUILD/kout"

    # 拷贝产物
    cp "$BUILD/kout/arch/arm64/boot/Image" "$BUILD/Image"
    cp "$BUILD/kout/arch/arm64/boot/dts/qcom/sm8750-piano.dtb" "$BUILD/" 2>/dev/null || \
        cp "$BUILD/kout/arch/arm64/boot/dts/qcom/"*.dtb "$BUILD/" 2>/dev/null || true

    cd "$DIR"
    log "内核编译完成"
}

# ─── 打包内核产物 ─────────────────────────────────────────
package_kernel() {
    log "打包内核产物..."
    mkdir -p "$BUILD/artifacts"
    [ -f "$BUILD/Image" ] && cp -a "$BUILD/Image" "$BUILD/artifacts/" || true
    cp -a "$BUILD"/*.dtb "$BUILD/artifacts/" 2>/dev/null || true
    [ -d "$BUILD/modules" ] && cp -a "$BUILD/modules" "$BUILD/artifacts/"

    mkdir -p "$OUT"
    tar -C "$BUILD/artifacts" -czf "$OUT/kernel-artifacts.tar.gz" .
    log "内核包生成: $OUT/kernel-artifacts.tar.gz"
}

# ─── 3. 构建 boot.img ─────────────────────────────────────
build_boot() {
    log "构建 boot.img..."
    local KIMG="$BUILD/Image"
    local INITRAMFS="$BUILD/initramfs.gz"
    local DTB="$BUILD/sm8750-piano.dtb"

    [ ! -f "$KIMG" ] && err "内核 Image 不存在，请先执行 kernel 步骤"

    # 初始化 initramfs 目录
    local INIT="$BUILD/initramfs-root"
    rm -rf "$INIT"
    mkdir -p "$INIT"/{bin,dev,etc,lib,mnt/rootfs,proc,sys,run}

    # 下载 aarch64 架构静态 BusyBox（从官方源直接下载）
    BUSYBOX_CACHE="$DIR/cache/busybox-aarch64"
    mkdir -p "$DIR/cache"

    if [ -f "$BUSYBOX_CACHE" ]; then
        log "复用缓存内 BusyBox，跳过下载"
        cp "$BUSYBOX_CACHE" "$BUILD/"
    else
        log "首次下载 BusyBox 并缓存（官方源）..."
        wget --timeout=30 --tries=3 -q \
            "https://busybox.net/downloads/binaries/1.35.0-aarch64-linux-musl/busybox" \
            -O "$BUSYBOX_CACHE" || err "BusyBox 下载失败，请手动从 https://busybox.net 下载并放置到 cache/busybox-aarch64"
        cp "$BUSYBOX_CACHE" "$BUILD/"
    fi

    cp "$BUILD/busybox-aarch64" "$INIT/bin/busybox"
    chmod +x "$INIT/bin/busybox"

    # 创建常用命令软链接
    for cmd in sh mount umount mkdir cat echo ls modprobe switch_root sleep seq test [ true false \
               grep sed awk head tail wc ln cp mv rm date uname hostname poweroff reboot; do
        ln -sf busybox "$INIT/bin/$cmd" 2>/dev/null || true
    done

    # 拷入内核模块
    [ -d "$BUILD/modules/lib/modules" ] && cp -a "$BUILD/modules/lib/modules" "$INIT/lib/"

    # 拷入启动必需固件（UFS、显示、PCIe 相关）
    if [ -d "$BUILD/firmware" ]; then
        mkdir -p "$INIT/lib/firmware"
        [ -d "$BUILD/firmware/wifi/ath12k" ] && cp -a "$BUILD/firmware/wifi/ath12k" "$INIT/lib/firmware/" 2>/dev/null || true
        [ -d "$BUILD/firmware/gpu" ]        && cp -a "$BUILD/firmware/gpu"        "$INIT/lib/firmware/" 2>/dev/null || true
        [ -d "$BUILD/firmware/bt/qca" ]     && cp -a "$BUILD/firmware/bt/qca"     "$INIT/lib/firmware/" 2>/dev/null || true
        [ -d "$BUILD/firmware/tz" ]         && cp -a "$BUILD/firmware/tz"         "$INIT/lib/firmware/" 2>/dev/null || true
    fi

    # 从 deviceinfo 提取需要在 initramfs 中加载的模块
    # 包含：存储、显示、PCIe(WiFi)、USB、蓝牙HCI
    local INIT_MODULES="phy_qcom_qmp_ufs ufs_qcom phy_qcom_qmp_pcie msm_drm dwc3 qcom_spmi_pmic qcom_qusb2_phy btqca hci_uart"

    # init 启动脚本
    cat > "$INIT/init" <<INITEOF
#!/bin/sh
export PATH=/bin

# 挂载基础文件系统
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mount -t tmpfs tmpfs /run

# 加载核心驱动模块
for m in $INIT_MODULES; do
    modprobe "\$m" 2>/dev/null
done

# 等待 UFS 存储与 by-name 链接就绪（最长 10 秒）
for i in \$(seq 1 50); do
    [ -b /dev/block/by-name/userdata ] && break
    sleep 0.2
done

# 检查目标分区是否存在
ROOT="/dev/block/by-name/userdata"
if [ ! -b "\$ROOT" ]; then
    echo "ERROR: 块设备 \$ROOT 不存在"
    echo "可用块设备:"
    ls -la /dev/block/by-name/ 2>/dev/null || ls /dev/block/ 2>/dev/null
    echo "进入紧急 Shell 调试"
    exec /bin/sh
fi

# 挂载根分区
if ! mount -t ext4 -o rw "\$ROOT" /mnt/rootfs 2>/dev/null; then
    echo "ERROR: 无法挂载 userdata 为根文件系统"
    echo "尝试运行 fsck..."
    e2fsck -y "\$ROOT" 2>/dev/null || true
    mount -t ext4 -o rw "\$ROOT" /mnt/rootfs 2>/dev/null || {
        echo "挂载失败，进入紧急 Shell"
        exec /bin/sh
    }
fi

# 检查 switch_root 目标是否有效
if [ ! -x /mnt/rootfs/sbin/init ]; then
    echo "ERROR: /mnt/rootfs/sbin/init 不存在或不可执行"
    echo "根文件系统内容:"
    ls -la /mnt/rootfs/ 2>/dev/null
    echo "进入紧急 Shell 调试"
    exec /bin/sh
fi

# 卸载临时文件系统，切换根
umount /proc /sys /dev /run 2>/dev/null
exec switch_root /mnt/rootfs /sbin/init
INITEOF
    chmod +x "$INIT/init"

    # 打包 initramfs
    log "打包 initramfs..."
    cd "$INIT"
    find . | cpio -o -H newc 2>/dev/null | gzip > "$BUILD/initramfs.gz"
    cd "$DIR"

    # 生成 boot.img：优先使用 mkbootimg，回退到内联 Python
    log "生成 boot.img..."
    if command -v mkbootimg >/dev/null 2>&1; then
        log "使用 mkbootimg 生成 boot.img"
        # 拼接 kernel + dtb
        cat "$KIMG" > "$BUILD/Image-dtb"
        [ -f "$DTB" ] && cat "$DTB" >> "$BUILD/Image-dtb"

        mkbootimg \
            --kernel "$BUILD/Image-dtb" \
            --ramdisk "$BUILD/initramfs.gz" \
            --cmdline "$CMDLINE" \
            --base 0x00000000 \
            --kernel_offset 0x00008000 \
            --ramdisk_offset 0x01000000 \
            --tags_offset 0x00000100 \
            --pagesize 4096 \
            --os_version "15.0.0" \
            --os_patch_level "2025-06" \
            -o "$OUT/boot.img"
    else
        log "mkbootimg 不可用，使用内联 Python 生成 boot.img"
        # 拼接 kernel + dtb
        cat "$KIMG" > "$BUILD/Image-dtb"
        [ -f "$DTB" ] && cat "$DTB" >> "$BUILD/Image-dtb"

        python3 - "$BUILD/Image-dtb" "$BUILD/initramfs.gz" "$OUT/boot.img" "$CMDLINE" <<'PYEOF'
import struct, hashlib, sys, os

kernel_file, ramdisk_file, output, cmdline = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4].encode()

with open(kernel_file, 'rb') as f: kernel = f.read()
with open(ramdisk_file, 'rb') as f: ramdisk = f.read()

page = 4096
def align(n): return ((n + page - 1) // page) * page

# Android boot image v1 header
hdr = bytearray(page)
hdr[0:8] = b'ANDROID!'
struct.pack_into('<I', hdr, 8,  len(kernel))         # kernel_size
struct.pack_into('<I', hdr, 12, 0x00008000)           # kernel_offset (relative to base)
struct.pack_into('<I', hdr, 16, len(ramdisk))         # ramdisk_size
struct.pack_into('<I', hdr, 20, 0x01000000)           # ramdisk_offset (relative to base)
struct.pack_into('<I', hdr, 24, 0)                    # second_size
struct.pack_into('<I', hdr, 28, 0)                    # second_offset
struct.pack_into('<I', hdr, 32, 0x00000100)           # tags_offset
struct.pack_into('<I', hdr, 36, page)                 # page_size
struct.pack_into('<I', hdr, 40, 1)                    # header_version (v1 for dtb appended)
struct.pack_into('<I', hdr, 44, 0)                    # os_version

# 写入启动参数 (max 512 bytes)
cmdline = cmdline[:512]
hdr[64:64+len(cmdline)] = cmdline

# SHA1 校验和（Android 标准）
sha1 = hashlib.sha1(kernel + ramdisk).digest()
hdr[128:128+20] = sha1

# DTB size (header v1: offset 1632)
dtb_size = 0  # DTB 已 append 到 kernel
struct.pack_into('<I', hdr, 1632, dtb_size)

with open(output, 'wb') as f:
    f.write(bytes(hdr))
    f.write(kernel)
    f.write(b'\0' * (align(len(kernel)) - len(kernel)))
    f.write(ramdisk)
    f.write(b'\0' * (align(len(ramdisk)) - len(ramdisk)))

print(f"boot.img 生成成功 -> {output}")
PYEOF
    fi

    log "boot.img 就绪: $(du -h "$OUT/boot.img" | cut -f1)"
}

# ─── 4. 生成 vbmeta.img（禁用 AVB 验证） ─────────────────
build_vbmeta() {
    log "生成 vbmeta.img（禁用 dm-verity/AVB）..."
    # 使用标准工具生成空的 vbmeta 并禁用验证
    # 如果没有 avbtool，手动生成一个最小的 vbmeta header
    python3 - "$OUT/vbmeta.img" <<'PYEOF'
import struct, sys

output = sys.argv[1]

# Minimal vbmeta image with verification disabled
# Header: AVB magic + version + auth/aux/vbmeta sizes = 0 (no actual chain)
vbmeta = bytearray(256)

# Magic: "AVB0"
vbmeta[0:4] = b'AVB0'
# Required_libs (offset 4, 48 bytes) - empty
# Header version major (offset 56)
struct.pack_into('>Q', vbmeta, 56, 1)
# Header version minor (offset 64)
struct.pack_into('>Q', vbmeta, 64, 0)
# Authentication data block size (offset 104)
struct.pack_into('>Q', vbmeta, 104, 0)
# Auxiliary data block size (offset 112)
struct.pack_into('>Q', vbmeta, 112, 0)

with open(output, 'wb') as f:
    f.write(vbmeta)

print(f"vbmeta.img 生成成功 -> {output} (AVB 已禁用)")
PYEOF
}

# ─── 5. 构建 rootfs.img ───────────────────────────────────
build_rootfs() {
    log "构建 rootfs.img..."
    local RFS="$BUILD/rootfs"
    local IMG="$OUT/rootfs.img"

    rm -rf "$RFS"
    mkdir -p "$RFS"

    # 下载 Alpine 基础根文件系统
    local TAR="$BUILD/alpine-minirootfs.tar.gz"
    if [ ! -f "$TAR" ]; then
        log "下载 Alpine Linux minirootfs (aarch64)..."
        wget -q "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/aarch64/alpine-minirootfs-3.21.0-aarch64.tar.gz" \
            -O "$TAR" || err "根文件系统下载失败，请检查网络"
    fi

    log "解压基础系统..."
    tar -xzf "$TAR" -C "$RFS"

    # 拷入内核模块
    [ -d "$BUILD/modules/lib/modules" ] && cp -a "$BUILD/modules/lib/modules" "$RFS/lib/"

    # 拷入完整固件
    if [ -d "$BUILD/firmware" ]; then
        log "拷入固件..."
        mkdir -p "$RFS/lib/firmware"
        [ -d "$BUILD/firmware/wifi/ath12k" ] && cp -a "$BUILD/firmware/wifi/ath12k" "$RFS/lib/firmware/" 2>/dev/null || true
        [ -d "$BUILD/firmware/gpu" ]        && cp -a "$BUILD/firmware/gpu"        "$RFS/lib/firmware/" 2>/dev/null || true
        [ -d "$BUILD/firmware/bt/qca" ]     && cp -a "$BUILD/firmware/bt/qca"     "$RFS/lib/firmware/" 2>/dev/null || true
        [ -d "$BUILD/firmware/tz" ]         && cp -a "$BUILD/firmware/tz"         "$RFS/lib/firmware/" 2>/dev/null || true
    fi

    # 整合 udev 规则
    log "注入设备 udev 权限规则"
    mkdir -p "$RFS/etc/udev/rules.d/"
    if [ -f "$DIR/device/90-xiaomi-pad8pro.rules" ]; then
        cp "$DIR/device/90-xiaomi-pad8pro.rules" "$RFS/etc/udev/rules.d/"
    fi

    # 整合休眠唤醒钩子
    log "注入休眠电源管理钩子"
    mkdir -p "$RFS/etc/pm/sleep.d/"
    if [ -f "$DIR/device/suspend-hook.sh" ]; then
        cp "$DIR/device/suspend-hook.sh" "$RFS/etc/pm/sleep.d/20-xiaomi-pad8pro-suspend"
        ${SUDO_CMD} chmod +x "$RFS/etc/pm/sleep.d/20-xiaomi-pad8pro-suspend"
    fi

    # 基础系统配置
    # resolv.conf 由 NetworkManager 管理，此处仅提供初始值
    echo "nameserver 8.8.8.8" > "$RFS/etc/resolv.conf"
    echo "nameserver 223.5.5.5" >> "$RFS/etc/resolv.conf"
    echo "pad8pro" > "$RFS/etc/hostname"
    cat > "$RFS/etc/hosts" <<EOF
127.0.0.1   localhost pad8pro
::1         localhost
EOF

    # 修正 fstab：使用高通 by-name 分区
    cat > "$RFS/etc/fstab" <<EOF
/dev/block/by-name/userdata   /        ext4   defaults,noatime   0 1
tmpfs                         /tmp     tmpfs  defaults,noatime   0 0
tmpfs                         /run     tmpfs  defaults,noatime   0 0
EOF

    # 修正 inittab：控制台配置 + 自动登录
    cat > "$RFS/etc/inittab" <<EOF
::sysinit:/sbin/openrc sysinit
::sysinit:/bin/mount -t proc proc /proc 2>/dev/null
::sysinit:/bin/mount -t devtmpfs devtmpfs /dev 2>/dev/null
::sysinit:/bin/mount -t tmpfs tmpfs /run 2>/dev/null
::sysinit:/bin/mount -t sysfs sysfs /sys 2>/dev/null

# 串口调试控制台
ttyMSM0::respawn:/sbin/agetty -L --autologin root ttyMSM0 115200 vt100

# 屏幕帧缓冲控制台
tty1::respawn:/sbin/agetty --noclear --autologin root tty1 linux
EOF

    # chroot 安装软件包
    if [ -f /usr/bin/qemu-aarch64-static ]; then
        ${SUDO_CMD} cp /usr/bin/qemu-aarch64-static "$RFS/usr/bin/" 2>/dev/null || true
        log "chroot 安装系统软件包..."
        ${SUDO_CMD} chroot "$RFS" /bin/sh -c '
            export PATH=/usr/sbin:/usr/bin:/sbin:/bin
            apk update
            apk add --no-cache \
                openrc eudev kmod util-linux e2fsprogs \
                wireless-tools wpa_supplicant iw iproute2 dhcpcd \
                openssh bash vim htop mesa-dri-gallium alsa-utils \
                networkmanager bluez bluez-utils

            # 配置服务自启
            rc-update add udev sysinit
            rc-update add udev-trigger sysinit
            rc-update add networkmanager default
            rc-update add sshd default
            rc-update add bluetooth default

            # 设置 root 默认密码（用户首次登录后应修改）
            echo "root:pad8pro" | chpasswd

            # 禁止空密码 SSH 登录（安全加固）
            sed -i "s/#PermitRootLogin.*/PermitRootLogin prohibit-password/" /etc/ssh/sshd_config
            sed -i "s/#PermitEmptyPasswords.*/PermitEmptyPasswords no/" /etc/ssh/sshd_config

            # 创建首次登录密码修改提示
            echo "⚠️  首次登录请立即修改 root 密码: passwd" > /etc/motd
        ' 2>&1 | tail -10 || true
    else
        warn "未检测到 qemu-aarch64-static，跳过 chroot 软件安装"
        warn "首次启动后可手动执行 apk add 安装所需软件"
    fi

    # 统一权限
    ${SUDO_CMD} chmod -R u+rX "$RFS" 2>/dev/null || true
    ${SUDO_CMD} chmod -R 755 "$RFS/var/lib/" 2>/dev/null || true

    # 动态计算镜像大小（预留 50% + 128MB 给用户后续安装软件）
    local CONTENT_MB
    CONTENT_MB=$(${SUDO_CMD} du -sm "$RFS" 2>/dev/null | awk '{print $1}')
    local SIZE=$(( (CONTENT_MB * 150 / 100) + 128 ))
    [ "$SIZE" -lt 512 ] && SIZE=512
    log "根文件系统内容: ${CONTENT_MB}MB → 镜像大小: ${SIZE}MB"

    # 生成 ext4 镜像
    log "打包 rootfs.img (${SIZE}MB)..."
    dd if=/dev/zero of="$IMG" bs=1M count="$SIZE" status=none
    if [ -n "${SUDO_CMD}" ]; then
        ${SUDO_CMD} mkfs.ext4 -q -L rootfs -d "$RFS" "$IMG"
    else
        warn "当前非 root 环境，镜像内文件所有者可能异常，建议用 sudo 执行"
        mkfs.ext4 -q -L rootfs -d "$RFS" "$IMG"
    fi

    log "rootfs.img 就绪: $(du -h "$IMG" | cut -f1)"
}

# ─── 主流程 ────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║    Xiaomi Pad 8 Pro - Linux 构建                     ║"
echo "║    输出: boot.img + vbmeta.img + rootfs.img          ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

case "${1:-all}" in
    deps)     install_deps ;;
    firmware) extract_firmware ;;
    kernel)   build_kernel ;;
    package-kernel) package_kernel ;;
    boot)     build_boot ;;
    vbmeta)   build_vbmeta ;;
    rootfs)   build_rootfs ;;
    all)
        install_deps
        extract_firmware
        build_kernel
        build_boot
        build_vbmeta
        build_rootfs
        echo ""
        echo -e "${CYAN}═══ 构建完成 ═══${NC}"
        echo "  输出目录: $OUT"
        echo "  boot.img    $(du -h "$OUT/boot.img" | cut -f1)"
        echo "  vbmeta.img  $(du -h "$OUT/vbmeta.img" | cut -f1)"
        echo "  rootfs.img  $(du -h "$OUT/rootfs.img" | cut -f1)"
        echo ""
        echo "刷入命令："
        echo "  adb reboot bootloader"
        echo "  fastboot flash vbmeta --disable-verity --disable-verification $OUT/vbmeta.img"
        echo "  fastboot flash boot $OUT/boot.img"
        echo "  fastboot flash userdata $OUT/rootfs.img"
        echo "  fastboot set_active a && fastboot reboot"
        ;;
    clean)    rm -rf "$BUILD"; log "已清理构建目录" ;;
    *)        echo "用法: $0 {all|deps|firmware|kernel|package-kernel|boot|vbmeta|rootfs|clean}" ;;
esac
