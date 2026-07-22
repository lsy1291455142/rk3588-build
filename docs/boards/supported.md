# 已支持板型

## 总览

| Profile | 硬件 | SoC | 内核 defconfig | DTB | U-Boot Python | SOURCE_MANIFEST |
|---|---|---|---|---|---|---|
| `rk3588-evb1-lp4-v10-linux` | Rockchip EVB1 | RK3588 | rockchip_linux_defconfig | rk3588-evb1-lp4-v10-linux.dtb | python3 | `rk3588-linux-5.10.xml` |
| `rk3588s-rock-5c` | Radxa ROCK 5C | RK3588S | rockchip_linux_defconfig | rk3588s-rock-5c.dtb | python3 | `rk3588-rock5c.xml`（commit 锁定） |
| `rk3588-cokepi-plus-lp4-v10` | CokePi Plus | RK3588 | cokepi_main_defconfig | rk3588-cpp-hdmi.dtb | python2 | 无（本地 SDK） |
| `rk3588s-cokepi-model-lp4-v10` | CokePi Model | RK3588S | cokepi_main_defconfig | rk3588s-cpm-hdmi1.dtb | python2 | 无（本地 SDK） |
| `rk3588-muse` | MUSE RK3588 | RK3588 | rockchip_linux_defconfig | rk3588-muse.dtb | python3 | `rk3588-muse-5.10.xml` |

所有板型共享：GPT 布局、IDBlock sector 64、U-Boot sector 16384、boot 起始 16 MiB、boot 大小 256 MiB、镜像总大小默认 2048 MiB、rootfs 初始大小 1700 MiB、串口 ttyFIQ0 @ 1500000。

## Rockchip EVB1

Profile：`rk3588-evb1-lp4-v10-linux`

Rockchip 官方参考板，使用标准的 `rockchip_linux_defconfig` 和 `rk3588_defconfig`。适合作为新板型的参考起点。

推荐 SDK：

```bash
make fetch BOARD=rk3588-evb1-lp4-v10-linux
# 默认 SOURCE_MANIFEST=rk3588-linux-5.10.xml
```

若要用 6.1 / 6.6：

```bash
make fetch-custom SDK_VOLUME=rk3588-sdk-linux-6.1 MANIFEST=rk3588-linux-6.1.xml
make use-volume
make use-board BOARD=rk3588-evb1-lp4-v10-linux
```

## Radxa ROCK 5C

Profile：`rk3588s-rock-5c`

Radxa ROCK 5C（RK3588S），是唯一做了全量版本锁定的板型。manifest `rk3588-rock5c.xml` 把 kernel、u-boot、rkbin、buildroot 全部锁定到具体 commit，profile 里的 `EXPECTED_*_REVISION` 会在构建前强制校验。

这是本项目的「黄金路径」，推荐首次使用时选择。

```bash
make fetch BOARD=rk3588s-rock-5c
```

## CokePi Plus / CokePi Model

Profile：`rk3588-cokepi-plus-lp4-v10` / `rk3588s-cokepi-model-lp4-v10`

CokePi 两块板共用同一个 SDK，但设备树不同（Plus 是 `rk3588-cpp-hdmi.dtb`，Model 是 `rk3588s-cpm-hdmi1.dtb`）。不可混用 profile，必须按板子丝印选择。

U-Boot 编译需要 Python 2（`UBOOT_PYTHON=python2`），Docker 镜像已内置。

SDK 来源：本地导入（CokePi SDK 不在公开仓库）：

```bash
make import-local-sdk SDK_PATH=/path/to/cokepi-sdk SDK_VOLUME=rk3588-sdk-cokepi-rkr9
make verify-sdk-volume SDK_VOLUME=rk3588-sdk-cokepi-rkr9
make use-board BOARD=rk3588s-cokepi-model-lp4-v10
```

额外的内核参数：`irqchip.gicv3_pseudo_nmi=0 rcupdate.rcu_expedited=1 rcu_nocbs=all`。

## MUSE RK3588

Profile：`rk3588-muse`

MUSE RK3588 开发板（eMMC 启动，LPDDR4X，RK806 + RK860x 电源管理）。内核来自 MUSEInstitute fork 的 `develop-5.10` 分支。

Debian 默认 `DEBIAN_PACKAGES_DEFAULT="network-manager,wpasupplicant,i2c-tools,usbutils,pciutils,mmc-utils"`，hostname 默认 `muse`。

```bash
make fetch BOARD=rk3588-muse
```

注意：DDR 初始化依赖 rkbin 中的 blob，manifest 拉取后建议确认 rkbin 使用了支持 LP4X 的 DDR 固件。
