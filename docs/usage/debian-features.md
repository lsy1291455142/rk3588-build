# Debian 功能集

构建 Debian rootfs 时，除了最小系统（minbase），还可以通过 `DEBIAN_FEATURES` 预装一组功能集。每个功能集对应若干软件包或系统配置，用逗号分隔的 token 指定。

## 可用功能

| Token | 安装的包 | 效果 |
|---|---|---|
| `nm` | network-manager, wpasupplicant, nmtui | 用 NetworkManager 替代 systemd-networkd 作为主网络栈（保留 systemd-resolved 做 DNS）；含 wpa_supplicant，使 WiFi 可扫描/连接 |
| `hwdebug` | i2c-tools, usbutils, pciutils, mmc-utils | 硬件调试工具，排查板级外设 |
| `tools` | tmux, htop, strace | 常用诊断/排障工具 |
| `firstboot-info` | （不装额外包） | 首次启动串口打印板型摘要；登录后 MOTD 与 profile 也显示板型信息 |
| `all` | 以上全部 | 等价于 `nm,hwdebug,tools,firstboot-info` |

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

## 在产物里查看

构建完成后，`rootfs-build-info.txt` 会记录实际启用的功能：

```
rootfs=debian
debian_release=13
debian_features=nm,hwdebug,firstboot-info
network_stack=NetworkManager
hostname=muse
```

`network_stack` 字段标明实际生效的网络栈（`NetworkManager` 或 `systemd-networkd`），方便确认 `nm` 是否真的生效。

## 实现机制

每个 token 在 `scripts/lib/common.sh` 里映射到具体包名，`scripts/build_debian.sh` 用 mmdebstrap 的 `--include` 安装，并按需配置 NetworkManager、串口 getty、首次启动扩容服务等。完整的构建流程见[构建流水线](/how-it-works/pipeline)。
