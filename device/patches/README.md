请把用于内核的补丁文件（.patch）放到本目录下，脚本会按文件名排序并依次应用。

命名建议：使用数字前缀以控制应用顺序，例如：

001-fix-xyz.patch
002-add-driver.patch

脚本：`scripts/apply_patches.sh` 会在构建时检查并尝试应用本目录下的补丁。