# 环境要求

## 宿主机

必须有：

- Docker Engine 或 Docker Desktop
- Docker Compose v2
- GNU Make

不需要在宿主机装交叉编译器、QEMU 用户态或厂商工具链；这些都在容器里。

Windows 建议在 **WSL2** 或 Git Bash 里跑 `make`。路径相关操作（尤其 `import-local-sdk`）优先用 Linux 路径。

## 架构差异

| 宿主机 | Kernel / U-Boot | Buildroot | Debian rootfs |
|---|---|---|---|
| x86_64 | 交叉编译 | 交叉编译 | `linux/arm64` 容器 + binfmt |
| ARM64 | 交叉或原生 | 交叉编译 | 同架构原生跑 |

选 `ROOTFS=debian` 时，会用到特权 ARM64 容器跑 `mmdebstrap`。只在可信机器、可信代码上做。

## 磁盘与时间

经验量级（因 SDK 与并行度而异）：

| 项 | 量级 |
|---|---|
| 单个 SDK volume | 数 GB 到十几 GB |
| 完整 `build-all` | 常见 30 分钟到数小时 |
| 输出镜像 | 默认 4 GiB raw，另有 `.zst` |

SSD 明显更快。`JOBS` 可写在 `.env` 里控制并行度。

## 权限与网络

- Docker 能访问你给的 SDK 绝对路径（本地导入时）
- 公开 `fetch-*` 需要能拉 GitHub / 对应镜像源
- Debian 构建会访问 `deb.debian.org`（可用 `DEBIAN_MIRROR` 改）

## Codespaces

仓库支持 GitHub Codespaces（Docker-in-Docker）。适合临时试跑；长期构建更建议本地或自有机器。
