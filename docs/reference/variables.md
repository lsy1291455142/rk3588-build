# 变量与 .env

三个核心变量**没有默认值**，缺了相关目标会直接失败。其余可写在 `.env` 或命令行覆盖。

模板见仓库根目录 [`.env.example`](https://github.com/lsy1291455142/rk3588-build/blob/main/.env.example)。

## 必需

| 变量 | 含义 | 典型设置 |
|---|---|---|
| `SDK_VOLUME` | 存放 BSP 的 Docker volume 名 | `make use-volume-*` / `fetch-*` / CLI |
| `BOARD` | `configs/boards/<name>.conf`（无后缀） | `make use-board-*` / CLI |
| `ROOTFS` | `buildroot` / `debian` / `all` | `make use-rootfs-*` / CLI |

```bash
make use-volume-rock5c
make use-board-rock5c
make use-rootfs-debian
make use-current
```

Compose 把 `SDK_VOLUME` 当 external volume。volume 不存在时，依赖它的服务起不来。

## Debian / rootfs

| 变量 | 默认 | 说明 |
|---|---|---|
| `DEBIAN_RELEASE` | `13` | `11` / `12` / `13` |
| `DEBIAN_FEATURES` | 空 | 见下表；空时用板级 `DEBIAN_FEATURES_DEFAULT`（若有） |
| `ROOTFS_HOSTNAME` | 空 → 板级默认或 `rk3588` | Debian hostname |
| `ROOTFS_USERNAME` | `rk3588` | 开发用户 |
| `ROOTFS_PASSWORD` | `rk3588` | 用户与 root 密码（仅实验环境） |
| `DEBIAN_MIRROR` | `http://deb.debian.org/debian` | 主源 |
| `DEBIAN_SECURITY_MIRROR` | `http://security.debian.org/debian-security` | security 源 |
| `DEBIAN_ALLOW_ARCHIVE_FALLBACK` | `yes` | Debian 11 归档回退 |

### `DEBIAN_FEATURES` token

逗号分隔。`all` 展开为全部 token。

| Token | 内容 |
|---|---|
| `nm` | NetworkManager + `nmtui`（不再启用 networkd） |
| `hwdebug` | `i2c-tools` `usbutils` `pciutils` `mmc-utils` |
| `tools` | `tmux` `htop` `strace` |
| `firstboot-info` | 首次启动串口摘要 + MOTD（无额外 deb） |
| `all` | 以上全部 |

强制 minbase（覆盖板级默认）：

```bash
make build-rootfs DEBIAN_FEATURES=none
# 也接受 minbase / off / -
```

板级可在 `.conf` 里写：

```bash
DEBIAN_FEATURES_DEFAULT="nm,hwdebug,firstboot-info"
ROOTFS_HOSTNAME_DEFAULT="muse"
```

## SDK 拉取

| 变量 | 说明 |
|---|---|
| `SDK_PATH` | `import-local-sdk` 的绝对路径 |
| `MANIFEST` | `fetch-custom` 用的本地 manifest 名 |
| `CUSTOM_MANIFEST_URL` / `CUSTOM_MANIFEST_NAME` | 远程 manifest |
| `BRANCH` | 部分 fetch 路径使用 |
| `DEPTH` | 浅克隆深度，默认 `1` |
| `MAX_RETRIES` | fetch 重试次数 |
| `EXTRA_COMPONENTS` | 是否拉额外组件，默认 `no` |
| `FETCH_ON_START` | 默认 `no` |

## 构建控制

| 变量 | 默认 | 说明 |
|---|---|---|
| `JOBS` | `0` | 并行度；`0` 表示脚本自定 |
| `CCACHE_MAXSIZE` | `10G` | ccache 上限 |
| `ZSTD_LEVEL` | `6` | 最终 `.img.zst` 压缩级别 |
| `USE_NATIVE_BUILD` | `no` | 是否倾向原生编译（视脚本路径） |

## 板级 profile 字段（不是 .env）

写在 `configs/boards/*.conf`，由 `BOARD` 选中后 source。主要字段：

| 字段 | 作用 |
|---|---|
| `KERNEL_DEFCONFIG` / `KERNEL_DTB` | 内核配置与唯一 DTB |
| `UBOOT_DEFCONFIG` / `UBOOT_BOARD` / `UBOOT_PYTHON` | U-Boot 构建 |
| `BOOTLOADER_LAYOUT` | 当前为 `rockchip-gpt-idblock-extlinux-v1` |
| `IDBLOCK_SECTOR` / `UBOOT_SECTOR` | 默认 64 / 16384 |
| `CONSOLE` / `EXTRA_KERNEL_ARGS` | extlinux APPEND |
| `IMAGE_SIZE_MIB` / `BOOT_*` / `ROOTFS_SIZE_MIB` | 镜像几何 |
| `EXPECTED_*_REVISION` | 可选源码锁定 |
| `DEBIAN_FEATURES_DEFAULT` / `ROOTFS_HOSTNAME_DEFAULT` | Debian 默认 |

完整说明见 [configs/README.md](https://github.com/lsy1291455142/rk3588-build/blob/main/configs/README.md)。
