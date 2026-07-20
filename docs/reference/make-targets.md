# Make 目标

入口始终是仓库根目录的 `Makefile`。完整列表以 `make help` 为准；本页按用途归类。

## 环境与上下文

| 目标 | 作用 |
|---|---|
| `make build` | 构建主 builder 镜像 `rk3588-build:latest` |
| `make build-nocache` | 无缓存重建主 builder |
| `make build-debian-builder` | 预构建 ARM64 Debian rootfs builder |
| `make register-arm64-binfmt` | 注册 arm64 binfmt（Debian 路径会用到） |
| `make use-current` | 显示当前 `SDK_VOLUME` / `BOARD` / `ROOTFS` |
| `make status` | 容器与 volume 状态 |
| `make shell` | 进入主 builder |
| `make debian-shell` | 进入 Debian ARM64 builder |
| `make check` | 脚本语法、manifest、契约等静态检查 |
| `make clean` | 停止容器 |
| `make clean-all` | 停止并删除相关 volume / 镜像（危险） |

## SDK

| 目标 | Volume / 说明 |
|---|---|
| `make fetch-rock5c` | `rk3588-sdk-rock5c` |
| `make fetch-510` | `rk3588-sdk-rockchip-5.10` |
| `make fetch-61` | `rk3588-sdk-rockchip-6.1` |
| `make fetch-66` | `rk3588-sdk-rockchip-6.6` |
| `make fetch-radxa` | `rk3588-sdk-radxa` |
| `make fetch-firefly` | `rk3588-sdk-firefly` |
| `make fetch-orangepi` | `rk3588-sdk-orangepi` |
| `make fetch-muse` | `rk3588-sdk-muse-5.10` |
| `make fetch-custom` | 自定义 manifest / 远程 |
| `make update` | 更新已有 `SDK_VOLUME` |
| `make import-local-sdk` | 本地路径 bind 成 volume（不复制源码） |
| `make verify-sdk-volume` | 检查 volume 是否含必需目录 |
| `make verify-cokepi-sdk` | CokePi SDK 额外检查 |

切换当前 volume（只写 `.env` 的 `SDK_VOLUME`）：

```bash
make use-volume
make use-volume-rock5c
make use-volume-muse
# ... 以及 rockchip-5.10 / 6.1 / 6.6 / firefly / radxa / orangepi
```

## 板型与 rootfs 切换

```bash
make use-board
make use-board-rock5c
make use-board-evb1
make use-board-cokepi-plus
make use-board-cokepi-model
make use-board-muse

make use-rootfs
make use-rootfs-buildroot
make use-rootfs-debian
make use-rootfs-all
```

这些目标**只改 `.env`**，不会自动开编。

## 组件与整包

| 目标 | 需要 | 说明 |
|---|---|---|
| `make build-kernel` | `BOARD` `SDK_VOLUME` | Image、DTB、modules.tar |
| `make build-uboot` | `BOARD` `SDK_VOLUME` | idblock / uboot / download-loader |
| `make build-rootfs` | `BOARD` `SDK_VOLUME` `ROOTFS` | Buildroot 和/或 Debian |
| `make image` | 同上 | 打包 GPT；末尾自动 `verify-image` |
| `make verify-image` | 同上 | 单独离线校验 |
| `make build-all` | 同上 | kernel → uboot → rootfs → image |
| `make pack` | 同 `image` | `image` 的别名入口 |
| `make test-debian-qemu` | `BOARD` `SDK_VOLUME` | ARM64 virt 冒烟 |
| `make test-debian-all` | `BOARD` `SDK_VOLUME` | 复用 bootloader/kernel，打 Debian 11/12/13 |

示例：

```bash
make build-all \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  ROOTFS=debian \
  DEBIAN_RELEASE=13 \
  DEBIAN_FEATURES=nm,hwdebug
```

## 产物位置

```text
output/<BOARD>/
├── common/
└── <variant>/          # buildroot 或 debian-13 等
```

详见 [构建流水线](/how-it-works/pipeline) 与 [第一次构建](/usage/quick-start)。
