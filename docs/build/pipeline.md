# 流水线总览

本文说明本项目如何从 SDK 源码得到可烧录的 GPT 镜像。

## 为什么只有 Image、DTB、U-Boot 不够

| 组件 | 作用 |
|---|---|
| loader / IDBlock | DDR 初始化、加载 U-Boot |
| U-Boot | 读分区、加载 Kernel 与 DTB |
| Kernel `Image` | 启动 Linux |
| DTB | 描述板级硬件 |
| 内核模块 | 与 Kernel release 匹配的驱动 |
| rootfs | 提供 `/sbin/init` 与用户空间 |
| 分区表 + 启动配置 | 固定偏移与挂载方式 |

缺少 rootfs 时，内核常见停在 `VFS: Unable to mount root fs` 或 `No working init found`。本项目输出的是**整盘 raw GPT 镜像**，不是单独的 bootloader 或 Rockchip `update.img`。

## 总览

```text
builder 镜像
    → SDK（fetch 或本地导入）
    → build-kernel   → Image / DTB / modules.tar
    → build-uboot    → idblock.img / uboot.img / download-loader.bin
    → build-rootfs   → Buildroot 和/或 Debian rootfs
    → image          → GPT raw image + .img.zst + SHA256
    → verify-image   （image 后自动执行）
    → 可选 test-debian-qemu
```

`SDK_VOLUME`、`BOARD`、`ROOTFS` 三者均无默认值，须通过 `.env`、`make use-*` 或命令行显式给出。

## 一键构建

```bash
make build-all \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  ROOTFS=debian \
  DEBIAN_RELEASE=13
```

分步目标：

```bash
make build-kernel
make build-uboot
make build-rootfs
make image          # 自动 verify-image
make verify-image   # 单独离线校验
```

## 完整命令示例

### ROCK 5C + Debian 13

```bash
make build
make fetch-rock5c
make build-all \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  ROOTFS=debian \
  DEBIAN_RELEASE=13
make test-debian-qemu \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  DEBIAN_RELEASE=13
```

### CokePi Model + 本地 SDK

```bash
make build
make import-local-sdk \
  SDK_PATH=/absolute/path/to/rk3588_linux-5.10-cokepi-rkr9 \
  SDK_VOLUME=rk3588-sdk-cokepi-rkr9
make verify-cokepi-sdk SDK_VOLUME=rk3588-sdk-cokepi-rkr9
make build-all \
  BOARD=rk3588s-cokepi-model-lp4-v10 \
  SDK_VOLUME=rk3588-sdk-cokepi-rkr9 \
  ROOTFS=debian \
  DEBIAN_RELEASE=13
```

### EVB1 + Buildroot / Debian / 两者

```bash
make fetch-510

make build-all \
  BOARD=rk3588-evb1-lp4-v10-linux \
  SDK_VOLUME=rk3588-sdk-rockchip-5.10 \
  ROOTFS=buildroot

make build-all \
  BOARD=rk3588-evb1-lp4-v10-linux \
  SDK_VOLUME=rk3588-sdk-rockchip-5.10 \
  ROOTFS=debian \
  DEBIAN_RELEASE=13

make build-all \
  BOARD=rk3588-evb1-lp4-v10-linux \
  SDK_VOLUME=rk3588-sdk-rockchip-5.10 \
  ROOTFS=all \
  DEBIAN_RELEASE=13
```

仅重新打包（`common/` 与对应 rootfs 产物已齐全）：

```bash
make image \
  BOARD=rk3588-evb1-lp4-v10-linux \
  SDK_VOLUME=rk3588-sdk-rockchip-5.10 \
  ROOTFS=buildroot
```
