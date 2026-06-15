# 8pro

基于以下参考仓库，为 8 Pro 创建的 Linux 支持项目骨架：

- https://github.com/adontoo/device_xiaomi_sm8750_OFRP
- https://github.com/AviderMin/ofrp_device_xiaomi_piano
- https://github.com/CypressFjord/Build_Piano_ROM
- https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/

本项目目标：
- 汇总参考仓库中的设备树、补丁和构建脚本，搭建面向 8 Pro 的 Linux 构建流程。
- 提供可复制的克隆与构建脚本，方便在 CI 或本地复现。

快速开始：

1. 克隆本仓库：

```bash
git clone <this-repo-url>
cd xiaomi-pad-8pro-linux
```

2. 下载参考仓库与依赖：

```bash
./scripts/clone_deps.sh
```

3. 构建（示例脚本）：

```bash
./scripts/build.sh
```

目录说明：
- `device/`：设备树、补丁与说明占位
- `scripts/`：克隆与构建辅助脚本
- `docs/`：开发与调试文档

后续：请提供设备具体型号、内核版本和目标根文件系统信息，我会继续填充设备树和补丁。
