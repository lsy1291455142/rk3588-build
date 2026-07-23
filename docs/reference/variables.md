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
| `DEBIAN_PACKAGES_DEFAULT` | （板级配置） | 板级配置文件 (`boards/<BOARD>/board.conf`) 中预设的标准基础软件包列表 |
| `DEBIAN_OVERLAYS` | （空） | 可选 overlay 插件列表；空=使用板级默认；`none`=关闭所有；`all`=启用全部 |
| `DEBIAN_OVERLAYS_DEFAULT` | （板级配置） | 板级配置文件中默认启用的 Overlay 插件列表 |
| `DEBIAN_MIRROR` | `http://deb.debian.org/debian` | Debian 主镜像源 |
| `DEBIAN_SECURITY_MIRROR` | `http://security.debian.org/debian-security` | 安全更新源 |
| `DEBIAN_ALLOW_ARCHIVE_FALLBACK` | `yes` | Debian 11 过期时回退到 archive.debian.org |

## 根文件系统布局变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `ROOTFS_MODE` | `rw-ext4` | 根文件系统布局：`rw-ext4`=单可写 ext4 根（默认）；`ro-overlay`=只读 SquashFS 根 + ext4 数据/overlay 分区（防掉电损坏、可恢复出厂） |
| `DATA_SIZE_MIB` | `0` | `ro-overlay` 模式下 ext4 数据分区大小（MiB）；`0`=占满根分区之后的剩余磁盘空间 |

优先级：**命令行/CLI（`make ROOTFS_MODE=...`）> 板级默认值 > 内置默认**。板级 profile
可在 `boards/<BOARD>/board.conf` 中用 `ROOTFS_MODE_DEFAULT`（内置默认 `rw-ext4`）与
`DATA_SIZE_MIB_DEFAULT`（内置默认 `0`）预配置默认值；二者均可被命令行覆盖。直接写
`ROOTFS_MODE=` / `DATA_SIZE_MIB=` 也能硬编码，但会强制覆盖命令行，一般不推荐。

示例：本仓库的 `rk3588s-cokepi-model-lp4-v10` 板型已设置
`ROOTFS_MODE_DEFAULT="ro-overlay"`，因此对该板执行 `make build-all BOARD=... ROOTFS=debian`
即默认产出只读 overlay 镜像，无需再传 `ROOTFS_MODE=ro-overlay`。

`ro-overlay` 模式的额外依赖（均由构建自动处理，无需手动安装）：

- **内核支持**：`scripts/build_kernel.sh` 在板级 defconfig 之后**始终合并**
  `configs/kernel/rootfs-base.config` 与 `configs/kernel/squashfs-overlay.config`
  （含 `CONFIG_SQUASHFS=y`、`CONFIG_OVERLAY_FS=y` 等），所以同一个内核产物可同时启动
  `rw-ext4` 与 `ro-overlay` 两种镜像，无需为 overlay 单独编内核。
- **initramfs 的 mount**：`ro-overlay` 会在 rootfs 阶段自动加入 `initramfs-tools` 与
  `busybox` 包。initramfs-tools 在缺少 busybox 时会回退到 klibc 的 `mount`，而 klibc
  mount **不支持 overlay 文件系统**（`mount -t overlay` 会打印 usage 并失败）。busybox 的
  mount 支持 overlay，且 `overlayroot` 钩子会优先调用 `/bin/busybox mount`。

详见 [`boards/TEMPLATE/board.conf`](../../boards/TEMPLATE/board.conf)。

### 包控制变量说明

- **`DEBIAN_PACKAGES_DEFAULT`** (板级定义)：固化在该板型 `.conf` 中的标准基础包。
- **`DEBIAN_PACKAGES`** (命令行/环境变量)：**覆盖模式**。如果传入此变量，板级 `DEBIAN_PACKAGES_DEFAULT` 会被直接替换；设为 `none` 则强制仅 minbase。

**示例：**
```bash
# 1. 默认构建：使用板级 DEBIAN_PACKAGES_DEFAULT (包含 network-manager 等)
make build-rootfs BOARD=rk3588-muse

# 2. 覆盖模式：忽略板级默认，只安装 htop 和 curl
make build-rootfs BOARD=rk3588-muse DEBIAN_PACKAGES=htop,curl

# 3. 在板级默认基础上追加：直接编辑 board.conf 的 DEBIAN_PACKAGES_DEFAULT，
#    或在命令行给出完整列表（默认项 + 新增项）
make build-rootfs BOARD=rk3588-muse DEBIAN_PACKAGES="network-manager,wpasupplicant,htop,python3-pip"
```


WiFi/BT 固件走板级 `boards/<BOARD>/plugin.sh`，不在通用变量里控制。
CokePi：`make build-rootfs` 从 `packages/*.deb` 装入 rootfs；host 可选手动：

```bash
make build-rootfs
./boards/rk3588s-cokepi-model-lp4-v10/rootfs/stage-aic8800-firmware.sh   # optional
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
