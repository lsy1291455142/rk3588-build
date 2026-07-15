# RK3588 Linux BSP Docker Build Environment

本项目提供一个基于 Docker 的 RK3588 BSP 编译与构建环境，支持一键生成可直接烧录至 SD 卡或 eMMC 的完整 GPT 格式系统镜像。构建流程不仅输出 U-Boot、内核 `Image` 和设备树（DTB），还会完整集成 Buildroot 或 Debian 根文件系统、`extlinux` 引导配置，并自动完成镜像打包、压缩与校验。

新手建议先阅读：[RK3588 开发板完整系统镜像构建流程](docs/RK3588_SYSTEM_IMAGE_BUILD_FLOW.md)。

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces.new/lsy1291455142/rk3588-build)

> [!TIP]
> **一键云端构建**：本项目已完整支持 GitHub Codespaces。点击上方按钮可直接在云端打开预配置好 Docker-in-Docker 和编译工具链的开发环境，无需在本地配置 Docker 和运行环境。
> * **免费额度**：GitHub 个人账户每月赠送 **120 核时**（默认 2 核机器可运行 60 小时）与 **15 GB 存储**空间。
> * **省流建议**：不使用时容器会自动暂停（不计运行时间）。为了避免持续占用 15 GB 存储额度，编译/测试完成后建议及时去 [GitHub Codespaces 管理页](https://github.com/codespaces) 删除不用的实例。

## 宿主机架构支持

| 宿主机架构 | U-Boot/Kernel | Buildroot rootfs | Debian rootfs | 说明 |
|---|---|---|---|---|
| x86_64 (PC/Codespace) | 交叉编译 | 交叉编译 | QEMU binfmt 模拟 ARM64 | 自动注册 binfmt，自动安装 i386 兼容库 |
| ARM64 (服务器/开发板) | 交叉编译或原生编译 | 交叉编译 | 原生 ARM64 | 自动安装 qemu-user-static 用于运行 rkbin 中的 x86-64 预编译工具 |

两套架构均无需手动配置，`make` 会自动检测并处理。

## 支持范围

- Kernel `Image`、指定板级 DTB、内核模块
- Rockchip loader 和 `uboot.img`
- U-Boot GPT/extlinux 启动能力与签名策略构建时校验
- Buildroot `2025.02.15`
- Debian 11/bullseye、12/bookworm、13/trixie，默认 Debian 13
- `ROOTFS=buildroot`、`ROOTFS=debian`、`ROOTFS=all`
- FAT32 boot 分区、extlinux、ext4 rootfs
- 首次启动在线扩展 rootfs
- 串口、DHCP、SSH、sudo 和常用诊断工具
- root 账户可直接登录（密码与普通用户相同）
- 4 GiB GPT raw image、`.img.zst`、SHA256 和元数据

当前内置的完整镜像板级配置只有
`rk3588-evb1-lp4-v10-linux`。其他开发板可以拉取源码，但在生成最终镜像前
必须增加匹配的 `configs/boards/<board>.conf`，并确认 DTB、U-Boot 和存储布局。

## 快速开始

宿主机需要 Docker Engine/Desktop、Docker Compose v2 和 GNU Make。Windows
建议在 Git Bash 或 WSL 中运行 `make`。

```bash
cp .env.example .env

make build
make build-debian-builder

# 1. 拉取 SDK（每个 BSP 使用独立 volume，互不干扰）
make fetch-510            # Rockchip Linux 5.10
# make fetch-radxa        # Radxa Rock 5B BSP
# make fetch-firefly      # Firefly AIO-3588 BSP
# make fetch-orangepi     # OrangePi 5 BSP

# 2. 构建 Buildroot 完整镜像
make build-all \
  BOARD=rk3588-evb1-lp4-v10-linux \
  ROOTFS=buildroot

# 3. 构建 Debian 13 完整镜像
make build-all \
  BOARD=rk3588-evb1-lp4-v10-linux \
  ROOTFS=debian \
  DEBIAN_RELEASE=13

# 4. 同时生成 Buildroot 和 Debian 13
make build-all \
  BOARD=rk3588-evb1-lp4-v10-linux \
  ROOTFS=all \
  DEBIAN_RELEASE=13
```

组件构建允许省略 `BOARD`，此时使用内置 EVB 示例配置。`image`、`pack` 和
`build-all` 必须显式提供 `BOARD`，防止把错误 DTB 或 bootloader 写入镜像。

Debian rootfs 在独立的 `linux/arm64` 容器中原生构建。x86_64 宿主机上
`make` 会自动通过 `tonistiigi/binfmt` 注册 ARM64 QEMU 模拟。`mmdebstrap`
构建期间需要在容器内创建临时挂载，因此 `debian-rootfs` 服务以 privileged
模式运行。只应在可信代码和可信构建主机上执行 Debian rootfs 构建。

## 多 SDK 源切换

每个 BSP 源码拉取到独立的 Docker volume，切换时不需要重新下载，也不会交叉
污染：

| 命令 | Volume | 说明 |
|---|---|---|
| `make fetch-510` | `rk3588-sdk-rockchip-5.10` | Rockchip Linux 5.10 LTS |
| `make fetch-61` | `rk3588-sdk-rockchip-6.1` | Rockchip Linux 6.1 LTS |
| `make fetch-66` | `rk3588-sdk-rockchip-6.6` | Rockchip Linux 6.6 |
| `make fetch-firefly` | `rk3588-sdk-firefly` | Firefly AIO-3588 BSP |
| `make fetch-radxa` | `rk3588-sdk-radxa` | Radxa Rock 5B BSP |
| `make fetch-orangepi` | `rk3588-sdk-orangepi` | OrangePi 5 BSP |

构建时通过 `SDK_VOLUME` 指定使用哪套 SDK：

```bash
# 用 Radxa SDK 构建
make build-kernel SDK_VOLUME=rk3588-sdk-radxa
make build-uboot  SDK_VOLUME=rk3588-sdk-radxa
make build-rootfs  SDK_VOLUME=rk3588-sdk-radxa ROOTFS=debian
make image         SDK_VOLUME=rk3588-sdk-radxa ROOTFS=debian

# 切回 Rockchip 5.10
make build-kernel SDK_VOLUME=rk3588-sdk-rockchip-5.10

# 更新指定 SDK
make update SDK_VOLUME=rk3588-sdk-radxa

# 查看所有 SDK volume
docker volume ls --filter name=rk3588
```

不传 `SDK_VOLUME` 时默认使用 `rk3588-sdk`。

## 输出目录

```text
output/<board>/
├── common/
│   ├── Image
│   ├── <board>.dtb
│   ├── kernel-release
│   ├── kernel.config
│   ├── modules.tar
│   ├── loader.bin
│   ├── uboot.img
│   └── *-build-info.txt
├── buildroot/
│   ├── rootfs.ext4
│   ├── rootfs.tar
│   ├── <board>-buildroot.img
│   ├── <board>-buildroot.img.zst
│   ├── <board>-buildroot.sha256
│   └── image-build-info.txt
└── debian-13/
    ├── rootfs.ext4
    ├── rootfs.tar
    ├── <board>-debian-13.img
    ├── <board>-debian-13.img.zst
    ├── <board>-debian-13.sha256
    └── image-build-info.txt
```

每次 `make image` 都会自动运行离线校验，包括 GPT 几何、bootloader 固定偏移、
FAT 中的 Kernel/DTB/extlinux、ext4 一致性、rootfs 标签、内核模块版本、开发
账户、root 登录状态和首次启动扩容钩子。

## 镜像布局

```text
sector 0                    Protective MBR / GPT
sector 64                   Rockchip loader
sector 16384                uboot.img
16 MiB .. 272 MiB           FAT32 boot partition
272 MiB .. image end        ext4 rootfs partition
```

rootfs 文件系统初始为 2 GiB，分区占用镜像剩余空间。首次启动服务调用
`resize2fs` 将文件系统扩展到整个 rootfs 分区。

## 默认登录

```text
username: rk3588
password: rk3588
root password: rk3588
```

可通过 `ROOTFS_USERNAME` 修改普通用户名称，`ROOTFS_PASSWORD` 同时修改普通用户
和 root 的密码。默认密码只适合隔离的开发网络，接入其他网络前必须更换。

## 常用命令

```bash
make help
make build
make build-debian-builder
make check

# 拉取 SDK
make fetch-510
make fetch-radxa
make update SDK_VOLUME=rk3588-sdk-radxa

# 组件构建
make build-kernel BOARD=rk3588-evb1-lp4-v10-linux
make build-uboot BOARD=rk3588-evb1-lp4-v10-linux
make build-rootfs BOARD=rk3588-evb1-lp4-v10-linux ROOTFS=buildroot

# 切换 SDK 源
make build-kernel SDK_VOLUME=rk3588-sdk-radxa
make build-uboot  SDK_VOLUME=rk3588-sdk-radxa

# 生成镜像
make image BOARD=rk3588-evb1-lp4-v10-linux ROOTFS=buildroot
make verify-image BOARD=rk3588-evb1-lp4-v10-linux ROOTFS=buildroot

# 一次性构建 Debian 11/12/13
make test-debian-all BOARD=rk3588-evb1-lp4-v10-linux

make shell                # 进入构建容器
make status               # 查看容器和 volume 状态
make clean                # 停止容器
make clean-all            # 停止容器并删除 volume 和镜像
```

`make test-debian-all` 会复用一次 Kernel/U-Boot 构建，依次生成并校验 Debian
11、12、13 镜像。

## 写入存储介质

先核对目标设备名，写错设备会覆盖宿主机磁盘：

```bash
zstd -d output/<board>/<variant>/<board>-<variant>.img.zst
sudo dd if=output/<board>/<variant>/<board>-<variant>.img \
  of=/dev/sdX bs=4M status=progress conv=fsync
```

本项目只生成 SD/eMMC 使用的 raw GPT 镜像，不生成 Rockchip `update.img`，
也不处理 SPI NAND、桌面环境、Mali/MPP/RKNPU 用户态组件。

## 源码与板级适配

六个 manifest 都包含官方 Buildroot `2025.02.15`：

```text
kernel/       Rockchip 或板厂内核
u-boot/       Rockchip 或板厂 U-Boot
rkbin/        DDR init、TF-A、OP-TEE 等预编译固件和打包工具
buildroot/    官方 Buildroot 固定版本
```

板级差异集中在 `configs/boards/`。新增板卡时至少要确认：

- `KERNEL_DTB` 与实际硬件一致
- U-Boot `make.sh` 参数和 loader 文件匹配
- 串口设备与波特率正确
- SD/eMMC 控制器在 Kernel 和 DTB 中启用
- loader、U-Boot、boot 分区的偏移没有重叠

## 许可证

分发镜像时需要同时处理 Kernel、U-Boot、Buildroot/Debian 软件包及 rkbin
固件各自的许可证义务。Kernel/U-Boot 的 GPL 源码提供义务不会因为使用容器
构建而消失。
