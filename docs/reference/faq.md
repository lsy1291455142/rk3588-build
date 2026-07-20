# FAQ

## 为什么要显式传 `BOARD` / `SDK_VOLUME` / `ROOTFS`？

避免误用错误板型或错误 SDK 污染产物。三者无默认值；缺一相关目标会直接失败。

## 为什么 DTB 要删掉 `/chosen/bootargs`？

Rockchip U-Boot 可能把 DTB 中的 `bootargs` 与 extlinux 合并，导致厂商固定的 `root=PARTUUID=...` 覆盖本项目的 `root=PARTLABEL=rootfs`。构建阶段会主动删除该属性。

## `idblock.img` 和 `download-loader.bin` 有什么区别？

| 文件 | 魔数 | 用途 |
|---|---|---|
| `idblock.img` | `RKNS` | 写入磁盘 sector 64 |
| `download-loader.bin` | `LDR ` | USB 下载，**不能**原样写入 sector 64 |

## QEMU 通过了就能上板吗？

不能。QEMU virt 只验证 Debian 用户空间与镜像基本结构，无法模拟 RK3588 DDR / PMIC / MMC 与真实 loader 路径。硬件以串口日志为准。

## CokePi Plus / Model 能混用吗？

不能。两者可用同一 SDK volume，但 DTB 不同，必须按丝印选择对应 board profile。

## 本地改了 `configs/` 要重建镜像吗？

一般不需要。工作区中的 `configs/`、`scripts/` 会 bind mount 进容器，覆盖镜像内副本。改工具链本身才需要 `make build`。
