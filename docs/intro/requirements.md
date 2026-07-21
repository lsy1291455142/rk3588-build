# 环境要求

## 宿主机

| 项目 | 要求 |
|---|---|
| 操作系统 | Linux、macOS、Windows（需 WSL2） |
| Docker | 20.10+，支持 `docker compose`（v2 插件） |
| Make | GNU Make 3.82+ |
| 磁盘 | 至少 50 GB 可用空间 |
| 内存 | 建议 8 GB+（内核编译峰值约 4 GB） |

不需要在宿主机安装交叉编译器、QEMU、Python、repo 工具或任何 Rockchip 专有工具。这些全部在 Docker 镜像里。

## 架构支持

| 宿主机架构 | 状态 | 说明 |
|---|---|---|
| x86_64 (amd64) | 完整支持 | 首次构建 Debian rootfs 时自动注册 ARM64 binfmt |
| ARM64 (aarch64) | 完整支持 | 原生运行，Debian rootfs 构建更快 |

x86_64 上构建 Debian rootfs 依赖 QEMU 用户态模拟（`qemu-user-static`），速度比 ARM64 原生慢约 2-3 倍，但功能完全一致。Buildroot rootfs 不受影响（纯交叉编译）。

## Docker 资源建议

默认 Docker Desktop 分配可能不够，建议：

- **内存**: 8 GB+
- **磁盘**: Docker 数据目录预留 60 GB+
- **CPU**: 不限，编译自动用满

## 网络

- 首次 `make build` 需要拉取 Ubuntu 22.04 和 Debian Trixie 基础镜像（约 500 MB）
- `make fetch-*` 需要从 GitHub / GitLab 拉取源码（约 3-5 GB，取决于 manifest）
- 内核编译过程完全离线，不需要网络

## 验证环境

```bash
docker --version          # 需要 20.10+
docker compose version    # 需要 v2
make --version            # 需要 GNU Make
df -h .                   # 确认当前分区有 50 GB+
```

## 项目自检

环境装好后先跑一次自检，确认所有脚本和配置本身没有问题：

```bash
make check
```

这会校验 Bash 语法、ShellCheck 规则、manifest XML 格式、板级 profile 完整性、Makefile 目标契约等。全部通过说明项目文件本身是健康的。
