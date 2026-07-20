# 第一次构建

目标：在干净环境里打出 **ROCK 5C + Debian 13** 镜像。这是公开源路径，用来验证工具链本身是否正常。

## 0. 准备

```bash
git clone https://github.com/lsy1291455142/rk3588-build.git
cd rk3588-build
```

确认 `docker`、`docker compose`、`make` 可用。

## 1. 准备 builder 镜像

二选一。

本地构建：

```bash
make build
```

或从 GHCR 拉 multi-arch 镜像，并打本地 tag（Makefile 认 `rk3588-build:latest`）：

```bash
docker pull ghcr.io/lsy1291455142/rk3588-build:latest
docker tag ghcr.io/lsy1291455142/rk3588-build:latest rk3588-build:latest
```

## 2. 拉 SDK

```bash
make fetch-rock5c
```

这会创建 Docker volume `rk3588-sdk-rock5c`，用 `manifests/rk3588-rock5c.xml` 拉源码。ROCK 5C profile 还锁定了已验证的 commit。

## 3. 一键构建

```bash
make build-all \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  ROOTFS=debian \
  DEBIAN_RELEASE=13
```

三个变量**没有默认值**。缺任何一个，相关目标会直接失败。

也可以先写进 `.env`：

```bash
make use-volume-rock5c
make use-board-rock5c
make use-rootfs-debian
make use-current
make build-all DEBIAN_RELEASE=13
```

## 4. 看产物

```text
output/rk3588s-rock-5c/
├── common/                 # Image、DTB、loader、uboot、modules
└── debian-13/
    ├── rootfs.ext4
    ├── rk3588s-rock-5c-debian-13.img
    ├── rk3588s-rock-5c-debian-13.img.zst
    └── ...
```

`make image` 结束后会自动跑 `verify-image`。失败先看终端最后一段错误，不要直接烧板。

## 5. 可选：QEMU 冒烟

```bash
make test-debian-qemu \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  DEBIAN_RELEASE=13
```

这只在 ARM64 `virt` 上检查登录 / systemd / 扩容 / 网络，**不能**代替真机串口。

## 6. 烧录

见 [烧录与启动](./flash-and-boot.md)。

## 换板时改什么

| 板 | SDK | BOARD |
|---|---|---|
| ROCK 5C | `make fetch-rock5c` | `rk3588s-rock-5c` |
| EVB1 | `make fetch-510` | `rk3588-evb1-lp4-v10-linux` |
| MUSE | `make fetch-muse` | `rk3588-muse` |
| CokePi | 本地 `import-local-sdk` | Plus / Model 对应 profile |

完整板表见 [已支持板型](/boards/supported)。
