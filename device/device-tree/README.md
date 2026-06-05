设备树目录（占位）

本目录用于存放设备树源（DTS/DTB）、转换脚本与说明。

建议结构：

- `dts/`：设备树源文件（*.dts, *.dtsi）
- `dtb/`：编译后的 dtb 文件
- `patches/`：设备树相关补丁
- `build.md`：如何从 DTS 生成 DTB 的说明

生成示例：

```bash
# 在内核源码目录下
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dtbs
# 或使用 dtc 编译单个 dts
dtc -I dts -O dtb -o out.dtb in.dts
```

我可以从参考仓库中提取现有的 DTS/DTB 到本目录并整理说明，是否现在开始？