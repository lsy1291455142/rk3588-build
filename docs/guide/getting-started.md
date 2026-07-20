# 快速开始

先构建或拉取 builder 镜像，再准备 SDK，再指定 `BOARD` / `ROOTFS` 执行完整构建。

## 环境要求

- Docker Engine / Desktop
- Docker Compose v2
- GNU Make

Windows 建议在 Git Bash 或 WSL 中执行 `make`。宿主机无需预先安装交叉编译器或 QEMU。

| 宿主机 | Kernel / U-Boot | Buildroot | Debian rootfs |
|---|---|---|---|
| x86_64 | 交叉编译 | 交叉编译 | ARM64 容器 + QEMU binfmt |
| ARM64 | 交叉或原生 | 交叉编译 | 原生 ARM64 |

`make` 会按宿主机架构自动处理 binfmt 与兼容库。

## 三个核心参数

所有组件构建与镜像打包都依赖下面三个变量，**均无默认值**：

| 变量 | 含义 | 设置方式 |
|---|---|---|
| `SDK_VOLUME` | 存放 BSP 源码的 Docker volume | `make fetch-*` / `import-local-sdk` / `use-volume-*` |
| `BOARD` | `configs/boards/<name>.conf` 板级配置 | `make use-board-*` |
| `ROOTFS` | `buildroot` \| `debian` \| `all` | `make use-rootfs-*` |

可写入 `.env` 供后续命令继承，也可在单次命令中覆盖。

## 路径 A：ROCK 5C + Debian 13（推荐入门）

公开源，适合第一次跑通：

```bash
make build
make fetch-rock5c
make build-all \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  ROOTFS=debian \
  DEBIAN_RELEASE=13
make test-debian-qemu \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  DEBIAN_RELEASE=13
```

`test-debian-qemu` 在 ARM64 virt 上做冒烟测试（串口登录、systemd、扩容、网络/SSH），**不能**替代真实硬件验收。

## 路径 B：CokePi（本地 SDK）

SDK 需已解压，根目录直接包含 `kernel/`、`u-boot/`、`rkbin/`、`buildroot/`。导入为 bind-backed volume，**不复制**源码。

```bash
make build
make import-local-sdk \
  SDK_PATH=/absolute/path/to/rk3588_linux-5.10-cokepi-rkr9 \
  SDK_VOLUME=rk3588-sdk-cokepi-rkr9
make verify-cokepi-sdk SDK_VOLUME=rk3588-sdk-cokepi-rkr9

# Model 示例；Plus 改为 use-board-cokepi-plus / 对应 BOARD
make use-board-cokepi-model
make use-rootfs-debian
make build-all \
  BOARD=rk3588s-cokepi-model-lp4-v10 \
  SDK_VOLUME=rk3588-sdk-cokepi-rkr9 \
  ROOTFS=debian \
  DEBIAN_RELEASE=13
```

## 路径 C：EVB1 + Buildroot

```bash
make build
make fetch-510
make build-all \
  BOARD=rk3588-evb1-lp4-v10-linux \
  SDK_VOLUME=rk3588-sdk-rockchip-5.10 \
  ROOTFS=buildroot
```

## 路径 D：MUSE RK3588 + Debian 13

```bash
make build
make fetch-muse
make use-board-muse
make use-rootfs-debian
make build-all \
  BOARD=rk3588-muse \
  SDK_VOLUME=rk3588-sdk-muse-5.10 \
  ROOTFS=debian \
  DEBIAN_RELEASE=13
```

## GitHub Codespaces

本项目支持在 GitHub Codespaces 中直接打开，预配置 Docker-in-Docker 与编译工具链。仓库 README 中有 Codespaces 徽章。

## 下一步

- 理解参数与产物结构：[环境与参数](./concepts.md)
- 查看阶段细节：[流水线总览](/build/pipeline)
- 板型字段：[已支持板型](/boards/profiles)
