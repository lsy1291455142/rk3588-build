# Make 目标参考

运行 `make` / `make menu` 进入编号菜单，或 `make help` 查看完整摘要。

## 环境与信息

| 目标 | 说明 |
|---|---|
| `make` / `make menu` | 编号交互菜单（默认目标） |
| `make build` | 构建主 Docker 构建器镜像 |
| `make build-nocache` | 无缓存重新构建 |
| `make build-debian-builder` | 预构建 ARM64 Debian rootfs 构建器（含 binfmt 注册） |
| `make register-arm64-binfmt` | 手动注册 ARM64 binfmt（x86_64 宿主机） |
| `make check` | 项目自检（语法、配置、契约校验） |
| `make list-boards` | 列出所有可用的板型及其描述 |
| `make new-board BOARD=<name>` | 从模版快速创建新的板型配置文件 |
| `make validate-board BOARD=<name>` | 校验指定板型配置文件的格式正确性 |
| `make info` | 显示当前构建环境配置与状态 |

## SDK 管理

| 目标 | 说明 |
|---|---|
| `make fetch [BOARD=<name>]` | 读取板型 `SOURCE_MANIFEST` 拉取 SDK；无 manifest 的板需用 import/fetch-custom |
| `make fetch-custom SDK_VOLUME=... MANIFEST=...` | 自定义本地 manifest 拉取 |
| `make fetch-custom SDK_VOLUME=... CUSTOM_MANIFEST_URL=... CUSTOM_MANIFEST_NAME=...` | 自定义远程 manifest 拉取 |
| `make import-local-sdk SDK_PATH=... SDK_VOLUME=...` | 导入本地已有 SDK |
| `make update SDK_VOLUME=...` | 更新已有 SDK（repo sync） |
| `make verify-sdk-volume SDK_VOLUME=...` | 校验 SDK 完整性 |

> WiFi/BT 固件**不是** Makefile 核心目标。由板级 `plugin.sh` 在
> `build-rootfs` 时自动 stage；可选手动 CLI：
> `./rootfs/debian/boards/rk3588s-cokepi-model-lp4-v10/stage-aic8800-firmware.sh`

## 切换与查看配置

修改 `.env` 文件保存全局默认选择，或通过 CLI 参数重写。

| 目标 | 说明 |
|---|---|
| `make use-board` | 编号选择板型（始终弹菜单） |
| `make use-board BOARD=<name>` | 直接切换到指定板型 |
| `make use-volume` | 交互式选择 SDK volume |
| `make use-rootfs` | 交互式选择 rootfs |
| `make use-rootfs-buildroot` | 切换 rootfs 为 `buildroot` |
| `make use-rootfs-debian` | 切换 rootfs 为 `debian` |
| `make use-rootfs-all` | 切换 rootfs 为 `all`（同时构建两种） |
| `make use-current` | 显示当前已选择的配置 |

## 构建

| 目标 | 说明 |
|---|---|
| `make build-uboot` | 编译 U-Boot 引导链 |
| `make build-kernel` | 编译内核 Image + DTB + 模块 |
| `make build-rootfs` | 构建 rootfs（按 `ROOTFS` 变量选路径） |
| `make image` | 组装 GPT 镜像 + 自动校验 |
| `make verify-image` | 单独重新校验镜像 |
| `make build-all` | 依次执行 uboot → kernel → rootfs → image |

所有构建目标需要指定 `BOARD`，`SDK_VOLUME` 会根据 `BOARD` 配置自动推导（亦可显式指定）。`build-rootfs`、`image`、`verify-image` 额外需要 `ROOTFS`。

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
