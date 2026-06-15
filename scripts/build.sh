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

# 在非 root 环境下尝试使用 sudo（若没有 sudo 则在需要时给出提示）
SUDO_CMD=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO_CMD="sudo"
    else
        SUDO_CMD=""
    fi
fi

# ─── 固件 ─────────────────────────────────────────────────
extract_firmware() {
    local FW="$BUILD/firmware"
    local SRC="$DIR/firmware"
    mkdir -p "$FW"/{wifi,gpu,bt}

    # 优先用项目根目录下已有的固件
    if [ -d "$SRC" ] && ls "$SRC"/wifi/* &>/dev/null 2>&1; then
        log "使用项目中的固件 ($SRC)"
        [ -d "$SRC/wifi" ] && cp -a "$SRC/wifi/"* "$FW/wifi/" 2>/dev/null || true
        [ -d "$SRC/gpu" ]  && cp -a "$SRC/gpu/"*  "$FW/gpu/"  2>/dev/null || true
        [ -d "$SRC/bt" ]   && cp -a "$SRC/bt/"*   "$FW/bt/"   2>/dev/null || true
        return
    fi

    # 否则尝试从设备提取
    log "提取 WiFi/BT/GPU 固件..."
    if command -v adb &>/dev/null && adb devices 2>/dev/null | grep -q "device$"; then
        log "从设备提取固件 (ADB)..."
        for p in /lib/firmware/ath12k /vendor/firmware/ath12k /firmware/image/ath12k; do
            adb pull "$p" "$FW/wifi/" 2>/dev/null && break
        done
        for f in a680_zap.mbn a680_sqe.fw; do
            adb pull "/lib/firmware/qcom/$f" "$FW/gpu/" 2>/dev/null || \
            adb pull "/vendor/firmware/qcom/$f" "$FW/gpu/" 2>/dev/null || true
        done
        for p in /lib/firmware/qca /vendor/firmware/qca; do
            adb pull "$p" "$FW/bt/" 2>/dev/null && break
        done
        log "固件提取完成"
    else
        warn "无固件，请将固件放入 firmware/ 目录："
        warn "  firmware/wifi/  ← ath12k/WCN7850 固件"
        warn "  firmware/bt/    ← qca 蓝牙固件"
        warn "  firmware/gpu/   ← qcom GPU 固件"
    fi
}

# ─── 1. 依赖 ───────────────────────────────────────────────
install_deps() {
    log "安装构建依赖..."
    if [ "${SKIP_DEPS:-0}" = "1" ]; then
        log "SKIP_DEPS=1，跳过依赖安装"
        return
    fi
    # 如果既不是 root 且没有 sudo，可提示用户以 sudo 运行
    if [ "$(id -u)" -ne 0 ] && [ -z "${SUDO_CMD}" ]; then
        err "需要 root 或 sudo 来安装依赖。请使用 'sudo ./scripts/build.sh deps' 或在 CI 中设置 SKIP_DEPS=1。"
    fi
    ${SUDO_CMD} apt-get update -qq
    ${SUDO_CMD} apt-get install -y -qq \
        gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
        device-tree-compiler bc bison flex libssl-dev \
        python3 python3-pip wget curl cpio gzip \
        qemu-user-static e2fsprogs parted xz-utils \
        2>/dev/null
    # 在需要时使用 sudo 安装 python 包（若有 sudo）
    if [ -n "${SUDO_CMD}" ]; then
        ${SUDO_CMD} pip3 install pmbootstrap 2>/dev/null || true
    else
        pip3 install --user pmbootstrap 2>/dev/null || true
    fi
    log "依赖就绪"
}

# ─── 2. 内核 ───────────────────────────────────────────────
build_kernel() {
    log "下载并编译 Linux 内核..."
    local KSRC="$BUILD/linux"

    if [ ! -d "$KSRC" ]; then
        git clone --depth=1 -b v6.12 \
            https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git "$KSRC"
    fi

    # 拷贝设备树
    cp "$DIR/dt/xiaomi,pad8pro.dts" "$KSRC/arch/arm64/boot/dts/qcom/"
    grep -q "xiaomi,pad8pro" "$KSRC/arch/arm64/boot/dts/qcom/Makefile" 2>/dev/null || \
        echo 'dtb-$(CONFIG_ARCH_SM8750) += xiaomi,pad8pro.dtb' >> \
            "$KSRC/arch/arm64/boot/dts/qcom/Makefile"

    cd "$KSRC"

    # 配置
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig O="$BUILD/kout" 2>/dev/null || \
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- qcom_defconfig O="$BUILD/kout" 2>/dev/null || \
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- msm_defconfig O="$BUILD/kout"

    # 合并设备配置
    cat "$DIR/device/kernel.config.fragment" >> "$BUILD/kout/.config"
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig O="$BUILD/kout"

    # 编译
    log "编译内核 ($(nproc) jobs)..."
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) \
        Image dtbs modules O="$BUILD/kout"

    # 安装模块
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
        modules_install INSTALL_MOD_PATH="$BUILD/modules" O="$BUILD/kout"

    cp "$BUILD/kout/arch/arm64/boot/Image" "$BUILD/Image"
    cp "$BUILD/kout/arch/arm64/boot/dts/qcom/xiaomi,pad8pro.dtb" "$BUILD/" 2>/dev/null || \
        cp "$BUILD/kout/arch/arm64/boot/dts/qcom/"*.dtb "$BUILD/" 2>/dev/null || true

    cd "$DIR"
    log "内核编译完成"
}

# ─── 3. boot.img ──────────────────────────────────────────
build_boot() {
    log "构建 boot.img..."
    local KIMG="$BUILD/Image"
    local INITRAMFS="$BUILD/initramfs.gz"
    local DTB="$BUILD/xiaomi,pad8pro.dtb"

    [ ! -f "$KIMG" ] && err "内核 Image 不存在"

    # initramfs
    local INIT="$BUILD/initramfs-root"
    rm -rf "$INIT"
    mkdir -p "$INIT"/{bin,dev,etc,lib,mnt/rootfs,proc,sys}

    # busybox 静态二进制
    if [ ! -f "$BUILD/busybox" ]; then
        wget -q "https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox" \
            -O "$BUILD/busybox" 2>/dev/null || \
            cp /bin/busybox "$BUILD/busybox" 2>/dev/null || true
    fi
    [ -f "$BUILD/busybox" ] && cp "$BUILD/busybox" "$INIT/bin/busybox" && chmod +x "$INIT/bin/busybox"

    # 常用命令链接
    for cmd in sh mount umount mkdir cat echo ls modprobe switch_root; do
        ln -sf busybox "$INIT/bin/$cmd" 2>/dev/null || true
    done

    # 拷入内核模块
    [ -d "$BUILD/modules/lib/modules" ] && cp -a "$BUILD/modules/lib/modules" "$INIT/lib/"

    # 拷入固件到 initramfs
    if [ -d "$BUILD/firmware" ]; then
        mkdir -p "$INIT/lib/firmware"
        cp -a "$BUILD/firmware/wifi/"* "$INIT/lib/firmware/ath12k/" 2>/dev/null || true
        cp -a "$BUILD/firmware/gpu/"* "$INIT/lib/firmware/qcom/" 2>/dev/null || true
        cp -a "$BUILD/firmware/bt/"* "$INIT/lib/firmware/qca/" 2>/dev/null || true
    fi

    # init 脚本
    cat > "$INIT/init" <<'EOF'
#!/bin/sh
export PATH=/bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mount -t tmpfs tmpfs /run

# 加载模块（含 WiFi/BT）
for m in msm_drm phy_qcom_qmp_ufs ufs_qcom dwc3 ath12k_pci; do
    modprobe "$m" 2>/dev/null
done

# 等存储
for i in $(seq 1 30); do
    [ -b /dev/sda ] || [ -b /dev/sdb ] && break
    sleep 0.2
done

# 找 rootfs
ROOT=""
for p in /dev/sda2 /dev/sdb2 /dev/sda3 /dev/sdb3; do
    [ -b "$p" ] && ROOT="$p" && break
done

[ -z "$ROOT" ] && echo "no rootfs, dropping to shell" && exec /bin/sh

mount -t ext4 -o ro "$ROOT" /mnt/rootfs 2>/dev/null || \
mount -t f2fs -o ro "$ROOT" /mnt/rootfs 2>/dev/null || \
    { echo "mount failed"; exec /bin/sh; }

umount /proc /sys /dev /run 2>/dev/null
exec switch_root /mnt/rootfs /sbin/init
EOF
    chmod +x "$INIT/init"

    # 打包
    cd "$INIT"
    find . | cpio -o -H newc 2>/dev/null | gzip > "$BUILD/initramfs.gz"
    cd "$DIR"

    # 合并 Image + DTB
    cat "$KIMG" > "$BUILD/Image-dtb"
    [ -f "$DTB" ] && cat "$DTB" >> "$BUILD/Image-dtb"

    # 写 boot.img（Python mkbootimg）
    python3 - "$BUILD/Image-dtb" "$BUILD/initramfs.gz" "$OUT/boot.img" <<'PYEOF'
import struct, hashlib, sys

kernel_file, ramdisk_file, output = sys.argv[1], sys.argv[2], sys.argv[3]

with open(kernel_file, 'rb') as f: kernel = f.read()
with open(ramdisk_file, 'rb') as f: ramdisk = f.read()

page = 4096
def align(n): return ((n + page - 1) // page) * page

hdr = bytearray(page)
hdr[0:8] = b'ANDROID!'
struct.pack_into('<I', hdr, 8, len(kernel))
struct.pack_into('<I', hdr, 12, 0x00008000)  # kernel_addr
struct.pack_into('<I', hdr, 16, len(ramdisk))
struct.pack_into('<I', hdr, 20, 0x01000000)  # ramdisk_addr
struct.pack_into('<I', hdr, 32, 0x00000100)  # tags_addr
struct.pack_into('<I', hdr, 36, page)
struct.pack_into('<I', hdr, 40, 0)  # header_version
cmdline = b'console=ttyMSM0,115200n8 console=tty0 androidboot.hardware=qcom'
hdr[64:64+len(cmdline)] = cmdline
sha = hashlib.sha256(kernel + ramdisk).digest()
hdr[160:160+32] = sha

with open(output, 'wb') as f:
    f.write(bytes(hdr))
    f.write(kernel)
    f.write(b'\0' * (align(len(kernel)) - len(kernel)))
    f.write(ramdisk)
    f.write(b'\0' * (align(len(ramdisk)) - len(ramdisk)))

print(f"boot.img -> {output}")
PYEOF

    log "boot.img 就绪: $(du -h "$OUT/boot.img" | cut -f1)"
}

# ─── 4. rootfs.img ────────────────────────────────────────
build_rootfs() {
    log "构建 rootfs.img..."
    local RFS="$BUILD/rootfs"
    local IMG="$OUT/rootfs.img"
    local SIZE=2048  # 2GB

    rm -rf "$RFS"
    mkdir -p "$RFS"

    # 下载 Alpine minirootfs
    local TAR="$BUILD/alpine-minirootfs.tar.gz"
    if [ ! -f "$TAR" ]; then
        log "下载 Alpine Linux minirootfs..."
        wget -q "https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/aarch64/alpine-minirootfs-3.21.0-aarch64.tar.gz" \
            -O "$TAR" || err "下载失败，请检查网络"
    fi

    log "解压 rootfs..."
    tar -xzf "$TAR" -C "$RFS"

    # 拷入内核模块
    [ -d "$BUILD/modules/lib/modules" ] && cp -a "$BUILD/modules/lib/modules" "$RFS/lib/"

    # 拷入固件（WiFi/BT/GPU）
    if [ -d "$BUILD/firmware" ]; then
        log "拷入固件..."
        mkdir -p "$RFS/lib/firmware"
        cp -a "$BUILD/firmware/wifi/"* "$RFS/lib/firmware/ath12k/" 2>/dev/null || true
        cp -a "$BUILD/firmware/gpu/"* "$RFS/lib/firmware/qcom/" 2>/dev/null || true
        cp -a "$BUILD/firmware/bt/"* "$RFS/lib/firmware/qca/" 2>/dev/null || true
    fi

    # 基本配置
    echo "nameserver 8.8.8.8" > "$RFS/etc/resolv.conf"
    echo "pad8pro" > "$RFS/etc/hostname"
    cat > "$RFS/etc/fstab" <<EOF
/dev/sda2   /        ext4   defaults,noatime   0 1
tmpfs       /tmp     tmpfs  defaults,noatime   0 0
tmpfs       /run     tmpfs  defaults,noatime   0 0
EOF
    cat > "$RFS/etc/inittab" <<EOF
::sysinit:/sbin/openrc sysinit
::sysinit:/bin/mount -t proc proc /proc 2>/dev/null
::sysinit:/bin/mount -t devtmpfs devtmpfs /dev 2>/dev/null
::sysinit:/bin/mount -t tmpfs tmpfs /run 2>/dev/null
::sysinit:/bin/mount -t sysfs sysfs /sys 2>/dev/null

# 串口控制台
ttyMSM0::respawn:/sbin/agetty -L ttyMSM0 115200 vt100

# 屏幕控制台（framebuffer）
tty1::respawn:/sbin/agetty --noclear tty1 115200 linux

# 自动登录 root（开发用）
::once:/bin/login -f root
EOF

    # chroot 安装包（需要 qemu-aarch64-static）
    if [ -f /usr/bin/qemu-aarch64-static ]; then
        ${SUDO_CMD} cp /usr/bin/qemu-aarch64-static "$RFS/usr/bin/" 2>/dev/null || true
        log "chroot 安装系统包..."
        ${SUDO_CMD} chroot "$RFS" /bin/sh -c '
            export PATH=/usr/sbin:/usr/bin:/sbin:/bin
            apk update
            apk add --no-cache \
                openrc eudev kmod util-linux e2fsprogs \
                wireless-tools wpa_supplicant iw iproute2 dhcpcd \
                openssh bash vim htop mesa-dri-gallium alsa-utils \
                networkmanager 2>/dev/null
            rc-update add networking default 2>/dev/null
            rc-update add sshd default 2>/dev/null
            rc-update add udev sysinit 2>/dev/null
            rc-update add udev-trigger sysinit 2>/dev/null
            rc-update add networkmanager default 2>/dev/null
            echo "root:" | chpasswd -e
        ' 2>&1 | tail -5 || true
    else
        warn "无 qemu-aarch64-static，跳过 chroot，首次启动时安装"
    fi

    # 根据实际内容动态计算镜像大小，跳过权限不足目录
    local CONTENT_MB
    # --ignore-errors 忽略无法读取的目录，2>/dev/null 屏蔽警告
    CONTENT_MB=$(du -sm --ignore-errors "$RFS" 2>/dev/null | awk '{print $1}')
    local SIZE=$(( (CONTENT_MB * 120 / 100) + 64 ))
    [ "$SIZE" -lt 256 ] && SIZE=256
    log "rootfs 内容: ${CONTENT_MB}MB → 镜像大小: ${SIZE}MB"
    
    # 打包 img
    log "打包 rootfs.img (${SIZE}MB)..."
    dd if=/dev/zero of="$IMG" bs=1M count="$SIZE" status=none
    # 使用 sudo 创建文件系统以便设置权限/所有权（CI 环境通常需要）
    if [ -n "${SUDO_CMD}" ]; then
        ${SUDO_CMD} mkfs.ext4 -q -L rootfs -d "$RFS" "$IMG"
    else
        mkfs.ext4 -q -L rootfs -d "$RFS" "$IMG"
    fi

    log "rootfs.img 就绪: $(du -h "$IMG" | cut -f1)"
}

# ─── 主流程 ────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║    Xiaomi Pad 8 Pro - Linux 构建                    ║"
echo "║    输出: boot.img + rootfs.img                       ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

case "${1:-all}" in
    deps)     install_deps ;;
    firmware) extract_firmware ;;
    kernel)   build_kernel ;;
    boot)     build_boot ;;
    rootfs)   build_rootfs ;;
    all)
        install_deps
        extract_firmware
        build_kernel
        build_boot
        build_rootfs
        echo ""
        echo -e "${CYAN}═══ 构建完成 ═══${NC}"
        echo "  $OUT/boot.img    $(du -h "$OUT/boot.img" | cut -f1)"
        echo "  $OUT/rootfs.img  $(du -h "$OUT/rootfs.img" | cut -f1)"
        echo ""
        echo "刷入: fastboot flash boot $OUT/boot.img"
        echo "      fastboot flash userdata $OUT/rootfs.img"
        ;;
    clean)    rm -rf "$BUILD"; log "已清理" ;;
    *)        echo "用法: $0 {all|deps|kernel|boot|rootfs|clean}" ;;
esac
