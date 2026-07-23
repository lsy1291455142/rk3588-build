# 已支持板型

本页列出仓库内置的板型 profile（位于 `boards/`，不含 `TEMPLATE`）。每个板型是一个目录，含 `board.conf`（必需）、可选的 `kernel.config`、`rootfs/`、`check.sh`。运行 `make list-boards` 可随时查看。

所有板型共用 SoC 族 `rk3588`（加载 `configs/soc/rk3588.conf`），统一 `BOOTLOADER_LAYOUT=rockchip-gpt-idblock-extlinux-v1`，磁盘几何默认 `IMAGE_SIZE_MIB=2048` / `BOOT_START_MIB=16` / `BOOT_SIZE_MIB=256` / `ROOTFS_SIZE_MIB=1700`，串口 `ttyFIQ0,1500000n8`。下表中仅列出有差异或值得注意的字段。

## 总览

| Profile | 描述 | 内核 defconfig | DTB | U-Boot defconfig / board | SDK 来源 |
|---|---|---|---|---|---|
| `rk3588-evb1-lp4-v10-linux` | Rockchip RK3588 EVB1 LP4 V1.0 参考板 | `rockchip_linux_defconfig` | `rk3588-evb1-lp4-v10-linux.dtb` | `rk3588_defconfig` / `rk3588` | `rk3588-linux-5.10.xml` |
| `rk3588s-rock-5c` | Radxa ROCK 5C (RK3588S) | `rockchip_linux_defconfig` | `rk3588s-rock-5c.dtb` | `rock-5c-rk3588s_defconfig` / `rock-5c-rk3588s` | `rk3588-rock5c.xml`（全量锁 commit） |
| `rk3588-cokepi-plus-lp4-v10` | CokePi Plus LP4 V1.0 (RK3588) | `cokepi_main_defconfig` | `rk3588-cpp-hdmi.dtb` | `rk3588_defconfig` / `rk3588` | 本地导入（无 `SOURCE_MANIFEST`） |
| `rk3588s-cokepi-model-lp4-v10` | CokePi Model LP4 V1.0 (RK3588S) | `cokepi_main_defconfig` | `rk3588s-cpm-hdmi1.dtb` | `rk3588_defconfig` / `rk3588` | 本地导入（无 `SOURCE_MANIFEST`） |
| `rk3588-muse` | MUSE RK3588 (eMMC, LPDDR4X, RK806+RK860x) | `rockchip_linux_defconfig` | `rk3588-muse.dtb` | `rk3588_defconfig` / `rk3588` | `rk3588-muse-5.10.xml` |

## Rockchip EVB1

- `BOARD_DESCRIPTION`: `Rockchip RK3588 EVB1 LP4 V1.0 Linux reference profile`
- `SOURCE_MANIFEST`: `rk3588-linux-5.10.xml`（官方 5.10 SDK，可用 `make fetch-custom` 换 6.1/6.6）
- `UBOOT_PYTHON`: `python3`
- `ROOTFS_HOSTNAME_DEFAULT`: `rk3588-evb1`
- `DEBIAN_PACKAGES_DEFAULT`: `network-manager,wpasupplicant,i2c-tools,usbutils,pciutils,mmc-utils`
- 其余用通用默认（`DEBIAN_OVERLAYS_DEFAULT=base,console,firstboot,firstboot-info,network`，几何默认）

## Radxa ROCK 5C

- `BOARD_DESCRIPTION`: `Radxa Rock 5C (RK3588S)`
- `SOURCE_MANIFEST`: `rk3588-rock5c.xml`，并锁定四个组件 commit：
  - `EXPECTED_KERNEL_REVISION=567401fe17185f0f4a65866158b775a364feb2d3`
  - `EXPECTED_UBOOT_REVISION=4218b05a597f458947f0f4706063b3bb819e07c`
  - `EXPECTED_RKBIN_REVISION=ecb4fcbe954edf38b3ae037d5de6d9f5bccf81f4`
  - `EXPECTED_BUILDROOT_REVISION=c49ae7216786d3cb62a8e8de5556007b4b539233`
- `UBOOT_PYTHON`: `python3`
- `ROOTFS_HOSTNAME_DEFAULT`: `rock5c`
- 提供 `check.sh`（板级自检钩子）
- 这是文档与测试的主要参考实现

## CokePi Plus / CokePi Model

- 二者均**不设置 `SOURCE_MANIFEST`**，需本地 SDK 导入：`make import-local-sdk SDK_PATH=/path/to/cokepi-sdk SDK_VOLUME=rk3588-sdk-cokepi-rkr9`。
- `KERNEL_DEFCONFIG=cokepi_main_defconfig`，`UBOOT_PYTHON=python2`（Rockchip CokePi U-Boot 需要 Python 2；构建器镜像内置 Python 2.7 与 pyelftools）。
- `EXTRA_KERNEL_ARGS` 含 `irqchip.gicv3_pseudo_nmi=0 rcupdate.rcu_expedited=1 rcu_nocbs=all`。
- CokePi Model 额外：`ROOTFS_MODE_DEFAULT="ro-overlay"`（默认构建只读 overlay 镜像），并有板级 `kernel.config` 由 `build_kernel.sh` 自动合并；其 `rootfs/` 通过 `plugin.sh` 安装 AIC8800D80 固件（来自 `packages/` 本地 `.deb`，需先运行 `stage-aic8800-firmware.sh`）。
- CokePi Model `DEBIAN_PACKAGES_DEFAULT` 在通用集合基础上追加 `htop`；`ROOTFS_HOSTNAME_DEFAULT=cokepi`。

## MUSE RK3588

- `BOARD_DESCRIPTION`: `MUSE RK3588 (eMMC boot, LPDDR4X, RK806 single + RK860x)`
- `SOURCE_MANIFEST`: `rk3588-muse-5.10.xml`（MUSE 维护的 fork）
- `UBOOT_PYTHON`: `python3`
- `ROOTFS_HOSTNAME_DEFAULT`: `muse`
- 通用默认 `DEBIAN_PACKAGES_DEFAULT` / `DEBIAN_OVERLAYS_DEFAULT`

## 关于版本锁定

`common.sh` 的 `validate_board_profile` 规定：一旦设置 `SOURCE_MANIFEST`，四个 `EXPECTED_*_REVISION` 必须为 40 位完整 Git SHA，否则校验失败。`make fetch` 拉取后也会比对。`rk3588s-rock-5c` 已填写全部四个；其它以 manifest 为源的板型（`evb1`、`muse`）在随附 profile 中未包含 `EXPECTED_*_REVISION`——若需启用 commit 锁定，应在对应 `board.conf` 中补全这些字段。CokePi 系列因走本地导入路径，不涉及此校验。
