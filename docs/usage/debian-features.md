# Debian 软件包与插件

构建 Debian rootfs 时，在 minbase 之上通过 `DEBIAN_PACKAGES` 安装**真实 APT 包名**。
项目专属行为（NetworkManager 配置、firstboot 摘要、WiFi/BT 固件）以
`rootfs/debian/plugins/` 插件形式存在，不再使用 `nm` / `hwdebug` 这类 feature token。

## 配置文件怎么放

| 路径 | 何时应用 |
|---|---|
| `rootfs/debian/overlay/` | 始终应用（minbase 也有） |
| `rootfs/debian/boards/<board>/overlay/` | 匹配当前 `BOARD` 时 |
| `rootfs/debian/plugins/*.sh` | 装完包后按文件名顺序执行 |
| 插件自带 `overlay*` | 由对应插件按需应用 |

- 文件以 `.in` 结尾时按模板处理，`@BOARD@`、`@ROOTFS_HOSTNAME@`、`@DEBIAN_PACKAGES@` 等在安装时展开。
- 详见 [`rootfs/debian/README.md`](../../rootfs/debian/README.md)。

## 软件包列表

`DEBIAN_PACKAGES`（或板级 `DEBIAN_PACKAGES_DEFAULT`）写什么就装什么，逗号/空格分隔。

| 示例 | 效果 |
|---|---|
| `network-manager,wpasupplicant` | 安装 NM 与 wpa_supplicant；网络插件检测到 NM 后启用它 |
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

构建元数据 `rootfs-build-info.txt` 记录 `debian_packages` / `debian_features`（同值）和 `network_stack`。

## 插件

| 插件 | 行为 |
|---|---|
| `00-systemd-base` | 启用 ssh、sbc-firstboot、串口 getty、resolved |
| `10-firstboot-info` | 首次启动串口摘要 + MOTD（`DEBIAN_FIRSTBOOT_INFO=no` 可关） |
| `network` | 有 `/usr/sbin/NetworkManager` → 写 NM conf 并启用；否则启用 systemd-networkd + 有线 DHCP |
| `20-wifibt` | 按 `WIFIBT_CHIP` 安装固件（与软件包列表无关） |

deb 包 postinst / systemd preset 会处理常规服务启用；项目只保留镜像布局需要的 enable（串口 getty、firstboot、NM 与 networkd 互斥）。

## WiFi/BT 固件

固件**不是** apt 包，由 `WIFIBT_CHIP` / `WIFIBT_SOURCE` / `WIFIBT_REQUIRED` 控制：

| 变量 | 默认 | 说明 |
|---|---|---|
| `WIFIBT_CHIP` | `none` | `none` 跳过；或 `AP6275S` / `AIC8800D80` / `ALL_AP` 等 |
| `WIFIBT_SOURCE` | `sdk-or-assets` | 查找顺序：SDK `external/rkwifibt/firmware` → 项目 `assets/wifibt` |
| `WIFIBT_REQUIRED` | `no` | `yes` 时固件缺失失败 |

```bash
make sync-wifibt-assets SDK_PATH=/path/to/full-bsp WIFIBT_CHIP=AP6275S
make build-rootfs \
  DEBIAN_PACKAGES=network-manager,wpasupplicant \
  WIFIBT_CHIP=AP6275S
```

完整流程见[构建流水线](/how-it-works/pipeline)。
