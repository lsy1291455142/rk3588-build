# Debian 功能集

构建 Debian rootfs 时，除了最小系统（minbase），还可以通过 `DEBIAN_FEATURES` 预装一组功能集。每个功能集对应若干软件包或系统配置，用逗号分隔的 token 指定。


## 配置文件怎么放（overlay）

额外配置**不要**再写进 `scripts/build_debian.sh` 的 heredoc。静态文件放在：

| 路径 | 何时应用 |
|---|---|
| `rootfs/debian/overlay/` | 始终应用（minbase 也有） |
| `rootfs/debian/overlay-networkd/` | 未启用 `nm` 时（systemd-networkd） |
| `rootfs/debian/features/<token>/overlay/` | 启用对应 `DEBIAN_FEATURES` 时 |
| `rootfs/debian/boards/<board>/overlay/` | 匹配当前 `BOARD` 时 |

应用顺序：通用 overlay → 网络栈 overlay → 各 feature → 板级 overlay（后者覆盖前者）。

- 文件以 `.in` 结尾时按模板处理，`@BOARD@`、`@ROOTFS_HOSTNAME@`、`@CONSOLE_SPEED@` 等在安装时展开，落盘时去掉 `.in`。
- 包名仍在 `scripts/lib/common.sh` 的 `debian_feature_packages()` 里声明；固件仍走 `install_wifibt_firmware`。
- 详见 [`rootfs/debian/README.md`](../../rootfs/debian/README.md)。

## 可用功能

| Token | 安装的包 | 效果 |
|---|---|---|
| `nm` | network-manager, wpasupplicant, nmtui | 用 NetworkManager 替代 systemd-networkd 作为主网络栈（保留 systemd-resolved 做 DNS）；含 wpa_supplicant，使 WiFi 可扫描/连接 |
| `hwdebug` | i2c-tools, usbutils, pciutils, mmc-utils | 硬件调试工具，排查板级外设 |
| `tools` | tmux, htop, strace | 常用诊断/排障工具 |
| `firstboot-info` | （不装额外包） | 首次启动串口打印板型摘要；登录后 MOTD 与 profile 也显示板型信息 |
| `wifibt` | （固件 blob，不是 deb 包） | 安装 WiFi/BT 固件到 `/lib/firmware`，并建立 Rockchip 兼容路径（`/vendor` → `/system`，`/system/etc/firmware` → `/lib/firmware`） |
| `all` | 以上全部 | 等价于 `nm,hwdebug,tools,firstboot-info,wifibt` |

## 默认值规则

`DEBIAN_FEATURES` 的取值按以下优先级生效：

1. **命令行显式指定**（最高优先级）：
   - `DEBIAN_FEATURES=nm,hwdebug` → 仅这两个
   - `DEBIAN_FEATURES=all` → 全部
   - `DEBIAN_FEATURES=none`（或 `minbase` / `off` / `-`）→ 强制 minbase，忽略板级默认
2. **板级 profile 的 `DEBIAN_FEATURES_DEFAULT`**：命令行未指定时生效。例如 MUSE 板默认 `nm,hwdebug,firstboot-info`。
3. **minbase**：以上都没有时，只装最基础系统。

## 使用示例

指定功能集构建：

```bash
make build-rootfs \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  ROOTFS=debian \
  DEBIAN_FEATURES=nm,hwdebug,firstboot-info
```

一键全功能 + 自定义主机名：

```bash
make build-rootfs \
  BOARD=rk3588-muse \
  SDK_VOLUME=rk3588-sdk-muse-5.10 \
  ROOTFS=debian \
  DEBIAN_FEATURES=all \
  ROOTFS_HOSTNAME=muse
```

强制最小系统（覆盖板级默认）：

```bash
make build-rootfs \
  BOARD=rk3588-muse \
  SDK_VOLUME=rk3588-sdk-muse-5.10 \
  ROOTFS=debian \
  DEBIAN_FEATURES=none
```

直接用板级默认（MUSE 会自动带上 `nm,hwdebug,firstboot-info`）：

```bash
make build-rootfs BOARD=rk3588-muse ROOTFS=debian
```

## WiFi/BT 固件（`wifibt`）

`nm` 只负责用户态网络栈（NetworkManager + wpa_supplicant）。**模组固件不在 Debian 包里**，需要单独装进 rootfs，否则 nmtui 往往只能看到有线口。

本 builder 刻意做成通用：最小 SDK（只有 kernel/u-boot/rkbin/buildroot）也能出可启动镜像；WiFi/BT 固件是可选能力。

### 变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `WIFIBT_CHIP` | `none`（板级可改） | 模组名，如 `AIC8800D80`、`AP6275S`、`RTL8822CS`；或 `ALL_AP` / `ALL_CY` / `ALL` |
| `WIFIBT_SOURCE` | `sdk-or-assets` | 查找顺序：`sdk` → `SDK/external/rkwifibt/firmware`；`assets` → 项目 `assets/wifibt`；`sdk-or-assets` 先 SDK 后 assets |
| `WIFIBT_REQUIRED` | `no` | `yes` 时找不到固件则构建失败；`no` 只警告并跳过 |

板级 profile 可用 `: "${WIFIBT_CHIP:=none}"` 给默认值，命令行始终可覆盖。

### 固件从哪来

1. **完整 BSP**：volume 里若有 `external/rkwifibt/firmware`，构建时直接用。
2. **项目 assets**（推荐给最小 SDK）：

```bash
make sync-wifibt-assets \
  SDK_PATH=/path/to/full-bsp \
  WIFIBT_CHIP=AP6275S
# 或同步全部 Broadcom AP6xxx：
make sync-wifibt-assets SDK_PATH=/path/to/full-bsp WIFIBT_CHIP=ALL_AP
```

`assets/wifibt/` 的目录布局与 BSP `external/rkwifibt/firmware/` 一致。二进制默认 gitignore，只保留目录说明。

### 构建示例

```bash
# 已知模组 + 要求必须装上固件
make build-rootfs \
  BOARD=rk3588s-cokepi-model-lp4-v10 \
  ROOTFS=debian \
  DEBIAN_FEATURES=nm,hwdebug,firstboot-info,wifibt \
  WIFIBT_CHIP=AP6275S \
  WIFIBT_REQUIRED=yes

# 只想先出镜像，模组型号未定：板级可开 wifibt 但 WIFIBT_CHIP=none（软跳过）
make build-rootfs BOARD=rk3588s-cokepi-model-lp4-v10 ROOTFS=debian
```

### 上板后怎么确认

- `rootfs-build-info.txt` 中的 `wifibt_chip` / `wifibt_source` / `wifibt_files`
- rootfs 内：`/lib/firmware/fw_*.bin`、`nvram_*.txt`、`/vendor` 软链
- 运行时：`lsmod` 看 `bcmdhd`/`aic8800` 等；`nmtui` / `nmcli device` 看无线口；`dmesg | grep -iE 'wlan|firmware|bcmdhd'`

模组型号不确定时，先看原理图丝印，再在完整 BSP 的 `external/rkwifibt` 或设备树 `compatible`/`wifi` 节点对照；最终以板上 SDIO/PCIe VID:PID 与模组文档为准。

## 在产物里查看

构建完成后，`rootfs-build-info.txt` 会记录实际启用的功能：

```
rootfs=debian
debian_release=13
debian_features=nm,hwdebug,firstboot-info
network_stack=NetworkManager
hostname=muse
wifibt_chip=none
wifibt_source=skipped
wifibt_files=0
```

`network_stack` 字段标明实际生效的网络栈（`NetworkManager` 或 `systemd-networkd`），方便确认 `nm` 是否真的生效。

## 实现机制

包类 token 在 `scripts/lib/common.sh` 的 `debian_feature_packages()` 映射到 deb 包名；`wifibt` 走 `install_wifibt_firmware()` 拷贝固件并建兼容路径。`scripts/build_debian.sh` 用 mmdebstrap 安装包，再按需配置 NetworkManager、串口 getty、首次启动扩容服务等。完整流程见[构建流水线](/how-it-works/pipeline)。
