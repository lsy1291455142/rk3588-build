# RK3588 完整系统镜像构建环境

这个项目用 Docker 拉取 RK3588 BSP，并构建可直接写入 SD 卡或 eMMC 的完整
GPT 原始镜像。流程不再只输出 `Image`、DTB 和 U-Boot，还会生成 Buildroot
或 Debian 根文件系统、`extlinux.conf`、压缩镜像、校验和与构建元数据。

新手建议先阅读：[RK3588 开发板完整系统镜像构建流程](docs/RK3588_SYSTEM_IMAGE_BUILD_FLOW.md)。

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
make fetch-510

# Buildroot 完整镜像
make build-all \
  BOARD=rk3588-evb1-lp4-v10-linux \
  ROOTFS=buildroot

# Debian 13 完整镜像
make build-debian-builder
make build-all \
  BOARD=rk3588-evb1-lp4-v10-linux \
  ROOTFS=debian \
  DEBIAN_RELEASE=13

# 同时生成 Buildroot 和指定 Debian 版本
make build-debian-builder
make build-all \
  BOARD=rk3588-evb1-lp4-v10-linux \
  ROOTFS=all \
  DEBIAN_RELEASE=13
```

组件构建允许省略 `BOARD`，此时使用内置 EVB 示例配置。`image`、`pack` 和
`build-all` 必须显式提供 `BOARD`，防止把错误 DTB 或 bootloader 写入镜像。

Debian rootfs 在独立的 `linux/arm64` 容器中原生构建。Docker Desktop 通常已
提供 ARM64 模拟；Linux x86_64 主机需要先启用 ARM64/binfmt。`make` 会在执行
Debian 构建前检查容器架构并给出明确错误。

`mmdebstrap` 构建期间需要在容器内创建临时挂载，因此 `debian-rootfs` 服务以
privileged 模式运行。只应在可信代码和可信构建主机上执行 Debian rootfs 构建。

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
账户、root 锁定状态和首次启动扩容钩子。

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
make build-builder
make build-debian-builder

make fetch
make fetch-510
make fetch-61
make fetch-66
make update

make build-kernel BOARD=rk3588-evb1-lp4-v10-linux
make build-uboot BOARD=rk3588-evb1-lp4-v10-linux
make build-rootfs BOARD=rk3588-evb1-lp4-v10-linux ROOTFS=buildroot

make image BOARD=rk3588-evb1-lp4-v10-linux ROOTFS=buildroot
make verify-image BOARD=rk3588-evb1-lp4-v10-linux ROOTFS=buildroot
make pack BOARD=rk3588-evb1-lp4-v10-linux ROOTFS=buildroot

make test-debian-all BOARD=rk3588-evb1-lp4-v10-linux
make check
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
rkbin/        DDR init 和 TF-A 等固件
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
