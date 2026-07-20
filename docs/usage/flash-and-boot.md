# 烧录与启动

## 找镜像

```text
output/<BOARD>/<variant>/<BOARD>-<variant>.img.zst
```

例：

```text
output/rk3588s-rock-5c/debian-13/rk3588s-rock-5c-debian-13.img.zst
```

## dd 到 SD / eMMC

先确认设备节点。写错盘会毁掉宿主机数据。

```bash
zstd -d -f output/rk3588s-rock-5c/debian-13/rk3588s-rock-5c-debian-13.img.zst
sudo dd if=output/rk3588s-rock-5c/debian-13/rk3588s-rock-5c-debian-13.img \
  of=/dev/sdX bs=4M status=progress conv=fsync
```

板载 eMMC 视启动模式可能是 `/dev/mmcblk0` 或 USB 烧录工具路径。本流程产出的是 **GPT raw**，不是 `rkdeveloptool wl` 用的分卷 `update.img`。

## USB 下载 loader

| 文件 | 魔数 | 用途 |
|---|---|---|
| `idblock.img` | `RKNS` | 写在磁盘 sector 64 |
| `download-loader.bin` | `LDR ` | 给 `rkdeveloptool db` 一类 USB 下载 |

两者不能互换。把 `download-loader.bin` 写到 sector 64 会起不来。

## 串口

默认 console（板级 profile 的 `CONSOLE`）：

```text
ttyFIQ0,1500000n8
```

多数 Rockchip 板：1500000 8N1。接好地线，先开串口再上电。

## 默认账号

```text
用户: rk3588
密码: rk3588
root 密码: rk3588
```

由 `ROOTFS_USERNAME` / `ROOTFS_PASSWORD` 控制。默认密码只适合隔离实验网。

## 启动后 root 挂载方式

内核参数来自 FAT 分区里的 `extlinux/extlinux.conf`：

```text
root=PARTLABEL=rootfs rootwait rw console=...
```

不写死 `mmcblk` 设备名。SD 和 eMMC 只要分区 label 对，就能挂上 rootfs。

Debian 首次启动会尝试修复备份 GPT、扩展 root 分区与文件系统。Buildroot 也带扩容钩子，行为以 rootfs 脚本为准。

## 起不来先查什么

1. 串口有没有 loader / U-Boot 输出  
2. U-Boot 是否找到 FAT 与 extlinux  
3. 内核是否卡在 `VFS: Unable to mount root fs`  
4. DTB 是否匹配硬件（错板 profile 最常见）

离线校验通过只说明镜像结构对；DRAM 初始化、PMIC、存储时序仍依赖厂商 loader 与正确 DTB。
