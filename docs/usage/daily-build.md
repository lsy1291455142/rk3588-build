# 日常构建

第一次跑通后，日常只需要改上下文、重编需要的部分。

## 看当前上下文

```bash
make use-current
```

显示当前 `.env` 里的 `SDK_VOLUME` / `BOARD` / `ROOTFS`。

## 切换

```bash
# SDK volume
make use-volume-rock5c
make use-volume-muse
make use-volume            # 交互选择

# 板型
make use-board-rock5c
make use-board-evb1
make use-board-cokepi-model
make use-board-muse

# rootfs
make use-rootfs-debian
make use-rootfs-buildroot
make use-rootfs-all
```

这些目标只改 `.env` 对应字段，不会自动开编。

## 分阶段目标

| 命令 | 何时用 |
|---|---|
| `make build-kernel` | 改了 defconfig / fragment / 内核补丁 |
| `make build-uboot` | 改了 U-Boot defconfig / board / loader 规则 |
| `make build-rootfs` | 改 rootfs 用户、包、Debian 版本 |
| `make image` | common + 对应 rootfs 已齐，只重打包 |
| `make verify-image` | 单独再跑离线校验 |
| `make build-all` | 从 kernel 到 image 全做 |

`build-rootfs` / `image` / `build-all` 都要求 `ROOTFS` 已设置。`ROOTFS=all` 会同时打 Buildroot 与 Debian。

## Debian 多版本

```bash
make test-debian-all BOARD=... SDK_VOLUME=...
```

复用同一套 bootloader/kernel，依次打 Debian 11/12/13。单独指定版本：

```bash
make build-all ROOTFS=debian DEBIAN_RELEASE=12
```

## Debian 可选预装功能

`DEBIAN_FEATURES` 控制预装包与首次启动信息。未指定时用板级 `DEBIAN_FEATURES_DEFAULT`（muse 默认 `nm,hwdebug,firstboot-info`）；无默认则 minbase。显式 `none` 强制 minbase。

| Token | 作用 |
|---|---|
| `nm` | NetworkManager + **nmtui** |
| `hwdebug` | I2C/USB/PCI/MMC 调试工具 |
| `tools` | tmux/htop/strace |
| `firstboot-info` | 首次启动串口/MOTD 板级摘要 |
| `all` | 全部 |

```bash
# muse 默认功能集 + hostname muse（可不写 DEBIAN_FEATURES）
make build-rootfs BOARD=rk3588-muse ROOTFS=debian
# 显式指定
make build-rootfs DEBIAN_FEATURES=nm,hwdebug,firstboot-info ROOTFS_HOSTNAME=muse
# 强制 minbase
make build-rootfs DEBIAN_FEATURES=none
make image
```

说明：

- **首次启动信息**不是扩容本身。扩容仍由 `rk3588-firstboot` 做（growpart + resize2fs）。
- 打开 `firstboot-info` 后，首次启动还会写 `/var/lib/rk3588-board-info`，串口打出 board/dtb/kernel/网络提示；登录 MOTD 也会显示，直到用户 home 下出现 `.rk3588-board-info.seen`。
- 打开 `nm` 后 **不再启用** systemd-networkd，避免双栈抢网卡；有线/无线用 `nmtui` 或 `nmcli`。

## 进入容器

```bash
make shell           # 主 builder
make debian-shell    # ARM64 Debian builder（需已构建）
```

容器内 SDK 在 `/home/builder/sdk`，输出在 `/home/builder/output`。  
工作区里的 `scripts/`、`configs/`、`rootfs/`、`manifests/` 是只读挂载，改完宿主机文件立刻生效，一般**不用**重建 builder 镜像。

## 清理

```bash
make clean       # 停容器
make clean-all   # 停容器并删 volume / 镜像（危险：会丢 SDK volume 引用）
```

`import-local-sdk` 的 volume 是 bind，删 volume **不会**删宿主机源码；但 `fetch-*` 拉进 volume 的源码会随 volume 一起没。

## 并行与缓存

| 变量 | 作用 |
|---|---|
| `JOBS` | make 并行度；`0` 表示脚本自行决定 |
| `CCACHE_MAXSIZE` | ccache 上限，默认 `10G` |
| `ZSTD_LEVEL` | 最终 `.img.zst` 压缩级别 |

写在 `.env` 或命令行均可。
