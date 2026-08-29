#!/bin/bash
# =============================================================================
# DTB 提取与处理脚本 - Xiaomi Pad 8 Pro (piano / SM8750)
#
# 背景：
#   小米官方 piano-w-oss 内核源码中不包含 SM8750/piano 的设备树源文件
#   (arch/arm64/boot/dts/qcom/ 只有到 sm8550 的旧平台)。
#   DTB 存储在设备的 dtbo 分区中，需要从官方固件提取。
#
# 功能：
#   1. 从设备 dump dtbo 分区
#   2. 从官方固件解包 dtbo.img
#   3. 从 dtbo.img 中提取所有 DTB
#   4. 反编译 DTB 为 DTS（便于修改）
#   5. 重新编译 DTS 为 DTB
#   6. 列出 dtbo 中的所有 DTB 信息
#
# 使用方法：
#   chmod +x extract-dtb.sh
#
#   # 方式一：从已 root 的设备直接提取
#   ./extract-dtb.sh from-device
#
#   # 方式二：从官方固件的 dtbo.img 提取
#   ./extract-dtb.sh from-image dtbo.img
#
#   # 方式三：从 boot.img 提取（有些设备 DTB 在 boot.img 中）
#   ./extract-dtb.sh from-boot boot.img
#
#   # 列出 dtbo.img 中的所有 DTB 信息
#   ./extract-dtb.sh list dtbo.img
#
#   # 反编译某个 dtb 为 dts
#   ./extract-dtb.sh decompile piano.dtb piano.dts
#
#   # 编译 dts 为 dtb
#   ./extract-dtb.sh compile piano.dts piano.dtb
#
# 依赖：
#   - adb (从设备提取时需要)
#   - dtc (设备树编译器)
#   - python3 (解析 dtbo 镜像)
#   - abootimg 或 unpack_bootimg (解包 boot.img)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/dtb-extracted"

# =============================================================================
# 检查依赖
# =============================================================================
check_deps() {
    local missing=()

    command -v dtc &>/dev/null || missing+=("dtc (device-tree-compiler)")
    command -v python3 &>/dev/null || missing+=("python3")

    if [ ${#missing[@]} -gt 0 ]; then
        warn "缺少依赖: ${missing[*]}"
        info "安装依赖:"
        echo "  Ubuntu/Debian: sudo apt install device-tree-compiler python3 abootimg"
        echo "  Arch: sudo pacman -S dtc python3"
        echo ""
        read -p "是否继续？(部分功能可能不可用) [y/N]: " cont
        [ "${cont:-n}" = "y" ] || exit 1
    fi
}

# =============================================================================
# 从设备提取 dtbo 分区
# =============================================================================
extract_from_device() {
    info "=== 从设备提取 dtbo 分区 ==="

    command -v adb &>/dev/null || error "adb 未安装，请安装 android-tools"

    # 检查设备连接
    if ! adb get-state &>/dev/null; then
        error "未检测到设备，请连接设备并启用 USB 调试"
    fi

    DEVICE_MODEL=$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    DEVICE_CODENAME=$(adb shell getprop ro.product.device 2>/dev/null | tr -d '\r')
    ok "已连接设备: $DEVICE_MODEL ($DEVICE_CODENAME)"

    mkdir -p "$OUTPUT_DIR"

    # 查找 dtbo 分区
    info "查找 dtbo 分区..."
    DTBO_BLOCK=$(adb shell "ls -la /dev/block/by-name/dtbo 2>/dev/null || ls -la /dev/block/by-name/dtbo_a 2>/dev/null || echo NOT_FOUND" 2>/dev/null | tr -d '\r')

    if echo "$DTBO_BLOCK" | grep -q "NOT_FOUND"; then
        # 尝试通过其他方式查找
        warn "未找到 /dev/block/by-name/dtbo，尝试搜索..."
        DTBO_BLOCK=$(adb shell "find /dev/block -name '*dtbo*' 2>/dev/null | head -1" 2>/dev/null | tr -d '\r')
    fi

    if [ -z "$DTBO_BLOCK" ] || echo "$DTBO_BLOCK" | grep -q "No such"; then
        error "无法找到 dtbo 分区。请确认设备已 root 或使用 from-image 方式从固件提取"
    fi

    # 提取实际块设备路径
    DTBO_DEV=$(echo "$DTBO_BLOCK" | grep -oP '/dev/block/\S+' | head -1)
    info "dtbo 分区设备: $DTBO_DEV"

    # dump 分区
    info "正在 dump dtbo 分区..."
    adb shell "su -c 'dd if=$DTBO_DEV of=/sdcard/dtbo.img bs=4096'" 2>/dev/null || \
    adb shell "dd if=$DTBO_DEV of=/sdcard/dtbo.img bs=4096" 2>/dev/null || \
    error "dump 失败，可能需要 root 权限"

    # 拉取到电脑
    adb pull /sdcard/dtbo.img "$OUTPUT_DIR/dtbo.img"
    adb shell "rm -f /sdcard/dtbo.img"

    ok "dtbo.img 已保存到: $OUTPUT_DIR/dtbo.img"
    ls -lh "$OUTPUT_DIR/dtbo.img"

    # 继续提取 DTB
    extract_from_dtbo_image "$OUTPUT_DIR/dtbo.img"
}

# =============================================================================
# 从 dtbo.img 提取所有 DTB
# =============================================================================
extract_from_dtbo_image() {
    local DTBO_IMG="${1:-}"

    if [ -z "$DTBO_IMG" ] || [ ! -f "$DTBO_IMG" ]; then
        error "请提供有效的 dtbo.img 文件路径"
    fi

    info "=== 从 dtbo.img 提取 DTB ==="
    info "输入文件: $DTBO_IMG"

    mkdir -p "$OUTPUT_DIR/dtbs"
    mkdir -p "$OUTPUT_DIR/dts"

    # 使用 Python 解析 dtbo 镜像格式
    # 高通 dtbo 镜像格式：
    #   头部 (32 bytes): magic(4) + version(4) + dtbo_total_size(4) +
    #                    num_dtbs(4) + dtbo_offset(4) + page_size(4) +
    #                    reserved(8)
    #   然后是每个 DTB 的表项 (32 bytes each):
    #     dt_size(4) + dt_offset(4) + id(4) + rev(4) + custom[4](16)
    #   然后是 DTB 数据

    info "解析 dtbo 镜像..."

    python3 << 'PYEOF'
import struct
import sys
import os

dtbo_path = sys.argv[1] if len(sys.argv) > 1 else "dtbo.img"
output_dir = sys.argv[2] if len(sys.argv) > 2 else "dtb-extracted/dtbs"

os.makedirs(output_dir, exist_ok=True)

with open(dtbo_path, "rb") as f:
    data = f.read()

# 尝试解析标准 dtbo 头部
magic = struct.unpack_from("<I", data, 0)[0]

if magic == 0x11111111:  # DTBO magic
    version = struct.unpack_from("<I", data, 4)[0]
    dtbo_total_size = struct.unpack_from("<I", data, 8)[0]
    num_dtbs = struct.unpack_from("<I", data, 12)[0]
    dtbo_offset = struct.unpack_from("<I", data, 16)[0]
    page_size = struct.unpack_from("<I", data, 20)[0]

    print(f"DTBO Header:")
    print(f"  Magic: 0x{magic:08x}")
    print(f"  Version: {version}")
    print(f"  Total size: {dtbo_total_size}")
    print(f"  Number of DTBs: {num_dtbs}")
    print(f"  DTBO offset: {dtbo_offset}")
    print(f"  Page size: {page_size}")
    print()

    # 解析每个 DTB 表项
    for i in range(num_dtbs):
        entry_offset = 32 + i * 32
        if entry_offset + 32 > len(data):
            break

        dt_size = struct.unpack_from("<I", data, entry_offset)[0]
        dt_offset = struct.unpack_from("<I", data, entry_offset + 4)[0]
        dt_id = struct.unpack_from("<I", data, entry_offset + 8)[0]
        dt_rev = struct.unpack_from("<I", data, entry_offset + 12)[0]

        print(f"DTB [{i}]:")
        print(f"  Size: {dt_size} bytes")
        print(f"  Offset: {dt_offset}")
        print(f"  ID: {dt_id}")
        print(f"  Revision: {dt_rev}")

        # 提取 DTB 数据
        dtb_data = data[dt_offset:dt_offset + dt_size]

        # 尝试从 DTB 中读取 model 信息
        try:
            # DTB 结构: header(40 bytes) + memory reservation block +
            #           structure block + strings block
            dtb_magic = struct.unpack_from(">I", dtb_data, 0)[0]
            if dtb_magic == 0xd00dfeed:
                total_size = struct.unpack_from(">I", dtb_data, 4)[0]
                off_dt_struct = struct.unpack_from(">I", dtb_data, 12)[0]
                off_dt_strings = struct.unpack_from(">I", dtb_data, 16)[0]
                size_dt_strings = struct.unpack_from(">I", dtb_data, 20)[0]

                strings = dtb_data[off_dt_strings:off_dt_strings + size_dt_strings]

                # 在 structure block 中搜索 "model" 属性
                struct_data = dtb_data[off_dt_struct:]
                pos = 0
                model_found = False
                while pos < len(struct_data) - 4:
                    token = struct.unpack_from(">I", struct_data, pos)[0]
                    if token == 0x00000003:  # FDT_PROP
                        pos += 4
                        prop_len = struct.unpack_from(">I", struct_data, pos)[0]
                        pos += 4
                        nameoff = struct.unpack_from(">I", struct_data, pos)[0]
                        pos += 4

                        # 读取属性名
                        name_end = strings.find(b'\x00', nameoff)
                        prop_name = strings[nameoff:name_end].decode('ascii', errors='replace')

                        if prop_name == "model":
                            model_val = struct_data[pos:pos + prop_len].rstrip(b'\x00').decode('ascii', errors='replace')
                            print(f"  Model: {model_val}")
                            model_found = True
                            break

                        # 跳过属性值（4字节对齐）
                        pos += (prop_len + 3) & ~3
                    elif token == 0x00000001:  # FDT_BEGIN_NODE
                        pos += 4
                        # 跳过节点名
                        name_end = struct_data.find(b'\x00', pos)
                        if name_end == -1:
                            break
                        pos = name_end + 1
                        pos = (pos + 3) & ~3  # 4字节对齐
                    elif token == 0x00000002:  # FDT_END_NODE
                        pos += 4
                    elif token == 0x00000004:  # FDT_NOP
                        pos += 4
                    elif token == 0x00000009:  # FDT_END
                        break
                    else:
                        break

                if not model_found:
                    print(f"  Model: (not found in root node)")
        except Exception as e:
            print(f"  (error parsing DTB header: {e})")

        # 保存 DTB 文件
        out_name = f"dtb_{i:02d}.dtb"
        out_path = os.path.join(output_dir, out_name)
        with open(out_path, "wb") as out:
            out.write(dtb_data)
        print(f"  Saved: {out_path}")
        print()

else:
    # 不是标准 dtbo 格式，尝试作为原始 DTB 或包含多个 DTB 的镜像处理
    print(f"Not a standard DTBO image (magic=0x{magic:08x})")
    print("Trying to find DTB signatures in the image...")

    # DTB magic: 0xd00dfeed (big-endian)
    dtb_magic = b'\xd0\x0d\xfe\xed'
    count = 0
    pos = 0

    while True:
        pos = data.find(dtb_magic, pos)
        if pos == -1:
            break

        # 读取 DTB 总大小
        if pos + 8 <= len(data):
            total_size = struct.unpack_from(">I", data, pos + 4)[0]
            if 100 < total_size < 10 * 1024 * 1024:  # 合理的 DTB 大小范围
                dtb_data = data[pos:pos + total_size]

                out_name = f"dtb_{count:02d}_offset_{pos}.dtb"
                out_path = os.path.join(output_dir, out_name)
                with open(out_path, "wb") as out:
                    out.write(dtb_data)

                print(f"  Found DTB at offset {pos}, size {total_size}, saved to {out_path}")
                count += 1
                pos += total_size
                continue

        pos += 4

    if count == 0:
        print("No DTB found in the image.")
        print("The image might be compressed or in a different format.")
        sys.exit(1)

PYEOF

    ok "DTB 提取完成！文件保存在: $OUTPUT_DIR/dtbs/"
    ls -lh "$OUTPUT_DIR/dtbs/"

    # 自动反编译所有 DTB
    info "反编译 DTB 为 DTS..."
    for dtb in "$OUTPUT_DIR/dtbs/"*.dtb; do
        [ -f "$dtb" ] || continue
        dts_name=$(basename "$dtb" .dtb).dts
        dtc -I dtb -O dts -o "$OUTPUT_DIR/dts/$dts_name" "$dtb" 2>/dev/null && \
            ok "  $(basename "$dtb") -> $dts_name" || \
            warn "  反编译 $(basename "$dtb") 失败"
    done

    ok "DTS 文件保存在: $OUTPUT_DIR/dts/"

    # 提示用户选择正确的 DTB
    echo ""
    info "=== 下一步 ==="
    echo "1. 查看提取的 DTB 信息，找到对应 piano 的 DTB"
    echo "   cat $OUTPUT_DIR/dts/dtb_00.dts | head -30"
    echo ""
    echo "2. 将正确的 DTB 复制到设备包目录"
    echo "   cp $OUTPUT_DIR/dtbs/dtb_XX.dtb $SCRIPT_DIR/device-xiaomi-piano/piano.dtb"
    echo ""
    echo "3. 修改 deviceinfo 中的 deviceinfo_dtb 字段"
    echo "   deviceinfo_dtb=\"piano\""
}

# =============================================================================
# 从 boot.img 提取 DTB
# =============================================================================
extract_from_boot() {
    local BOOT_IMG="${1:-}"

    if [ -z "$BOOT_IMG" ] || [ ! -f "$BOOT_IMG" ]; then
        error "请提供有效的 boot.img 文件路径"
    fi

    info "=== 从 boot.img 提取 DTB ==="

    mkdir -p "$OUTPUT_DIR/boot-unpacked"

    # 尝试用 unpack_bootimg (Google 官方工具)
    if command -v unpack_bootimg &>/dev/null; then
        info "使用 unpack_bootimg 解包..."
        unpack_bootimg --boot_img "$BOOT_IMG" --out "$OUTPUT_DIR/boot-unpacked"
    elif command -v abootimg &>/dev/null; then
        info "使用 abootimg 解包..."
        cd "$OUTPUT_DIR/boot-unpacked"
        abootimg -x "$BOOT_IMG" 2>/dev/null || warn "abootimg 解包部分失败"
        cd "$SCRIPT_DIR"
    else
        # 使用 Python 手动解析 Android boot image
        info "使用 Python 解析 boot.img..."
        python3 << PYEOF
import struct
import os

boot_path = "$BOOT_IMG"
out_dir = "$OUTPUT_DIR/boot-unpacked"
os.makedirs(out_dir, exist_ok=True)

with open(boot_path, "rb") as f:
    data = f.read()

# Android boot image header
magic = data[:8]
print(f"Magic: {magic}")

if magic[:4] == b'ANDR' or magic[:4] == b'ANDR':
    # 解析头部
    kernel_size = struct.unpack_from("<I", data, 8)[0]
    kernel_addr = struct.unpack_from("<I", data, 12)[0]
    ramdisk_size = struct.unpack_from("<I", data, 16)[0]
    ramdisk_addr = struct.unpack_from("<I", data, 20)[0]
    second_size = struct.unpack_from("<I", data, 24)[0]
    second_addr = struct.unpack_from("<I", data, 28)[0]
    tags_addr = struct.unpack_from("<I", data, 32)[0]
    page_size = struct.unpack_from("<I", data, 36)[0]
    dt_size = struct.unpack_from("<I", data, 40)[0] if len(data) > 44 else 0

    print(f"Kernel size: {kernel_size}")
    print(f"Ramdisk size: {ramdisk_size}")
    print(f"Second size: {second_size}")
    print(f"Page size: {page_size}")
    print(f"DTB size: {dt_size}")

    # 计算各部分偏移
    kernel_offset = page_size
    ramdisk_offset = kernel_offset + ((kernel_size + page_size - 1) // page_size) * page_size
    second_offset = ramdisk_offset + ((ramdisk_size + page_size - 1) // page_size) * page_size
    dtb_offset = second_offset + ((second_size + page_size - 1) // page_size) * page_size

    # 保存各部分
    with open(os.path.join(out_dir, "kernel"), "wb") as f:
        f.write(data[kernel_offset:kernel_offset + kernel_size])

    with open(os.path.join(out_dir, "ramdisk.gz"), "wb") as f:
        f.write(data[ramdisk_offset:ramdisk_offset + ramdisk_size])

    if dt_size > 0:
        with open(os.path.join(out_dir, "dtb"), "wb") as f:
            f.write(data[dtb_offset:dtb_offset + dt_size])
        print(f"DTB saved to {out_dir}/dtb")
    else:
        print("No DTB in boot image header (might be in vendor_boot or dtbo partition)")
else:
    print("Not a standard Android boot image")
PYEOF
    fi

    # 检查是否提取到 DTB
    if [ -f "$OUTPUT_DIR/boot-unpacked/dtb" ]; then
        cp "$OUTPUT_DIR/boot-unpacked/dtb" "$OUTPUT_DIR/dtbs/from-boot.dtb"
        ok "从 boot.img 提取到 DTB: $OUTPUT_DIR/dtbs/from-boot.dtb"
    else
        warn "boot.img 中没有 DTB（SM8750 设备的 DTB 通常在 dtbo 分区）"
        info "请使用 from-device 或 from-image 方式从 dtbo 分区提取"
    fi
}

# =============================================================================
# 列出 dtbo.img 中的 DTB 信息
# =============================================================================
list_dtbo() {
    local DTBO_IMG="${1:-}"
    [ -z "$DTBO_IMG" ] && error "请提供 dtbo.img 路径"
    [ ! -f "$DTBO_IMG" ] && error "文件不存在: $DTBO_IMG"

    python3 -c "
import struct
import sys

with open('$DTBO_IMG', 'rb') as f:
    data = f.read()

magic = struct.unpack_from('<I', data, 0)[0]
if magic == 0x11111111:
    num_dtbs = struct.unpack_from('<I', data, 12)[0]
    print(f'DTBO contains {num_dtbs} DTB(s):')
    print()
    for i in range(num_dtbs):
        entry = 32 + i * 32
        dt_size = struct.unpack_from('<I', data, entry)[0]
        dt_offset = struct.unpack_from('<I', data, entry + 4)[0]
        dt_id = struct.unpack_from('<I', data, entry + 8)[0]
        dt_rev = struct.unpack_from('<I', data, entry + 12)[0]
        print(f'  [{i}] size={dt_size:8d}  offset=0x{dt_offset:08x}  id={dt_id}  rev={dt_rev}')
else:
    print(f'Not a standard DTBO (magic=0x{magic:08x})')
"
}

# =============================================================================
# 反编译 DTB 为 DTS
# =============================================================================
decompile_dtb() {
    local DTB="${1:-}"
    local DTS="${2:-}"

    [ -z "$DTB" ] && error "请输入 dtb 文件路径"
    [ ! -f "$DTB" ] && error "文件不存在: $DTB"
    [ -z "$DTS" ] && DTS="${DTB%.dtb}.dts"

    info "反编译: $DTB -> $DTS"
    dtc -I dtb -O dts -o "$DTS" "$DTB"
    ok "完成: $DTS"
    wc -l "$DTS"
}

# =============================================================================
# 编译 DTS 为 DTB
# =============================================================================
compile_dts() {
    local DTS="${1:-}"
    local DTB="${2:-}"

    [ -z "$DTS" ] && error "请输入 dts 文件路径"
    [ ! -f "$DTS" ] && error "文件不存在: $DTS"
    [ -z "$DTB" ] && DTB="${DTS%.dts}.dtb"

    info "编译: $DTS -> $DTB"
    dtc -I dts -O dtb -o "$DTB" "$DTS"
    ok "完成: $DTB"
    ls -lh "$DTB"
}

# =============================================================================
# 帮助
# =============================================================================
do_help() {
    cat << EOF
DTB 提取与处理脚本 - Xiaomi Pad 8 Pro (piano / SM8750)

用法: $0 <命令> [参数]

命令:
  from-device              从已连接设备提取 dtbo 分区并解包
  from-image <dtbo.img>   从官方固件的 dtbo.img 提取所有 DTB
  from-boot <boot.img>    从 boot.img 提取 DTB
  list <dtbo.img>         列出 dtbo.img 中的所有 DTB 信息
  decompile <dtb> [dts]   反编译 DTB 为 DTS
  compile <dts> [dtb]     编译 DTS 为 DTB
  help                     显示此帮助

示例:
  # 从设备提取（推荐）
  $0 from-device

  # 从固件提取
  $0 from-image dtbo.img

  # 列出 dtbo 内容
  $0 list dtbo.img

  # 反编译/编译
  $0 decompile piano.dtb piano.dts
  $0 compile piano.dts piano.dtb

输出目录: $OUTPUT_DIR/
  dtbs/  - 提取的 DTB 文件
  dts/   - 反编译的 DTS 文件

注意:
  - SM8750 设备的 DTB 在 dtbo 分区，不在内核源码中
  - 提取后需要找到对应 piano 的 DTB（查看 model 字段）
  - 将正确的 DTB 放到 device-xiaomi-piano/ 目录
  - 修改 deviceinfo 中的 deviceinfo_dtb 字段

EOF
}

# =============================================================================
# 主入口
# =============================================================================
main() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        from-device)    check_deps; extract_from_device "$@" ;;
        from-image)     check_deps; extract_from_dtbo_image "$@" ;;
        from-boot)      check_deps; extract_from_boot "$@" ;;
        list)           check_deps; list_dtbo "$@" ;;
        decompile)      check_deps; decompile_dtb "$@" ;;
        compile)        check_deps; compile_dts "$@" ;;
        help|-h|--help) do_help ;;
        *)
            error "未知命令: $cmd\n运行 $0 help 查看帮助"
            ;;
    esac
}

main "$@"
