# Debian 软件包与可选 Overlay

构建 Debian rootfs 时，在 minbase 之上通过 `DEBIAN_PACKAGES` 安装**真实 APT 包名**。
项目专属行为（NetworkManager 配置、firstboot 摘要、WiFi/BT 固件、串口 getty 等）以
`rootfs/debian/overlays/` 可选插件形式存在，不再使用 `nm` / `hwdebug` 这类 feature token，
也不再写死进构建核心。

## 配置文件怎么放

| 路径 | 何时应用 |
|---|---|
| `rootfs/debian/boards/<board>/overlay/` | 匹配当前 `BOARD` 时（始终） |
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
| `wifibt` | 可选插件：装固件 deb/blobs 并做路径适配（见 overlays/wifibt） |

```bash
make build-rootfs DEBIAN_OVERLAYS=base,console,firstboot,network
make build-rootfs DEBIAN_OVERLAYS=none
make build-rootfs DEBIAN_OVERLAYS=all
```

插件只做镜像布局需要的 enable（串口 getty、firstboot、NM 与 networkd 互斥等）。
常规 deb 包 postinst / systemd preset 仍按 Debian 自身逻辑处理。

## WiFi/BT 固件（`wifibt` overlay）

与 `htop`/`network-manager` 同类：**装固件包 + 路径适配**。逻辑只在
`rootfs/debian/overlays/wifibt/`，构建核心不参与。仅 `DEBIAN_OVERLAYS` 含 `wifibt` 时生效。

| 变量 | 默认 | 说明 |
|---|---|---|
| `WIFIBT_CHIP` | `none` | `none` 跳过；或 `AIC8800D80` / `AP6275S` 等 |
| `WIFIBT_DEB` | （空） | 固件 `.deb` 路径或 URL；也可放 `overlays/wifibt/packages/` |
| `WIFIBT_SOURCE` | `auto` | `auto`：package → firmware/ → SDK；或强制 `package`/`firmware`/`sdk` |
| `WIFIBT_REQUIRED` | `no` | `yes` 时固件缺失失败 |

```bash
# CokePi / AIC：拉 Radxa aic8800-firmware deb（推荐）
./rootfs/debian/overlays/wifibt/sync-assets.sh --deb-aic

make build-rootfs \
  DEBIAN_PACKAGES=network-manager,wpasupplicant \
  DEBIAN_OVERLAYS=base,console,firstboot,network,wifibt \
  WIFIBT_CHIP=AIC8800D80

# 其它模组：有 deb 就 --deb；否则静态文件
./rootfs/debian/overlays/wifibt/sync-assets.sh --deb /path/to/vendor-firmware.deb
# 或
./rootfs/debian/overlays/wifibt/sync-assets.sh --from-bsp /path/to/full-bsp AP6275S
```

插件会做驱动路径 remap（如 AIC → `/lib/firmware/aic8800D80/` + `/vendor` 链）。
详见 [overlays/wifibt/README.md](../../rootfs/debian/overlays/wifibt/README.md)。
