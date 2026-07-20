# 环境与参数

## 项目定位

本仓库管理的是**构建流程与板级配置**，不是厂商 BSP 本体：

- 工具链：`rk3588-build` Docker 镜像
- 源码：独立 Docker volume（`SDK_VOLUME`）
- 板级：`configs/boards/<board>.conf`
- 产物：`output/<board>/...`

## 三个核心参数

| 变量 | 含义 | 无默认值时的行为 |
|---|---|---|
| `SDK_VOLUME` | BSP 源码 volume | 相关目标直接失败 |
| `BOARD` | 板级 profile 名（去掉 `.conf`） | 相关目标直接失败 |
| `ROOTFS` | `buildroot` / `debian` / `all` | `build-rootfs` / `image` / `build-all` 直接失败 |

写入 `.env` 后可被后续 `make` 继承：

```bash
make use-volume-rock5c
make use-board-rock5c
make use-rootfs-debian
make use-current
```

等价的一次性传参：

```bash
make build-all \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  ROOTFS=debian \
  DEBIAN_RELEASE=13
```

## 常用可选变量

见仓库 [`.env.example`](https://github.com/lsy1291455142/rk3588-build/blob/main/.env.example)。常见项：

| 变量 | 说明 |
|---|---|
| `DEBIAN_RELEASE` | 默认 `13`（trixie） |
| `ROOTFS_USERNAME` / `ROOTFS_PASSWORD` | 默认用户与密码 |
| `JOBS` | 并行编译任务数 |
| `ZSTD_LEVEL` | 镜像压缩级别 |

## 宿主机架构差异

| 宿主机 | Kernel / U-Boot | Buildroot | Debian rootfs |
|---|---|---|---|
| x86_64 | 交叉编译 | 交叉编译 | ARM64 容器 + QEMU binfmt |
| ARM64 | 交叉或原生 | 交叉编译 | 原生 ARM64 |

x86_64 会安装 i386 依赖以运行部分 rkbin 工具；ARM64 会安装 `qemu-user-static` 以运行其中的 x86 预编译工具。

## 工作区挂载

使用本仓库 `docker compose` / Makefile 时，工作区中的 `scripts/`、`configs/` 等会 bind mount 覆盖镜像内副本。因此改板级配置或脚本后，无需重建 builder 镜像即可生效。
