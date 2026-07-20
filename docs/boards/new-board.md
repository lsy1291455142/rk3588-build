# 新板检查清单

## 步骤

1. 准备对应 SDK（`fetch-*` 或 `import-local-sdk`）
2. 复制最近似的 `configs/boards/*.conf`，修改 DTB、defconfig、U-Boot 参数与串口
3. 确认 loader / U-Boot 扇区不与 boot 分区重叠
4. 用 `BOARD=...` 构建并做离线校验，再在硬件上串口验收

```bash
cp configs/boards/rk3588-evb1-lp4-v10-linux.conf \
   configs/boards/rk3588-myboard.conf
```

也可用已有 MUSE 路径：

```text
configs/boards/rk3588-muse.conf
manifests/rk3588-muse-5.10.xml
make fetch-muse
```

## 至少确认的字段

| 字段 | 说明 |
|---|---|
| `KERNEL_DEFCONFIG` / `KERNEL_DTB` | 与硬件匹配的 defconfig 与唯一 DTB |
| `UBOOT_DEFCONFIG` / `UBOOT_BOARD` | BSP `make.sh` 参数 |
| `UBOOT_PYTHON` | 仅 `python2` 或 `python3` |
| `DOWNLOAD_LOADER_GLOBS` / `UBOOT_IMAGE_NAMES` | 产物匹配规则 |
| `CONSOLE` / `EXTRA_KERNEL_ARGS` | 串口与附加内核参数 |
| `IMAGE_SIZE_MIB` / `BOOT_*` / `ROOTFS_SIZE_MIB` | 镜像与分区几何 |
| `IDBLOCK_SECTOR` / `UBOOT_SECTOR` | 须在 `BOOT_START_MIB` 之前，当前布局为 64 / 16384 |

## 验证顺序

1. `fetch-*` 或 `import-local-sdk` 接入正确 SDK
2. `make build-all BOARD=rk3588-myboard SDK_VOLUME=... ROOTFS=...`
3. 通过 `verify-image`
4. 在硬件上用 1500000 8N1 串口做最终验收

DTB、DRAM 初始化或存储控制器与硬件不符时，即使离线校验通过，板卡仍可能无法启动。

## 相关文档

- [已支持板型](./profiles.md)
- [校验边界](/build/verification)
- [流水线总览](/build/pipeline)
