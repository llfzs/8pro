设备占位目录

本目录用于放置 Xiaomi Pad 8 Pro 的设备树、补丁、驱动补丁和说明文档。

建议结构：

- `kernel/`：内核相关补丁与配置
- `device-tree/`：设备树源与 dtb 生成说明
- `firmware/`：需要的固件 blobs
- `rootfs/`：根文件系统定制说明

请提供设备型号、主 SoC、目标内核版本，以便我开始移植和整理。