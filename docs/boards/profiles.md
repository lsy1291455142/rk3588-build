# 已支持板型

镜像构建由板级 profile 与共享内核 fragment 驱动。

## 内置 profile

```text
configs/boards/rk3588-evb1-lp4-v10-linux.conf
configs/boards/rk3588s-rock-5c.conf
configs/boards/rk3588-cokepi-plus-lp4-v10.conf
configs/boards/rk3588s-cokepi-model-lp4-v10.conf
configs/boards/rk3588-muse.conf
```

| `BOARD` | 硬件 | 配套 `SDK_VOLUME` | 源码来源 |
|---|---|---|---|
| `rk3588s-rock-5c` | Radxa ROCK 5C | `rk3588-sdk-rock5c` | `make fetch-rock5c`（锁定 commit） |
| `rk3588-evb1-lp4-v10-linux` | Rockchip EVB1 LP4 V1.0 | `rk3588-sdk-rockchip-5.10` | `make fetch-510` |
| `rk3588-cokepi-plus-lp4-v10` | CokePi Plus（RK3588） | `rk3588-sdk-cokepi-rkr9` | 本地 `import-local-sdk` |
| `rk3588s-cokepi-model-lp4-v10` | CokePi Model（RK3588S） | `rk3588-sdk-cokepi-rkr9` | 本地 `import-local-sdk` |
| `rk3588-muse` | MUSE RK3588（eMMC） | `rk3588-sdk-muse-5.10` | `make fetch-muse` |

CokePi 两套 profile 分别使用 SDK 中 HDMI 设备树：

- Plus：`rk3588-cpp-hdmi.dtb`
- Model：`rk3588s-cpm-hdmi1.dtb`

按板卡丝印选择，Plus 与 Model 不可混用。

## 主要字段

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

所有组件与镜像目标都要求显式 `BOARD=<profile 文件名去掉 .conf>`，无默认板型。

## 布局约束

loader 与 U-Boot 区域必须位于 `BOOT_START_MIB` 之前。当前约定：

- 前 16 MiB 预留 bootloader
- IDBlock：sector 64
- `uboot.img`：sector 16384
- FAT boot：自 16 MiB 起，默认 256 MiB

## 内核 fragment

`configs/kernel/rootfs-base.config` 在板级 defconfig 之后合并，启用 Buildroot / Debian 所需的最小能力（ext4、MMC、devtmpfs、namespaces、cgroups 等）。

板级专用内核选项应放在 BSP defconfig 或额外板级适配中，不要堆进该共享 baseline。
