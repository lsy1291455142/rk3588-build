# Make 目标参考

所有构建入口集中在 `Makefile`。默认目标为 `menu`（交互式数字菜单）。本页列出面向用户的全部 `make` 目标，按用途分组。目标内部依赖关系（如 `build-all` 依次调用 `build-uboot` → `build-kernel` → `build-rootfs` → `image`）也一并说明。

> 提示：运行 `make help` 可随时查看内建帮助与完整 ROCK 5C 工作流示例。

## 环境与信息

| 目标 | 说明 |
|---|---|
| `make menu` | 默认目标。编号菜单，按数字选择 `build`/`fetch`/`build-all`/`test-debian-qemu` 等 24 项。 |
| `make help` | 打印完整命令行帮助，含 ROCK 5C 一键构建示例。 |
| `make info` | 显示当前 `.env` 配置、当前板型（描述、manifest）、SDK 卷、rootfs、Debian 发行版。 |
| `make status` | 执行 `docker compose ps` 并列出 `rk3588` 前缀的 Docker 卷。 |
| `make list-boards` | 列出所有板型 profile 及其 `BOARD_DESCRIPTION`。 |

## 构建 Docker 构建器

| 目标 | 说明 |
|---|---|
| `make build` | 构建主构建器镜像 `rk3588-build:latest`（`SDK_VOLUME=rk3588-sdk-build`，即 `docker compose build rk3588-build`）。 |
| `make build-nocache` | 同上，但 `--no-cache`。 |
| `make build-builder` | 同 `make build`（别名）。 |
| `make build-debian-builder` | 预构建 ARM64 Debian rootfs 构建器（`debian-rootfs` 服务），并先 `register-arm64-binfmt`。 |
| `make register-arm64-binfmt` | 在 x86_64 宿主用 `tonistiigi/binfmt` 注册 ARM64 模拟；ARM64 宿主跳过。 |

## SDK 管理

| 目标 | 说明 |
|---|---|
| `make fetch BOARD=<board>` | 按板级 `SOURCE_MANIFEST` 用 `repo` 拉取 SDK 到派生卷（如 `rk3588-sdk-rock5c`），随后切换 `.env` 的 `SDK_VOLUME`。 |
| `make fetch-custom SDK_VOLUME=<v> MANIFEST=<f.xml>` | 用本地 manifest 文件拉取。也可用 `CUSTOM_MANIFEST_URL` + `CUSTOM_MANIFEST_NAME` 指定远程 manifest。 |
| `make update SDK_VOLUME=<v>` | 重新初始化并 `repo sync` 更新已有 SDK 卷。 |
| `make import-local-sdk SDK_PATH=/abs SDK_VOLUME=<v>` | 把本地已下载的 SDK 目录以 bind 卷方式接入（不复制源码），随后切换 `.env`。 |
| `make verify-sdk-volume SDK_VOLUME=<v>` | 校验卷内 `kernel`/`u-boot`/`rkbin`/`buildroot` 四组件目录存在且卷可被 builder 用户（uid 1000）写入。 |
| `make shell SDK_VOLUME=<v>` | 打开主构建器交互 shell。 |
| `make debian-shell SDK_VOLUME=<v>` | 打开 ARM64 Debian 构建器交互 shell。 |

## 切换与查看配置

| 目标 | 说明 |
|---|---|
| `make use-volume` | 交互式选择 `rk3588-sdk-*` 卷并写入 `.env` 的 `SDK_VOLUME`。 |
| `make use-board [BOARD=<b>]` | 交互式或指定式选择板型，写入 `.env` 的 `BOARD`；若 `SDK_VOLUME` 为空会按 `SOURCE_MANIFEST` 派生。 |
| `make use-rootfs` | 交互式选择 `buildroot`/`debian`/`all`，写入 `.env` 的 `ROOTFS`。 |
| `make use-rootfs-buildroot` | 直接写入 `ROOTFS=buildroot`。 |
| `make use-rootfs-debian` | 直接写入 `ROOTFS=debian`。 |
| `make use-rootfs-all` | 直接写入 `ROOTFS=all`。 |
| `make use-current` | 显示当前 `SDK_VOLUME` / `BOARD` / `ROOTFS`。 |

## 构建

| 目标 | 说明 |
|---|---|
| `make build-uboot BOARD=.. SDK_VOLUME=..` | 编译 U-Boot + 打包 RKNS IDBlock，产物写入 `output/<BOARD>/common/`。 |
| `make build-kernel BOARD=.. SDK_VOLUME=..` | 合并 defconfig + 共享/板级 fragment，编译 `Image`、`rockchip/<DTB>`、模块包。 |
| `make build-rootfs ROOTFS=<buildroot\|debian>` | 构建指定 rootfs（分派 `_buildroot-rootfs` / `_debian-rootfs`）。`all` 时两者都构建。 |
| `make _buildroot-rootfs` | 内部：Buildroot external tree 构建（需 `build-kernel` 产物）。 |
| `make _debian-rootfs` | 内部：先 `debian-preflight` 校验 ARM64 架构，再用 mmdebstrap 构建 Debian rootfs。 |
| `make debian-preflight` | 内部：探测 `debian-rootfs` 容器架构是否为 `arm64`。 |
| `make build-all [DEBIAN_RELEASE=..] [DEBIAN_PACKAGES=..] [DEBIAN_OVERLAYS=..]` | 依次 `build-uboot` → `build-kernel` → `build-rootfs` → `image`（完整镜像流水线）。 |

## 镜像与校验

| 目标 | 说明 |
|---|---|
| `make image` | 按 `ROOTFS` 组装 GPT 裸镜像（`_image-one`），随后 `_verify-one`。 |
| `make verify-image` | 仅对已有镜像执行深度校验（`_verify-one`），不重新组装。 |
| `make _image-one` | 内部：调用 `make_image.sh` 生成 `.img` / `.img.zst` / `.sha256` / `image-build-info.txt`。 |
| `make _verify-one` | 内部：以 root 身份调用 `verify_image.sh` 校验分区几何、嵌入式组件、rootfs 内容。 |

## 测试

| 目标 | 说明 |
|---|---|
| `make test-debian-qemu BOARD=.. SDK_VOLUME=.. [DEBIAN_RELEASE=13]` | 在 QEMU `virt` 中用构建内核与完整 GPT 镜像做串口登录 + SSH + systemd 健康检查。 |
| `make test-debian-all BOARD=.. SDK_VOLUME=..` | 依次对 Debian 11/12/13 各构建 rootfs + 镜像（验证跨版本可构建性）。 |

## 板型管理

| 目标 | 说明 |
|---|---|
| `make new-board BOARD=<name>` | 从 `TEMPLATE` 复制 `board.conf` 并生成空的 `kernel.config` 片段。 |
| `make validate-board BOARD=<name>` | 加载并校验板级 profile（`load_board_profile` 的校验逻辑）。 |

## 校验与清理

| 目标 | 说明 |
|---|---|
| `make check` | 运行项目检查：bash 语法、ShellCheck、manifest 校验、板型 profile、buildroot 外部树、U-Boot 契约、内核契约、QEMU 契约、Debian 包/overlay 契约等。 |
| `make clean` | `docker compose down --remove-orphans`。 |
| `make clean-all` | 同上并移除卷与本地镜像（`--volumes --rmi local`）。 |

## 内部/依赖目标

以下目标供上述目标调用，一般不直接使用：`require-board`、`require-rootfs`、`require-sdk-volume`、`validate-rootfs`、`prepare-output`、`_use_sdk_switch`、`_use_board_switch`、`_use_rootfs_switch`。

## 典型组合

完整 Debian 13 构建（ROCK 5C）：

```bash
make build
make fetch BOARD=rk3588s-rock-5c
make build-all BOARD=rk3588s-rock-5c SDK_VOLUME=rk3588-sdk-rock5c ROOTFS=debian DEBIAN_RELEASE=13
make test-debian-qemu BOARD=rk3588s-rock-5c SDK_VOLUME=rk3588-sdk-rock5c DEBIAN_RELEASE=13
```

跨版本可构建性（仅 Debian）：

```bash
make test-debian-all BOARD=rk3588s-rock-5c SDK_VOLUME=rk3588-sdk-rock5c
```
