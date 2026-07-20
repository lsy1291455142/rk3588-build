# 磁盘与启动契约

这是整套流程能跨 SD / eMMC 工作的约定。改打包逻辑或板级布局时，不要破坏它们。

## 布局

默认几何（board conf 可改，但现有板都按这个）：

```text
0 ──────── 16 MiB ──────── 272 MiB ──────── image end
│ GPT+预留 │   FAT BOOT    │   ext4 rootfs  │
│          │ 256 MiB       │ PARTLABEL=rootfs│
│ idblock @64              │                │
│ uboot   @16384           │                │
```

| 偏移 | 内容 |
|---|---|
| sector 64 | `idblock.img`，魔数 `RKNS` |
| sector 16384 | `uboot.img` |
| `BOOT_START_MIB`（默认 16） | FAT32，label `BOOT` |
| FAT 之后 | ext4，label / PARTLABEL `rootfs` |

loader / U-Boot 必须落在 FAT 起始之前。脚本会检查 idblock、uboot 体积是否越界。

## 启动链

```text
SoC ROM
  -> sector 64 RKNS IDBlock（DRAM 初始化 + 加载 U-Boot）
  -> sector 16384 uboot.img
  -> 读 FAT /extlinux/extlinux.conf
  -> booti Image + DTB
  -> 内核按 PARTLABEL=rootfs 挂根
```

## 谁说了算：启动参数

**以 extlinux 为准。**

因此：

1. 打包进镜像的 DTB 不得带 `/chosen/bootargs`  
2. `verify-image` 会检查 common 产物 DTB 和 FAT 里那份  
3. root 使用 `PARTLABEL=rootfs`，不绑 `mmcblk0p2` 这类名字  

## 两个 loader 文件

| 文件 | 魔数 | 放哪 |
|---|---|---|
| `idblock.img` | `RKNS` | 磁盘 sector 64 |
| `download-loader.bin` | `LDR ` | 仅 USB 下载，不进 GPT 固定布局 |

## FAT 最小集合

```text
/Image
/<KERNEL_DTB 文件名>
/extlinux/extlinux.conf
```

没有 initramfs 依赖。模块在 rootfs 的 `/lib/modules/<release>`。

## 校验边界

| 能证明 | 不能证明 |
|---|---|
| 分区表、偏移、魔数正确 | DDR / PMIC 在真机初始化成功 |
| extlinux 契约与 DTB 无冲突 bootargs | eMMC 时序 / 供电稳定 |
| rootfs 含用户、模块、扩容钩子 | 显示 / NPU / 网卡板级功能 |
| QEMU virt 上 Debian 可登录 | 真实 U-Boot 加载路径 |

硬件结论以串口日志为准。
