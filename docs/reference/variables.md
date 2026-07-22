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
| `DEBIAN_PACKAGES` | （空） | 指定 APT 包名列表（逗号/空格）；**会整体覆盖**板级 `DEBIAN_PACKAGES_DEFAULT`；`none`=仅 minbase |
| `DEBIAN_PACKAGES_DEFAULT` | （板级配置） | 板级配置文件 (`configs/boards/*.conf`) 中预设的标准基础软件包列表 |
| `DEBIAN_EXTRA_PACKAGES` | （空） | **追加**额外 APT 包（在现有包列表末尾追加，**不覆盖**已有包，适合临时调试） |
| `DEBIAN_OVERLAYS` | （空） | 可选 overlay 插件列表；空=使用板级默认；`none`=关闭所有；`all`=启用全部 |
| `DEBIAN_OVERLAYS_DEFAULT` | （板级配置） | 板级配置文件中默认启用的 Overlay 插件列表 |
| `DEBIAN_MIRROR` | `http://deb.debian.org/debian` | Debian 主镜像源 |
| `DEBIAN_SECURITY_MIRROR` | `http://security.debian.org/debian-security` | 安全更新源 |
| `DEBIAN_ALLOW_ARCHIVE_FALLBACK` | `yes` | Debian 11 过期时回退到 archive.debian.org |

### 包控制变量对比说明

- **`DEBIAN_PACKAGES_DEFAULT`** (板级定义)：固化在该板型 `.conf` 中的标准基础包。
- **`DEBIAN_PACKAGES`** (命令行/环境变量)：**覆盖模式**。如果传入此变量，板级 `DEBIAN_PACKAGES_DEFAULT` 会被直接替换。
- **`DEBIAN_EXTRA_PACKAGES`** (命令行/环境变量)：**追加模式**。在最终决定的包列表末尾追加新包，不改变已有包。

**示例：**
```bash
# 1. 默认构建：使用板级 DEBIAN_PACKAGES_DEFAULT (包含 network-manager 等)
make build-rootfs BOARD=rk3588-muse

# 2. 覆盖模式：忽略板级默认，只安装 htop 和 curl
make build-rootfs BOARD=rk3588-muse DEBIAN_PACKAGES=htop,curl

# 3. 追加模式：保留板级默认包，另外临时多装 htop 和 python3-pip
make build-rootfs BOARD=rk3588-muse DEBIAN_EXTRA_PACKAGES=htop,python3-pip
```


WiFi/BT 固件走板级 `boards/<BOARD>/plugin.sh`，不在通用变量里控制。
CokePi：`make build-rootfs` 从 `packages/*.deb` 装入 rootfs；host 可选手动：

```bash
make build-rootfs
./rootfs/debian/boards/rk3588s-cokepi-model-lp4-v10/stage-aic8800-firmware.sh   # optional
```


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
DEBIAN_OVERLAYS=base,console,firstboot,firstboot-info,network
ROOTFS_USERNAME=admin
ROOTFS_PASSWORD=mysecret
JOBS=8
```

`.env` 文件在 Makefile 顶部通过 `-include .env` 加载，所有变量同时传入 docker compose 环境。
