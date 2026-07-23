# 变量与 .env

本页列出构建系统所有可配置变量，按作用域分组。变量的最终取值遵循固定的优先级：命令行 `make KEY=val` > `.env` 文件 > 板级 profile 默认值（`board.conf`）> 脚本内置默认值。所有变量都通过 `docker-compose.yml` 以环境变量形式注入构建容器。

> 准确性说明：以下默认值均取自 `Makefile`、`scripts/lib/common.sh`、`boards/TEMPLATE/board.conf` 与 `scripts/[build_*.sh]` 的实际赋值，与代码完全一致。旧文档中出现的 `IMAGE_SIZE_MIB=4096`、`ROOTFS_SIZE_MIB=2048` 等数值为过时笔误，请以本页为准。

## 核心变量（Makefile / 顶层）

| 变量 | 默认 | 说明 |
|---|---|---|
| `BOARD` | 空（必填） | 板型名称，对应 `boards/<BOARD>/board.conf`。设置后 `SDK_VOLUME` 会自动从板级 `SOURCE_MANIFEST` 派生。 |
| `ROOTFS` | 空（必填） | 根文件系统类型：`buildroot`、`debian` 或 `all`。 |
| `SDK_VOLUME` | 空（构建时必填） | Docker 卷名，承载 SDK 源码。若设置 `BOARD` 且其 `SOURCE_MANIFEST` 存在，会自动派生为 `rk3588-sdk-<manifest 去前缀>`。 |
| `DEBIAN_RELEASE` | `13` | Debian 发行版代号：`11`=bullseye、`12`=bookworm、`13`=trixie。仅 Debian rootfs 使用。 |
| `ROOTFS_USERNAME` | `user` | 非 root 普通用户名（Debian）。Buildroot 路径的脚本内置回退为 `rk3588`。 |
| `ROOTFS_PASSWORD` | `password` | 上述用户与 root 的密码（Debian）。Buildroot 路径脚本内置回退为 `rk3588`。 |
| `ROOTFS_HOSTNAME` | 空 | 主机名。为空时回退到板级 `ROOTFS_HOSTNAME_DEFAULT`，再回退到 `BOARD`。 |
| `DEBIAN_PACKAGES` | 空 | 额外 APT 包，精确包名，逗号或空格分隔；`none`/`minbase`/`off`/`-` 表示仅 minbase。不接受功能别名（如 `nm`、`wifibt`）。 |
| `DEBIAN_OVERLAYS` | 空 | 可选 overlay 插件，逗号分隔；`none`/`off`/`-` 关闭；`all` 启用全部；空时回退板级 `DEBIAN_OVERLAYS_DEFAULT`。 |
| `DEBIAN_MIRROR` | `http://deb.debian.org/debian` | Debian 主仓库地址。 |
| `DEBIAN_SECURITY_MIRROR` | `http://security.debian.org/debian-security` | Debian 安全仓库地址。 |
| `DEBIAN_ALLOW_ARCHIVE_FALLBACK` | `yes` | 仅 Debian 11 在常规镜像失败时回退 `archive.debian.org`（`check-valid-until=no`）。 |
| `JOBS` | `0` | 并行编译数；`0` 表示自动取 `nproc`。 |
| `ZSTD_LEVEL` | `6` | 镜像 zstd 压缩级别（1–19，整数）。 |
| `QEMU_TIMEOUT` | `600` | QEMU 冒烟测试总超时（秒，正整数）。 |
| `QEMU_MEMORY_MIB` | `1024` | QEMU 客户机内存（MiB，正整数）。 |
| `QEMU_CPUS` | `2` | QEMU 客户机 CPU 数（正整数）。 |
| `ROOTFS_MODE` | 空 | 根文件系统布局：`rw-ext4` 或 `ro-overlay`。为空时回退板级 `ROOTFS_MODE_DEFAULT`，再回退 `rw-ext4`。 |
| `DATA_SIZE_MIB` | 空 | `ro-overlay` 模式下 ext4 数据分区大小（MiB）。`0` 表示占满剩余空间；为空时回退板级 `DATA_SIZE_MIB_DEFAULT`，再回退 `0`。 |

## 根文件系统布局变量

`ROOTFS_MODE` 与 `DATA_SIZE_MIB` 共同决定分区结构：

- `rw-ext4`（默认）：单个可写 ext4 根分区（第 2 分区，标签 `rootfs`），大小为 `ROOTFS_SIZE_MIB`。
- `ro-overlay`：只读 SquashFS 根（第 2 分区）+ ext4 数据分区（第 3 分区，标签 `data`，挂载 `/data`，作为 OverlayFS upper）。SquashFS 分区尺寸由镜像体积加 1 MiB 余量自动推算；数据分区尺寸由 `DATA_SIZE_MIB` 决定（`0` 占满剩余）。该模式需要内核 `CONFIG_SQUASHFS` 与 `CONFIG_OVERLAY_FS`（已由 `configs/kernel/squashfs-overlay.config` 始终合并），并由 initramfs `overlayroot` hook 在启动期组装。

## Debian 专用变量

| 变量 | 来源 | 说明 |
|---|---|---|
| `DEBIAN_PACKAGES` | CLI / `.env` / 板级 `DEBIAN_PACKAGES_DEFAULT` | 板级默认仅在 CLI/`.env` 未指定时生效；指定 `none` 强制仅 minbase。 |
| `DEBIAN_OVERLAYS` | CLI / `.env` / 板级 `DEBIAN_OVERLAYS_DEFAULT` | 同上；内置插件：`base`、`console`、`firstboot`、`firstboot-info`、`network`。 |
| `ROOTFS_HOSTNAME` | CLI / `.env` / 板级 `ROOTFS_HOSTNAME_DEFAULT` | 同上。 |
| `DEBIAN_CODENAME` | 由 `DEBIAN_RELEASE` 推导 | `11→bullseye`、`12→bookworm`、`13→trixie`。 |
| `DEBIAN_COMPONENTS` | 由 `DEBIAN_RELEASE` 推导 | `11`: `main contrib non-free`；`12/13`: `main contrib non-free non-free-firmware`（mmdebstrap `--components` 用逗号连接）。 |

Debian 基础包（始终包含，`build_debian.sh` 内 `PACKAGES` 数组）：`ca-certificates`、`cloud-guest-utils`、`curl`、`dbus`、`e2fsprogs`、`ethtool`、`gdisk`、`iproute2`、`iputils-ping`、`kmod`、`less`、`net-tools`、`openssh-server`、`passwd`、`procps`、`psmisc`、`sudo`、`systemd-sysv`、`udev`、`util-linux`、`vim-tiny`、`wget`；非 11 版本追加 `systemd-resolved`；`ro-overlay` 模式追加 `initramfs-tools`、`busybox`。

## 构建变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `JOBS` | `0` | 见上。 |
| `ZSTD_LEVEL` | `6` | 见上。 |
| `CCACHE_DIR` | `/home/builder/.ccache` | ccache 缓存目录（挂载于 `rk3588-ccache` 卷）。 |
| `CCACHE_MAXSIZE` | `10G` | ccache 上限（`docker-compose.yml` 注入）。 |
| `USE_NATIVE_BUILD` | `no` | 仅 ARM64 宿主机有效：设为 `yes` 时清空调 `CROSS_COMPILE` 用原生 GCC。 |
| `ARCH` | `arm64` | 目标架构（构建容器内固定）。 |
| `CROSS_COMPILE` | `aarch64-linux-gnu-` | 交叉编译器前缀（`USE_NATIVE_BUILD=yes` 且 ARM64 宿主时清空）。 |

## SDK 拉取变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `MANIFEST` | 空 | 本地 manifest 文件名（位于 `manifests/`，不含路径）。`make fetch` 时从板级 `SOURCE_MANIFEST` 自动获得。 |
| `CUSTOM_MANIFEST_URL` | 空 | 自定义远程 manifest 仓库 URL（`make fetch-custom`）。 |
| `CUSTOM_MANIFEST_NAME` | 空 | 自定义 manifest 文件名（`make fetch-custom`）。 |
| `BRANCH` | `main` | 自定义 manifest 的默认分支。 |
| `DEPTH` | `1` | `repo` 浅克隆深度；`0` 表示完整克隆。 |
| `JOBS` | `nproc` | `repo sync` 并行数（`fetch_sources.sh` 内）。 |
| `MAX_RETRIES` | `3` | `repo sync` 最大重试次数。 |
| `MIN_DISK_GB` | `10` | 拉取前最小可用磁盘空间（GB）检查门槛。 |
| `FETCH_ON_START` | `no` | 容器启动时是否自动拉取 SDK（`entrypoint.sh`）。 |
| `EXTRA_COMPONENTS` | `no` | 自定义 manifest 拉取时的额外组件开关。 |

## QEMU 测试变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `QEMU_TIMEOUT` | `600` | 见上。 |
| `QEMU_MEMORY_MIB` | `1024` | 见上。 |
| `QEMU_CPUS` | `2` | 见上。 |

以上三个变量仅在 `make test-debian-qemu` / `make test-debian-all` 中生效（Debian rootfs）。

## 板级 profile 变量（`boards/<BOARD>/board.conf`）

完整字段定义见 [新增板型](/boards/add-board) 与 `boards/TEMPLATE/board.conf`。常用字段：

`BOARD_DESCRIPTION`（必填）、`SOC`、`SOURCE_MANIFEST`、`EXPECTED_KERNEL_REVISION` / `EXPECTED_UBOOT_REVISION` / `EXPECTED_RKBIN_REVISION` / `EXPECTED_BUILDROOT_REVISION`（设置 `SOURCE_MANIFEST` 时必填，40 位完整 SHA）、`KERNEL_DEFCONFIG`（必填）、`KERNEL_DTB`（必填，须 `.dtb` 结尾）、`KERNEL_DTBO`、`KERNEL_EXTRA_FRAGMENTS`、`DTB_STRIP_BOOTARGS`（默认 `yes`）、`UBOOT_DEFCONFIG`（必填）、`UBOOT_BOARD`（必填）、`UBOOT_BUILD_SYSTEM`（默认 `rockchip-make-sh`）、`UBOOT_PYTHON`（默认 `python3`）、`BOOTLOADER_LAYOUT`（默认 `rockchip-gpt-idblock-extlinux-v1`）、`DOWNLOAD_LOADER_GLOBS`、`UBOOT_IMAGE_NAMES`、`IDBLOCK_SECTOR`（默认 `64`）、`UBOOT_SECTOR`（默认 `16384`）、`CONSOLE`（必填，如 `ttyFIQ0,1500000n8`）、`EXTRA_KERNEL_ARGS`、`IMAGE_SIZE_MIB`（默认 `2048`）、`BOOT_START_MIB`（默认 `16`）、`BOOT_SIZE_MIB`（默认 `256`）、`ROOTFS_SIZE_MIB`（默认 `1700`）、`ROOTFS_MODE_DEFAULT`、`DATA_SIZE_MIB_DEFAULT`、`OUTPUT_IMAGE_PREFIX`、`EXTLINUX_LABEL`、`ROOTFS_HOSTNAME_DEFAULT`、`DEBIAN_PACKAGES_DEFAULT`、`DEBIAN_OVERLAYS_DEFAULT`。

## .env 文件示例

`.env` 由 `make use-*` 系列目标自动维护（仅写入被切换的键）。以下为手动编辑示例：

```ini
BOARD=rk3588s-rock-5c
SDK_VOLUME=rk3588-sdk-rock5c
ROOTFS=debian
DEBIAN_RELEASE=13
ROOTFS_USERNAME=user
ROOTFS_PASSWORD=password
DEBIAN_PACKAGES=network-manager,wpasupplicant,i2c-tools
DEBIAN_OVERLAYS=base,console,firstboot,firstboot-info,network
```

所有 `make` 目标在运行前通过 `require-board` / `require-rootfs` / `require-sdk-volume` 校验必要变量；缺失时给出 `make use-*` 或命令行示例提示。
