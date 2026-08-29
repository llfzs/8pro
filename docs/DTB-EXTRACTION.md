# DTB 提取指南 - Xiaomi Pad 8 Pro (piano / SM8750)

## 问题背景

小米官方 `piano-w-oss` 内核源码中**不包含** SM8750/piano 的设备树源文件：

```
arch/arm64/boot/dts/qcom/
├── Makefile
├── apq8016-sbc.dts
├── ... (旧平台文件)
├── sm8150-microsoft-surface-duo.dts
├── sm8350-mtp.dts
├── sm8450.dtsi
├── sm8550-mtp.dts
├── sm8550-qrd.dts
├── sm8550.dtsi
└── ... (没有 sm8750 或 piano 相关文件)
```

`MiCode/kernel_devicetree` 单独仓库目前也只有 `guitar-w-oss`（REDMI Pad 2 SE），piano 的设备树尚未发布。

**SM8750 设备的 DTB 存储在 `dtbo` 分区中**，需要从官方固件或运行中的设备提取。

## 提取方法

### 方法一：从已 root 的设备直接提取（推荐）

```bash
# 1. 连接设备，启用 USB 调试和 root
adb devices

# 2. 运行提取脚本
chmod +x extract-dtb.sh
./extract-dtb.sh from-device
```

脚本会自动：
- 查找 dtbo 分区（`/dev/block/by-name/dtbo`）
- dump 分区为 dtbo.img
- 解析 dtbo 镜像，提取所有 DTB
- 反编译为 DTS 便于查看

输出在 `dtb-extracted/` 目录：
```
dtb-extracted/
├── dtbo.img          # 原始 dtbo 镜像
├── dtbs/
│   ├── dtb_00.dtb
│   ├── dtb_01.dtb
│   └── ...
└── dts/
    ├── dtb_00.dts
    ├── dtb_01.dts
    └── ...
```

### 方法二：从官方固件提取

1. 下载官方固件：https://miuirom.org/tablets/xiaomi-pad-8-pro
2. 解压缩固件，找到 `dtbo.img`（通常在 `images/` 目录）
3. 运行提取脚本：

```bash
./extract-dtb.sh from-image /path/to/dtbo.img
```

### 方法三：从 TWRP/OFRP 备份提取

如果你已经刷了 TWRP/OFRP，可以在 recovery 中备份 dtbo 分区，然后提取。

## 识别正确的 DTB

dtbo.img 中可能包含多个 DTB（对应不同硬件版本/面板），需要找到对应 piano 的那个。

### 查看 DTB 信息

```bash
# 列出 dtbo 中的所有 DTB
./extract-dtb.sh list dtbo.img

# 查看某个 DTB 的 model 字段
head -30 dtb-extracted/dts/dtb_00.dts
```

正确的 DTB 应该包含：
```dts
/ {
    model = "Xiaomi Pad 8 Pro";
    compatible = "xiaomi,piano", "qcom,sm8750";
    ...
};
```

### 常见 DTB 类型

| DTB | 用途 |
|-----|------|
| dtb_00 | 主设备树（通常是这个） |
| dtb_01 | 不同面板版本 |
| dtb_02 | 不同内存配置 |
| ... | ... |

如果不确定，**先试 dtb_00**，不行再试其他的。

## 配置 postmarketOS 使用提取的 DTB

### 步骤 1：复制 DTB 到设备包

```bash
# 假设 dtb_00.dtb 是正确的
cp dtb-extracted/dtbs/dtb_00.dtb device-xiaomi-piano/piano.dtb
```

### 步骤 2：修改 deviceinfo

编辑 `device-xiaomi-piano/deviceinfo`，设置：

```bash
# DTB 文件名（不含扩展名）
deviceinfo_dtb="piano"

# 不使用 dtbloader（我们直接用提取的 DTB）
deviceinfo_no_dtbloader="true"
```

### 步骤 3：修改设备包 APKBUILD

确保 `device-xiaomi-piano/APKBUILD` 中包含 DTB 文件：

```bash
source="
	deviceinfo
	piano.dtb
"

package() {
	install -Dm644 "$srcdir/deviceinfo" \
		"$pkgdir/etc/deviceinfo"

	# 安装 DTB
	install -Dm644 "$srcdir/piano.dtb" \
		"$pkgdir/boot/dtbs/piano.dtb"
}
```

### 步骤 4：重新构建

```bash
./build.sh clean
./build.sh all
```

## 修改 DTB（可选）

如果需要修改设备树（例如启用 UART 调试、修改显示参数）：

```bash
# 1. 反编译
./extract-dtb.sh decompile piano.dtb piano.dts

# 2. 编辑 dts 文件
vim piano.dts

# 3. 重新编译
./extract-dtb.sh compile piano.dts piano.dtb
```

### 常见修改

#### 启用 UART 控制台

```dts
/ {
    chosen {
        stdout-path = "serial0:115200n8";
    };
    aliases {
        serial0 = &qupv3_se10_uart;
    };
};

&qupv3_se10_uart {
    status = "okay";
};
```

#### 启用 simple-framebuffer

```dts
/ {
    reserved-memory {
        framebuffer: framebuffer@9c000000 {
            compatible = "simple-framebuffer";
            reg = <0x0 0x9c000000 0x0 0x1900000>; /* 1600*2560*4 */
            width = <1600>;
            height = <2560>;
            stride = <6400>; /* 1600*4 */
            format = "a8b8g8r8";
        };
    };
};
```

> **注意**：simple-framebuffer 的地址和大小必须与 bootloader 设置的一致。
> 可以从运行中的安卓系统获取：
> ```bash
> adb shell su -c 'cat /proc/device-tree/chosen/framebuffer/reg' | xxd
> adb shell su -c 'cat /proc/device-tree/chosen/framebuffer/width'
> ```

## 从安卓系统获取 DTB 信息

如果设备已 root，可以直接从运行的系统获取设备树：

```bash
# 导出整个设备树（包括运行时的参数）
adb shell su -c 'cat /sys/firmware/devicetree/base/model'
adb shell su -c 'ls /sys/firmware/devicetree/base/'

# 导出完整 DTB
adb shell su -c 'cat /sys/firmware/fdt' > running.dtb

# 反编译查看
./extract-dtb.sh decompile running.dtb running.dts
```

这种方式获取的是**运行时的设备树**（包含 bootloader 修改的参数），比从 dtbo 提取的更准确。

## 常见问题

### Q: 提取的 DTB 启动后黑屏怎么办？

A: 
1. 确认选对了 DTB（查看 model 字段）
2. 尝试 dtbo 中的其他 DTB
3. 通过 UART 串口查看内核日志，定位卡在哪一步
4. 检查 `deviceinfo_kernel_cmdline` 中的控制台参数是否正确

### Q: 可以用主线内核的 sm8750.dtsi 吗？

A: 目前主线内核（6.x）还没有完整的 SM8750 设备树支持。SM8750 太新，主线化需要大量工作。初期建议使用从固件提取的下游 DTB。

### Q: DTB 可以和内核版本不匹配吗？

A: 下游内核的 DTB 通常与特定内核版本绑定。如果内核版本差异较大，可能会出现驱动不匹配的问题。建议使用与内核源码同一版本的固件中提取的 DTB。

### Q: 如何确认 DTB 被正确加载？

A: 
```bash
# 在 postmarketOS 中
cat /proc/device-tree/model
# 应输出: Xiaomi Pad 8 Pro

dmesg | grep -i "Machine model"
# 应输出: Machine model: Xiaomi Pad 8 Pro
```

## 参考链接

- 高通 DTBO 格式说明：https://source.android.com/docs/core/architecture/dto/partitions
- Android boot image 格式：https://source.android.com/docs/core/architecture/bootloader/boot-image-header
- postmarketOS deviceinfo 参考：https://wiki.postmarketos.org/wiki/Deviceinfo_reference
- 小米官方内核：https://github.com/MiCode/Xiaomi_Kernel_OpenSource/tree/piano-w-oss
