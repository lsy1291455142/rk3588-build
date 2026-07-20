# configs/

镜像构建由板级 profile 与共享内核 fragment 驱动。

## 板级 profile（`boards/`）

当前内置：

```text
configs/boards/rk3588-evb1-lp4-v10-linux.conf
configs/boards/rk3588s-rock-5c.conf
configs/boards/rk3588-cokepi-plus-lp4-v10.conf
configs/boards/rk3588s-cokepi-model-lp4-v10.conf
configs/boards/rk3588-muse.conf
```

| Profile | 硬件 | 说明 |
|---|---|---|
| `rk3588-evb1-lp4-v10-linux` | Rockchip EVB1 | 参考板；`UBOOT_PYTHON=python3` |
| `rk3588s-rock-5c` | Radxa ROCK 5C | 锁定 manifest 中各仓库 commit |
| `rk3588-cokepi-plus-lp4-v10` | CokePi Plus（RK3588） | `KERNEL_DTB=rk3588-cpp-hdmi.dtb`；需本地 CokePi SDK |
| `rk3588s-cokepi-model-lp4-v10` | CokePi Model（RK3588S） | `KERNEL_DTB=rk3588s-cpm-hdmi1.dtb`；需本地 CokePi SDK |
| `rk3588-muse` | MUSE RK3588（eMMC） | `KERNEL_DTB=rk3588-muse.dtb`；kernel 来自 `MUSEInstitute/kernel` `develop-5.10` |

CokePi Plus 与 Model 使用同一 SDK volume 时仍须按丝印选择不同 profile，不可混用。项目 profile 选用 SDK 中 HDMI 设备树变体。

### 主要字段

| 字段 | 作用 |
|---|---|
| `KERNEL_DEFCONFIG` | BSP 内核 defconfig |
| `KERNEL_DTB` | 唯一打包的 DTB 文件名 |
| `UBOOT_DEFCONFIG` / `UBOOT_BOARD` | U-Boot 配置与 `make.sh` 板名 |
| `UBOOT_BUILD_SYSTEM` | 当前为 `rockchip-make-sh` |
| `UBOOT_PYTHON` | `python2` 或 `python3`，必填 |
| `BOOTLOADER_LAYOUT` | 当前为 `rockchip-gpt-idblock-extlinux-v1` |
| `DOWNLOAD_LOADER_GLOBS` / `UBOOT_IMAGE_NAMES` | 产物匹配 |
| `IDBLOCK_SECTOR` / `UBOOT_SECTOR` | 默认 64 / 16384 |
| `CONSOLE` / `EXTRA_KERNEL_ARGS` | 写入 extlinux |
| `IMAGE_SIZE_MIB` / `BOOT_START_MIB` / `BOOT_SIZE_MIB` / `ROOTFS_SIZE_MIB` | 镜像几何 |

可选锁定 revision（如 ROCK 5C）：`EXPECTED_KERNEL_REVISION` 等；`SOURCE_MANIFEST` 记录对应 manifest。

所有组件与镜像目标都要求显式 `BOARD=<profile 文件名去掉 .conf>`，无默认板型。新增硬件时复制最接近的 profile 再改字段。

### 布局约束

loader 与 U-Boot 区域必须位于 `BOOT_START_MIB` 之前。当前约定：

- 前 16 MiB 预留 bootloader
- IDBlock：sector 64
- `uboot.img`：sector 16384
- FAT boot：自 16 MiB 起，默认 256 MiB

## 内核 fragment（`kernel/`）

`configs/kernel/rootfs-base.config` 在板级 defconfig 之后合并，启用 Buildroot / Debian 所需的最小能力（ext4、MMC、devtmpfs、namespaces、cgroups 等）。

板级专用内核选项应放在 BSP defconfig 或额外板级适配中，不要堆进该共享 baseline。

## Debian 可选功能（rootfs）

构建 Debian 时可通过环境变量 `DEBIAN_FEATURES` 预装功能集（逗号分隔）。
未指定时：若板级设了 `DEBIAN_FEATURES_DEFAULT` 则用板级默认，否则 minbase。
显式 `DEBIAN_FEATURES=none`（或 `minbase` / `off` / `-`）强制 minbase。

| Token | 内容 |
|---|---|
| `nm` | NetworkManager + `nmtui`（替代 systemd-networkd 作为主网络栈） |
| `hwdebug` | `i2c-tools` `usbutils` `pciutils` `mmc-utils` |
| `tools` | `tmux` `htop` `strace` |
| `firstboot-info` | 首次启动串口摘要 + MOTD/登录提示（不装额外 deb） |
| `all` | 以上全部 |

板级 profile 可设默认值（仅当 CLI/env 未指定时生效）：

```bash
DEBIAN_FEATURES_DEFAULT="nm,hwdebug,firstboot-info"
ROOTFS_HOSTNAME_DEFAULT="muse"
```

示例：

```bash
make build-rootfs DEBIAN_FEATURES=nm,hwdebug,firstboot-info
make build-rootfs DEBIAN_FEATURES=all ROOTFS_HOSTNAME=muse
# 强制 minbase，覆盖板级默认
make build-rootfs DEBIAN_FEATURES=none
```

`rootfs-build-info.txt` 会记录 `debian_features` 与 `network_stack`。

