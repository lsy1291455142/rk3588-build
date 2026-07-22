# Debian 软件包与可选 Overlay

构建 Debian rootfs 时，在 minbase 之上通过 `DEBIAN_PACKAGES` 安装**真实 APT 包名**。
项目专属行为（NetworkManager 配置、firstboot 摘要、WiFi/BT 固件、串口 getty 等）以
`rootfs/debian/overlays/` 可选插件形式存在，不再使用 `nm` / `hwdebug` 这类 feature token，
也不再写死进构建核心。

## 配置文件怎么放

| 路径 | 何时应用 |
|---|---|
| `rootfs/debian/boards/<board>/plugin.sh` | 匹配当前 `BOARD` 时（始终） |
| `rootfs/debian/boards/<board>/overlay/` | 板级插件应用，或无 plugin 时静态拷贝 |
| `rootfs/debian/overlays/<name>/plugin.sh` | `DEBIAN_OVERLAYS` 选中时 |
| 插件自带 `overlay` / `overlay-*` | 由对应插件按需应用 |

- 文件以 `.in` 结尾时按模板处理，`@BOARD@`、`@ROOTFS_HOSTNAME@`、`@DEBIAN_PACKAGES@`、`@DEBIAN_OVERLAYS@` 等在安装时展开。
- 详见 [`rootfs/debian/README.md`](../../rootfs/debian/README.md)。

## 软件包列表

`DEBIAN_PACKAGES`（或板级 `DEBIAN_PACKAGES_DEFAULT`）写什么就装什么，逗号/空格分隔。

| 示例 | 效果 |
|---|---|
| `network-manager,wpasupplicant` | 只安装这些 apt 包 |
| `i2c-tools,usbutils,pciutils,mmc-utils` | 硬件调试工具 |
| `tmux,htop,strace` | 常用诊断工具 |
| `none` / `minbase` / `off` | 强制 minbase，忽略板级默认 |
| （空） | 使用板级默认；板级也空则只有 minbase |

优先级：命令行 `DEBIAN_PACKAGES` > 板级 `DEBIAN_PACKAGES_DEFAULT` > minbase。
`DEBIAN_EXTRA_PACKAGES` 会追加到最终列表。

```bash
make build-rootfs DEBIAN_PACKAGES=network-manager,wpasupplicant,i2c-tools
make build-rootfs DEBIAN_PACKAGES=none
make build-rootfs DEBIAN_EXTRA_PACKAGES=htop,python3-pip
```

构建元数据 `rootfs-build-info.txt` 记录 `debian_packages`、`debian_overlays` 和 `network_stack`。

## 可选 Overlay 插件

`DEBIAN_OVERLAYS`（或板级 `DEBIAN_OVERLAYS_DEFAULT`）选择附件插件。

| 值 | 含义 |
|---|---|
| （空） | 板级默认；板级也空则无插件 |
| `none` / `off` / `-` | 强制无可选 overlay |
| `all` | 启用 `overlays/*` 全部插件 |
| `base,console,firstboot,network` | 显式列表（按顺序） |

| Overlay | 行为 |
|---|---|
| `base` | SSH 密码/root 登录、hostkey ExecStartPre、udev GPU 权限；启用 ssh / resolved |
| `console` | 串口 getty 波特率 drop-in + 启用 `serial-getty@CONSOLE_DEVICE` |
| `firstboot` | 首次启动扩容 rootfs |
| `firstboot-info` | 首次启动串口摘要 + MOTD |
| `network` | 有 `/usr/sbin/NetworkManager` → 写 NM conf 并启用；否则启用 systemd-networkd + 有线 DHCP |

```bash
make build-rootfs DEBIAN_OVERLAYS=base,console,firstboot,network
make build-rootfs DEBIAN_OVERLAYS=none
make build-rootfs DEBIAN_OVERLAYS=all
```

插件只做镜像布局需要的 enable（串口 getty、firstboot、NM 与 networkd 互斥等）。
常规 deb 包 postinst / systemd preset 仍按 Debian 自身逻辑处理。

## 板级 plugin（与 overlays 同规范）

板型专属逻辑放在 `rootfs/debian/boards/<BOARD>/`，接口与可选 overlay 一致：

- 有 `plugin.sh` → 构建时 `source` 并调用 `board_plugin_apply(root_dir)`
- 仅有 `overlay/` → 静态拷贝
- 规范说明：[`rootfs/debian/boards/README.md`](../../rootfs/debian/boards/README.md)

## WiFi/BT 固件（板级 plugin 示例）

WiFi/BT 不是通用插件，也不进 `DEBIAN_PACKAGES`。CokePi Model 的板级
`plugin.sh` 在 `make build-rootfs` 时自动 stage Radxa `aic8800-firmware`
（默认 3.0，`info_len=4`），并拷贝 `overlay/`（含 `/vendor` 兼容链）。

```bash
make build-rootfs   # 自动 stage + 应用板级 overlay

# 可选：手动刷新 / 指定 deb
./rootfs/debian/boards/rk3588s-cokepi-model-lp4-v10/stage-aic8800-firmware.sh
```

详见 [boards/rk3588s-cokepi-model-lp4-v10/README.md](../../rootfs/debian/boards/rk3588s-cokepi-model-lp4-v10/README.md)。

