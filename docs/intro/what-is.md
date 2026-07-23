# 这是什么

`rk3588-build` 是一个基于 Docker 容器化的 SBC（单板计算机）Linux 系统镜像构建工具，专门为 RK3588 / RK3588S 开发板生成可直接烧录启动的 GPT 磁盘镜像。宿主机只需 Docker 与 GNU Make，无需安装交叉工具链、QEMU 或任何 Rockchip 专有工具。

## 解决什么问题

在没有此类工具时，为 RK3588 板子做镜像需要手动搭建交叉编译环境、理解 Rockchip 的 U-Boot `make.sh` 与 IDBlock 打包、拼装 extlinux 启动、处理 Debian/ Buildroot rootfs，并自行保证 SDK 版本可复现。本工具把这些步骤收敛进一套配置驱动的流水线：板型差异只体现在 `boards/<BOARD>/board.conf` 与少量 overlay 中，核心脚本保持板型无关。

## 产出什么

一条命令（`make build-all`）即可产出裸 GPT 镜像（`.img`）、zstd 压缩镜像（`.img.zst`）、SHA-256 校验和（`.sha256`）与完整构建元数据（`image-build-info.txt`）。镜像内含 Rockchip 启动链（RKNS IDBlock + U-Boot）、FAT32 boot 分区（内核/DTB/extlinux）、以及 ext4 或 SquashFS+OverlayFS 的根文件系统。可选择在 QEMU `virt` 中做串口登录 + SSH + systemd 健康检查。

## 不是什么

- 不含任何 Rockchip 厂商源码。`kernel`/`u-boot`/`rkbin`/`buildroot` 全部通过 `repo` manifest 从上游拉取，或导入本地已下载的 SDK；许可证遵循各自上游。
- 不是发行版。`patches/` 仅作可选本地补丁存放，构建系统不会自动套用。
- 不替你写板级驱动。新板型需要正确的 defconfig、DTB 与（必要时）固件，本工具只负责把它们组合成可启动镜像。

## 设计理念

- **配置驱动的多板型支持**：新增板子只需新增 `board.conf`，不改脚本。
- **版本可复现**：每个 SDK 用 `repo` manifest 锁定四个组件的 Git commit，板级 profile 可强制校验（Rockchip EVB1/MUSE 设 `SOURCE_MANIFEST`，ROCK 5C 还锁 `EXPECTED_*_REVISION`）。
- **纯构建核心 + 插件化**：核心脚本只处理通用逻辑；板级差异通过 overlay（`rootfs/debian/overlays/`、`boards/<BOARD>/rootfs/`）与 hooks（`board.hooks.sh`）注入。
- **双 rootfs 同一套组装/校验**：Buildroot 最小化系统或 Debian 11/12/13，共用 `make_image.sh` 与 `verify_image.sh`。
- **端到端校验**：`verify_image.sh` 从分区几何到 rootfs 内容逐项比对，确保产出的镜像与源码、配置一致。
- **可测**：QEMU `virt` 冒烟测试无需真实硬件即可验证 Debian 镜像可启动、可登录、服务健康。
