内核目录（占位）

本目录用于放置与 Xiaomi Pad 8 Pro（sm8750）相关的内核补丁、配置和说明。

建议结构：

- `patches/`：对上游内核或厂商内核的补丁（*.patch）
- `configs/`：推荐的 kernel config（如 defconfig）
- `notes.md`：移植说明与已知问题

使用流程：
1. 运行 `./scripts/clone_deps.sh` 将参考仓库拉取到 `third_party/`。
2. 将需要应用的补丁放入 `device/kernel/patches/`。
3. 使用 `./scripts/apply_patches.sh` 应用补丁到指定的内核源码目录。
4. 使用 `./scripts/build_kernel.sh` 编译内核。

如需我从参考仓库提取补丁与配置，请允许我访问并列出 third_party 中的内容。