# Make 目标参考

运行 `make help` 查看内置摘要。

## 环境准备

| 目标 | 说明 |
|---|---|
| `make build` | 构建主 Docker 构建器镜像 |
| `make build-nocache` | 无缓存重新构建 |
| `make build-debian-builder` | 预构建 ARM64 Debian rootfs 构建器（含 binfmt 注册） |
| `make register-arm64-binfmt` | 手动注册 ARM64 binfmt（x86_64 宿主机） |
| `make check` | 项目自检（语法、配置、契约校验） |

## SDK 管理

| 目标 | 说明 |
|---|---|
| `make fetch-510` | Rockchip Linux 5.10 → `rk3588-sdk-rockchip-5.10` |
| `make fetch-61` | Rockchip Linux 6.1 → `rk3588-sdk-rockchip-6.1` |
| `make fetch-66` | Rockchip Linux 6.6 → `rk3588-sdk-rockchip-6.6` |
| `make fetch-firefly` | Firefly AIO-3588 → `rk3588-sdk-firefly` |
| `make fetch-radxa` | Radxa Rock 5B → `rk3588-sdk-radxa` |
| `make fetch-rock5c` | Radxa Rock 5C → `rk3588-sdk-rock5c` |
| `make fetch-orangepi` | OrangePi 5 → `rk3588-sdk-orangepi` |
| `make fetch-muse` | MUSE RK3588 → `rk3588-sdk-muse-5.10` |
| `make fetch-custom SDK_VOLUME=... MANIFEST=...` | 自定义本地 manifest |
| `make fetch-custom SDK_VOLUME=... CUSTOM_MANIFEST_URL=... CUSTOM_MANIFEST_NAME=...` | 自定义远程 manifest |
| `make import-local-sdk SDK_PATH=... SDK_VOLUME=...` | 导入本地已有 SDK |
| `make update SDK_VOLUME=...` | 更新已有 SDK（repo sync） |
| `make verify-sdk-volume SDK_VOLUME=...` | 校验 SDK 完整性 |
| `make verify-cokepi-sdk SDK_VOLUME=...` | CokePi SDK 额外校验 |

## 切换当前配置

这些目标修改 `.env` 文件，互不影响。

| 目标 | 说明 |
|---|---|
| `make use-volume` | 交互式选择 SDK volume |
| `make use-volume-rockchip-5.10` | → `rk3588-sdk-rockchip-5.10` |
| `make use-volume-rockchip-6.1` | → `rk3588-sdk-rockchip-6.1` |
| `make use-volume-rockchip-6.6` | → `rk3588-sdk-rockchip-6.6` |
| `make use-volume-firefly` | → `rk3588-sdk-firefly` |
| `make use-volume-radxa` | → `rk3588-sdk-radxa` |
| `make use-volume-rock5c` | → `rk3588-sdk-rock5c` |
| `make use-volume-orangepi` | → `rk3588-sdk-orangepi` |
| `make use-volume-muse` | → `rk3588-sdk-muse-5.10` |
| `make use-board` | 交互式选择板型 |
| `make use-board-evb1` | → `rk3588-evb1-lp4-v10-linux` |
| `make use-board-rock5c` | → `rk3588s-rock-5c` |
| `make use-board-cokepi-plus` | → `rk3588-cokepi-plus-lp4-v10` |
| `make use-board-cokepi-model` | → `rk3588s-cokepi-model-lp4-v10` |
| `make use-board-muse` | → `rk3588-muse` |
| `make use-rootfs` | 交互式选择 rootfs |
| `make use-rootfs-buildroot` | → `buildroot` |
| `make use-rootfs-debian` | → `debian` |
| `make use-rootfs-all` | → `all`（同时构建两种） |
| `make use-current` | 显示当前选择 |

## 构建

| 目标 | 说明 |
|---|---|
| `make build-uboot` | 编译 U-Boot 引导链 |
| `make build-kernel` | 编译内核 Image + DTB + 模块 |
| `make build-rootfs` | 构建 rootfs（按 ROOTFS 变量选路径） |
| `make image` | 组装 GPT 镜像 + 自动校验 |
| `make verify-image` | 单独重新校验镜像 |
| `make pack` | `image` 的别名 |
| `make build-all` | 依次执行 uboot → kernel → rootfs → image |

所有构建目标需要 `BOARD` 和 `SDK_VOLUME`，可以来自 `.env` 或命令行。`build-rootfs`、`image`、`verify-image` 额外需要 `ROOTFS`。

## 测试

| 目标 | 说明 |
|---|---|
| `make test-debian-qemu` | QEMU 冒烟测试（需要已构建的 Debian 镜像） |
| `make test-debian-all` | 构建 Debian 11/12/13 三个版本并分别出镜像 |

## 调试

| 目标 | 说明 |
|---|---|
| `make shell SDK_VOLUME=...` | 进入主构建器交互式 shell |
| `make debian-shell SDK_VOLUME=...` | 进入 Debian rootfs 构建器 shell |
| `make status` | 显示 Docker 容器和 volume 状态 |

## 清理

| 目标 | 说明 |
|---|---|
| `make clean` | 停止并删除容器 |
| `make clean-all` | 同时删除 volume 和镜像 |
