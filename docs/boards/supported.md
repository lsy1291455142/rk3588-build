# 已支持板型

`BOARD` 对应 `configs/boards/<BOARD>.conf` 文件名（去掉 `.conf`）。构建时**没有默认板**。

## 一览

| `BOARD` | 硬件 | 配套 `SDK_VOLUME` | SDK 来源 | 备注 |
|---|---|---|---|---|
| `rk3588s-rock-5c` | Radxa ROCK 5C | `rk3588-sdk-rock5c` | `make fetch-rock5c` | 公开源入门路径；profile 锁定 commit |
| `rk3588-evb1-lp4-v10-linux` | Rockchip EVB1 LP4 V1.0 | `rk3588-sdk-rockchip-5.10` | `make fetch-510` | 参考板；`UBOOT_PYTHON=python3` |
| `rk3588-cokepi-plus-lp4-v10` | CokePi Plus（RK3588） | `rk3588-sdk-cokepi-rkr9` | `import-local-sdk` | DTB：`rk3588-cpp-hdmi.dtb` |
| `rk3588s-cokepi-model-lp4-v10` | CokePi Model（RK3588S） | `rk3588-sdk-cokepi-rkr9` | `import-local-sdk` | DTB：`rk3588s-cpm-hdmi1.dtb` |
| `rk3588-muse` | MUSE RK3588（eMMC） | `rk3588-sdk-muse-5.10` | `make fetch-muse` | kernel fork；默认 Debian features |

CokePi Plus 与 Model 可共用同一 SDK volume，但 **BOARD 不可混用**（DTB 不同）。按板卡丝印选 profile。

## 快捷切换

```bash
make use-board-rock5c
make use-board-evb1
make use-board-cokepi-plus
make use-board-cokepi-model
make use-board-muse
make use-board            # 交互选择
make use-current
```

## 各板要点

### ROCK 5C（`rk3588s-rock-5c`）

- 推荐第一次跑通整条链路
- `SOURCE_MANIFEST=rk3588-rock5c.xml`，并有 `EXPECTED_*_REVISION`
- U-Boot：`rock-5c-rk3588s_defconfig` / board `rock-5c-rk3588s`
- DTB：`rk3588s-rock-5c.dtb`

```bash
make fetch-rock5c
make build-all \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  ROOTFS=debian \
  DEBIAN_RELEASE=13
```

### EVB1（`rk3588-evb1-lp4-v10-linux`）

- Rockchip 参考布局；常与 Buildroot 搭配验证
- DTB：`rk3588-evb1-lp4-v10-linux.dtb`

```bash
make fetch-510
make build-all \
  BOARD=rk3588-evb1-lp4-v10-linux \
  SDK_VOLUME=rk3588-sdk-rockchip-5.10 \
  ROOTFS=buildroot
```

### CokePi Plus / Model

- SDK 无法公开拉取，需本地解压后 `import-local-sdk`
- Plus：`rk3588-cpp-hdmi.dtb`；Model：`rk3588s-cpm-hdmi1.dtb`
- `UBOOT_PYTHON=python2`

```bash
make import-local-sdk \
  SDK_PATH=/absolute/path/to/rk3588_linux-5.10-cokepi-rkr9 \
  SDK_VOLUME=rk3588-sdk-cokepi-rkr9
make verify-cokepi-sdk SDK_VOLUME=rk3588-sdk-cokepi-rkr9
make build-all \
  BOARD=rk3588s-cokepi-model-lp4-v10 \
  SDK_VOLUME=rk3588-sdk-cokepi-rkr9 \
  ROOTFS=debian \
  DEBIAN_RELEASE=13
```

### MUSE（`rk3588-muse`）

- kernel：`MUSEInstitute/kernel` 的 `develop-5.10`，需有 `rk3588-muse.dts` → `rk3588-muse.dtb`
- u-boot / rkbin 走 Rockchip 公开仓（`make fetch-muse`）
- 板级默认：`DEBIAN_FEATURES_DEFAULT=nm,hwdebug,firstboot-info`，`ROOTFS_HOSTNAME_DEFAULT=muse`
- 串口：`ttyFIQ0,1500000n8`；root 仍按 `PARTLABEL=rootfs`（SD/eMMC 通用布局）

```bash
make fetch-muse
make build-all \
  BOARD=rk3588-muse \
  SDK_VOLUME=rk3588-sdk-muse-5.10 \
  ROOTFS=debian \
  DEBIAN_RELEASE=13
```

强制 minbase（覆盖板级默认 features）：

```bash
make build-rootfs DEBIAN_FEATURES=none
```

## 共同约定

现有 profile 都用同一启动布局：

| 项 | 值 |
|---|---|
| 布局 | `rockchip-gpt-idblock-extlinux-v1` |
| idblock | sector 64（`RKNS`） |
| uboot | sector 16384 |
| FAT BOOT | 16 MiB 起，默认 256 MiB |
| rootfs | `PARTLABEL=rootfs` |
| console | 多为 `ttyFIQ0,1500000n8` |

字段细节见仓库 [configs/README.md](https://github.com/lsy1291455142/rk3588-build/blob/main/configs/README.md)。新增硬件见 [新增板型](./add-board)。
