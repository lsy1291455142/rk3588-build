# 变量与 .env

所有变量可以通过三种方式设置，优先级从高到低：

1. 命令行：`make build-all BOARD=my-board`
2. `.env` 文件：`BOARD=my-board`
3. Makefile 默认值

`make use-board` / `use-volume` / `use-rootfs` 系列目标会自动写入 `.env`。

## 核心变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `BOARD` | （必填） | 板级 profile 名（`.conf` 文件名去掉后缀） |
| `SDK_VOLUME` | （必填） | Docker volume 名，指向 SDK 源码 |
| `ROOTFS` | （构建 rootfs 时必填） | `buildroot`、`debian` 或 `all` |

## rootfs 变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `ROOTFS_USERNAME` | `user` | 非 root 用户名 |
| `ROOTFS_PASSWORD` | `password` | 用户和 root 密码 |
| `ROOTFS_HOSTNAME` | `(板型名)` | 主机名 |

## Debian 变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `DEBIAN_RELEASE` | `13` | Debian 版本：11、12 或 13 |
| `DEBIAN_PACKAGES` | （空） | 额外 APT 包名（逗号/空格）；空=板级默认/minbase；`none`=强制 minbase |
| `DEBIAN_EXTRA_PACKAGES` | （空） | 预装额外的 APT 软件包（如 `htop i2c-tools python3-pip docker.io`） |
| `WIFIBT_CHIP` | `none`（板级可改） | WiFi/BT 模组：`AIC8800D80` / `AP6275S` / `ALL_AP` / `ALL` 等；`none` 表示软跳过 |
| `WIFIBT_SOURCE` | `sdk-or-assets` | 固件来源：`sdk`、`assets` 或 `sdk-or-assets`（先 SDK 后 assets） |
| `WIFIBT_REQUIRED` | `no` | `yes` 时找不到固件则失败；`no` 只警告 |
| `DEBIAN_MIRROR` | `http://deb.debian.org/debian` | Debian 主镜像源 |
| `DEBIAN_SECURITY_MIRROR` | `http://security.debian.org/debian-security` | 安全更新源 |
| `DEBIAN_ALLOW_ARCHIVE_FALLBACK` | `yes` | Debian 11 过期时回退到 archive.debian.org |

`DEBIAN_PACKAGES` 为空时：如果板级 profile 设了 `DEBIAN_PACKAGES_DEFAULT` 则用板级默认，否则 minbase。设为 `none` / `minbase` / `off` / `-` 强制 minbase。写真实包名，例如 `network-manager,wpasupplicant,i2c-tools`。

WiFi/BT 固件由 `WIFIBT_CHIP` 控制（插件），不是软件包 token。最小 SDK 没有 `external/rkwifibt` 时，先：

```bash
make sync-wifibt-assets SDK_PATH=/path/to/full-bsp WIFIBT_CHIP=AP6275S
```

再 `make build-rootfs ... DEBIAN_PACKAGES=network-manager,wpasupplicant WIFIBT_CHIP=AP6275S`。

## 构建变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `JOBS` | `0`（= CPU 核数） | 编译并行数 |
| `ZSTD_LEVEL` | `6` | 镜像压缩级别（1-19） |
| `DEPTH` | `1` | repo 浅克隆深度，`0` = 完整克隆 |
| `CCACHE_MAXSIZE` | `10G` | ccache 缓存上限 |
| `USE_NATIVE_BUILD` | `no` | ARM64 宿主机上用原生 GCC 替代交叉编译 |

## SDK 拉取变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `MANIFEST` | （空） | 本地 manifest 文件名 |
| `CUSTOM_MANIFEST_URL` | （空） | 远程 manifest 仓库 URL |
| `CUSTOM_MANIFEST_NAME` | （空） | 远程 manifest 文件名 |
| `SDK_PATH` | （空） | 本地 SDK 路径（import-local-sdk 用） |
| `FETCH_ON_START` | `no` | 容器启动时自动拉取 SDK |
| `EXTRA_COMPONENTS` | `no` | 拉取额外组件 |
| `MAX_RETRIES` | `3` | repo sync 重试次数 |
| `MIN_DISK_GB` | `10` | 最小磁盘空间检查 |

## QEMU 测试变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `QEMU_TIMEOUT` | `600` | 启动超时（秒） |
| `QEMU_MEMORY_MIB` | `1024` | 虚拟机内存 |
| `QEMU_CPUS` | `2` | 虚拟机 CPU 数 |

## .env 文件示例

```bash
# 当前选择（由 make use-* 自动写入）
BOARD=rk3588s-rock-5c
SDK_VOLUME=rk3588-sdk-rock5c
ROOTFS=debian

# 可选覆盖
DEBIAN_RELEASE=13
DEBIAN_PACKAGES=network-manager,wpasupplicant,i2c-tools
WIFIBT_CHIP=AP6275S
WIFIBT_SOURCE=sdk-or-assets
WIFIBT_REQUIRED=no
ROOTFS_USERNAME=admin
ROOTFS_PASSWORD=mysecret
JOBS=8
```

`.env` 文件在 Makefile 顶部通过 `-include .env` 加载，所有变量同时传入 docker compose 环境。
