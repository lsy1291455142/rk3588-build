# 校验边界

## 离线校验能证明什么

| 能证明 | 不能证明 |
|---|---|
| 镜像 GPT / 分区 / bootloader 偏移正确 | DDR / PMIC 初始化在真机成功 |
| FAT 内容与 extlinux 契约 | 真实 MMC / eMMC 时序与稳定性 |
| rootfs 完整性与默认账户 | 外设、显示、NPU 等板级功能 |
| QEMU virt 上 Debian 基本可引导 | 真实 U-Boot 加载路径 |

硬件验收以开发板串口日志为准。

## `verify-image` 检查项

- GPT 主备表与分区起止
- boot / rootfs 类型与名称
- 固定偏移处的 RKNS IDBlock 与 U-Boot
- FAT 中的 Image、DTB、extlinux
- 产物 DTB 与 FAT 内 DTB 均无 `/chosen/bootargs`
- rootfs 标签、模块目录、开发账户、root 登录、扩容钩子
- raw image 与 `.img.zst` 的 SHA256

## QEMU 冒烟

```bash
make test-debian-qemu \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  DEBIAN_RELEASE=13
```

在 ARM64 `virt` 上验证串口登录、systemd、扩容、网络与 SSH。  
**不能**模拟 RK3588 DDR / PMIC / MMC 与真实 loader/U-Boot 路径。

## 许可证提示

分发镜像时需同时处理 Kernel、U-Boot、Buildroot/Debian 软件包及 rkbin 固件各自的许可证义务。容器构建不免除 Kernel / U-Boot 的 GPL 源码提供义务。
