# RK3588 Linux BSP Docker Build Environment

本项目提供一个基于 Docker 的 RK3588 BSP 编译与构建环境，支持一键生成可直接烧录至 SD 卡或 eMMC 的完整 GPT 格式系统镜像。构建流程不仅输出 U-Boot、内核 `Image` 和设备树（DTB），还会完整集成 Buildroot 或 Debian 根文件系统、`extlinux` 引导配置，并自动完成镜像打包、压缩与校验。

新手建议先阅读：[RK3588 开发板完整系统镜像构建流程](docs/RK3588_SYSTEM_IMAGE_BUILD_FLOW.md)。

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/lsy1291455142/rk3588-build)

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
- 同一 builder 同时提供 Python 2/3，并按 BOARD profile 选择 U-Boot 解释器
- U-Boot GPT/extlinux 启动能力与签名策略构建时校验
- Buildroot `2025.02.15`
- Debian 11/bullseye、12/bookworm、13/trixie，默认 Debian 13
- `ROOTFS=buildroot`、`ROOTFS=debian`、`ROOTFS=all`
- FAT32 boot 分区、extlinux、ext4 rootfs
- 首次启动在线扩展 rootfs
- 串口、DHCP、SSH、sudo 和常用诊断工具
- root 账户可直接登录（密码与普通用户相同）
- 4 GiB GPT raw image、`.img.zst`、SHA256 和元数据

当前内置以下完整镜像板级配置：

| `BOARD` | 开发板 | 配套 SDK |
|---|---|---|
| `rk3588-evb1-lp4-v10-linux` | Rockchip RK3588 EVB1 LP4 V1.0 | `rk3588-sdk-rockchip-5.10` |
| `rk3588-cokepi-plus-lp4-v10` | CokePi Plus LP4 V1.0 (RK3588) | `rk3588-sdk-cokepi-rkr9`（本地导入） |
| `rk3588s-rock-5c` | Radxa ROCK 5C | `rk3588-sdk-rock5c` |
| `rk3588s-cokepi-model-lp4-v10` | CokePi Model LP4 V1.0 (RK3588S) | `rk3588-sdk-cokepi-rkr9`（本地导入） |

其他开发板可以拉取源码，但在生成最终镜像前必须增加匹配的
`configs/boards/<board>.conf`，并确认 DTB、U-Boot 和存储布局。

## 快速开始

宿主机需要 Docker Engine/Desktop、Docker Compose v2 和 GNU Make。Windows
建议在 Git Bash 或 WSL 中运行 `make`。

运行 `make help` 可以看到经过测试的完整命令。构建 ROCK 5C Debian 13 时，
不需要手工创建 Docker volume，或在宿主机安装 QEMU 和交叉编译器。`BOARD` 和
`SDK_VOLUME` 是分开设置的：既可命令行显式传入，也可分别用 `make use-volume-*` 和
`make use-board-*` 写入 `.env`：

```bash
make build
make fetch-rock5c
make use-volume-rock5c
make use-board-rock5c
# 也可以: make use-volume && make use-board
make build-all ROOTFS=debian DEBIAN_RELEASE=13
make test-debian-qemu DEBIAN_RELEASE=13
```

也可以不使用 `.env`，直接在命令中指定：

```bash
make build-all \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  ROOTFS=debian \
  DEBIAN_RELEASE=13
```

所有组件构建和最终镜像都要求显式 `BOARD`，不会再回落到默认 EVB 板型。

Debian rootfs 在独立的 `linux/arm64` 容器中构建。`make build-rootfs ROOTFS=debian`
和 `make build-all ROOTFS=debian` 会自动准备该 builder：x86_64 Docker 主机通过
`tonistiigi/binfmt` 注册 ARM64 QEMU 模拟，ARM64 Docker 主机直接原生运行。
`make build-debian-builder` 仍可用于单独预构建或刷新 builder。`mmdebstrap`
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
| `make fetch-rock5c` | `rk3588-sdk-rock5c` | Radxa Rock 5C BSP |
| `make fetch-orangepi` | `rk3588-sdk-orangepi` | OrangePi 5 BSP |

自定义本地 manifest：

```bash
make fetch-custom \
  SDK_VOLUME=rk3588-sdk-cokepi \
  MANIFEST=rk3588-cokepi.xml
```

自定义远程 manifest 仓库：

```bash
make fetch-custom \
  SDK_VOLUME=rk3588-sdk-custom \
  CUSTOM_MANIFEST_URL=https://example.com/manifests.git \
  CUSTOM_MANIFEST_NAME=cokepi.xml
```

没有交互式 SDK 选择。每次拉取必须通过明确的 `fetch-*` target 或
`fetch-custom` 指定 manifest 和 volume，避免源码混用。

### 导入已经下载的本地 SDK

如果宿主机上已经有完整 SDK，不要先复制到普通 Docker volume。大型 BSP 通常
占用 20 GB 以上，复制会额外占用同等磁盘空间。项目可以创建一个由宿主机目录
支撑的命名 volume，Compose 仍然通过统一的 `SDK_VOLUME` 接口使用它：

```bash
make build
make import-local-sdk \
  SDK_PATH=/absolute/path/to/rk3588-sdk \
  SDK_VOLUME=rk3588-sdk-cokepi
make verify-sdk-volume SDK_VOLUME=rk3588-sdk-cokepi
```

导入命令要求 SDK 根目录直接包含 `kernel/`、`u-boot/`、`rkbin/` 和
`buildroot/`，并自动把 `SDK_VOLUME` 写入 `.env`。源码不会复制；容器中的
`/home/builder/sdk` 直接映射到宿主机目录，构建缓存目录 `.rk3588-build/` 也会
写在该 SDK 根目录下。删除 Docker volume 不会删除宿主机 SDK，但移动或删除
宿主机目录会使 volume 失效。Docker daemon 必须能够访问传入的绝对路径。

本地 SDK volume 只解决源码接入。新开发板仍需在 `configs/boards/` 增加与硬件
匹配的 profile，明确指定内核 DTB 和 U-Boot 配置，然后再设置 `BOARD`。

当前本机的 CokePi RKR9 SDK 可以直接导入并验证：

```bash
make import-local-sdk \
  SDK_PATH=/root/downloads/rk3588_linux-5.10-cokepi-rkr9/rk3588_linux-5.10-cokepi-rkr9 \
  SDK_VOLUME=rk3588-sdk-cokepi-rkr9
make verify-cokepi-sdk SDK_VOLUME=rk3588-sdk-cokepi-rkr9
```

根据开发板丝印二选一，命令只修改 `BOARD`，不会修改已经导入的 SDK volume：

```bash
# RK3588 CokePi Plus
make use-board-cokepi-plus

# RK3588S CokePi Model
make use-board-cokepi-model
```

两套 profile 分别采用 SDK 中面向 HDMI 输出的 `rk3588-cpp-hdmi.dtb` 和
`rk3588s-cpm-hdmi1.dtb`。应按实物型号选择，不能把 Plus 与 Model 混用。

构建时通过 `SDK_VOLUME` 和 `BOARD` 指定 SDK 与板型。二者分开写入 `.env`，
之后命令自动继承：

```bash
# 分别写入 SDK volume 和 board
# 交互选择：
make use-volume
make use-board
# 或快捷目标：
make use-volume-rock5c
make use-board-rock5c
make use-current

# 用 Rock 5C SDK + Rock 5C board 构建
make build-kernel
make build-uboot
make build-rootfs ROOTFS=debian
make image

# 也可以临时覆盖
make build-kernel BOARD=rk3588s-rock-5c SDK_VOLUME=rk3588-sdk-rock5c

# 切回 Rockchip 5.10 SDK 与 EVB board
make use-volume-rockchip-5.10
make use-board-evb1
make build-kernel

# 更新指定 SDK
make update SDK_VOLUME=rk3588-sdk-radxa

# 查看所有 SDK volume
docker volume ls --filter name=rk3588
```

`SDK_VOLUME` 与 `BOARD` 都必须通过 `.env`、对应的 `use-volume-*` / `use-board-*`
或命令行显式设置。没有默认板型，也不会互相覆盖。

`make image` 和 `make verify-image` 在命令行及 `.env` 都未设置 `ROOTFS` 时，
会根据当前板型已有的 `rootfs.ext4` 自动选择 Buildroot 或 Debian。若两种 rootfs
同时存在，则必须显式传入 `ROOTFS=buildroot` 或 `ROOTFS=debian`，避免打包错误系统。

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
账户、root 登录状态、首次启动扩容钩子、锁定源码 revision 和 QEMU 所需内核
配置。

`make test-debian-qemu` 使用构建出的同一个 Kernel 和完整 raw GPT 镜像，在
ARM64 `virt` 机器上验证 Debian 13 能到达串口登录、systemd 无失败单元、首次
扩容成功、网络和 SSH 可用。QEMU 不能模拟 RK3588 的 DDR、PMIC、MMC 控制器
和真实 loader/U-Boot，因此开发板串口启动仍是最终硬件验收。

## 镜像布局

```text
sector 0                    Protective MBR / GPT
sector 64                   Rockchip loader
sector 16384                uboot.img
16 MiB .. 272 MiB           FAT32 boot partition
272 MiB .. image end        ext4 rootfs partition
```

rootfs 文件系统初始为 2 GiB，分区占用镜像剩余空间。Debian 首次启动时使用
`sgdisk -e` 修复备份 GPT，使用 `growpart` 将 rootfs 分区扩展到磁盘末尾，
再通过 `resize2fs` 扩展 ext4 文件系统。

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
make build-debian-builder  # 可选：提前构建/刷新 ARM64 Debian builder
make check

# 拉取 SDK
make fetch-510
make fetch-radxa
make fetch-rock5c
make update SDK_VOLUME=rk3588-sdk-radxa

# 组件构建
make use-volume-rockchip-5.10
make use-board-evb1
make build-kernel
make build-uboot
make build-rootfs ROOTFS=buildroot

# 切换 SDK 源
make use-volume-rock5c
make use-board-rock5c
make build-kernel
make build-uboot

# 生成镜像
make use-volume-rockchip-5.10
make use-board-evb1
make image ROOTFS=buildroot
make verify-image ROOTFS=buildroot
make test-debian-qemu \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  DEBIAN_RELEASE=13

# 一次性构建 Debian 11/12/13
make use-volume-rockchip-5.10
make use-board-evb1
make test-debian-all

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

七个 manifest 都包含官方 Buildroot `2025.02.15`：

```text
kernel/       Rockchip 或板厂内核
u-boot/       Rockchip 或板厂 U-Boot
rkbin/        DDR init、TF-A、OP-TEE 等预编译固件和打包工具
buildroot/    官方 Buildroot 固定版本
```

板级差异集中在 `configs/boards/`。新增板卡时至少要确认：

- `KERNEL_DTB` 与实际硬件一致
- U-Boot `make.sh` 参数、`UBOOT_PYTHON` 和 loader 文件匹配
- 串口设备与波特率正确
- SD/eMMC 控制器在 Kernel 和 DTB 中启用
- loader、U-Boot、boot 分区的偏移没有重叠

`UBOOT_PYTHON` 必须在 BOARD profile 中显式设置为 `python2` 或 `python3`。
builder 全局保持 `python -> python3`；U-Boot 构建只在当前进程内让裸 `python`
指向所选版本，因此旧 BSP 与新 BSP 可以复用同一个镜像。

## 许可证

分发镜像时需要同时处理 Kernel、U-Boot、Buildroot/Debian 软件包及 rkbin
固件各自的许可证义务。Kernel/U-Boot 的 GPL 源码提供义务不会因为使用容器
构建而消失。
