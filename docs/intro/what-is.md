# 这是什么

`rk3588-build` 是一套 **Docker 化的 RK3588 系统镜像构建流程**。

它不替代厂商 BSP。它做的是：

1. 把工具链固定在 builder 镜像里
2. 用 Docker volume 挂上你的 SDK 源码
3. 按板级 profile 编 kernel / U-Boot / rootfs
4. 拼成一张可 `dd` 的 GPT raw 镜像，并做离线校验

## 你会得到什么

构建成功后，大致会有：

| 产物 | 作用 |
|---|---|
| `Image` + 板级 DTB + `modules.tar` | 内核与模块 |
| `idblock.img` / `uboot.img` / `download-loader.bin` | 启动链与 USB 下载用 loader |
| `rootfs.ext4` | Buildroot 或 Debian 根文件系统 |
| `<board>-<variant>.img` / `.img.zst` | 整盘 GPT 镜像 |

镜像布局固定为：

```text
sector 64     idblock (RKNS)
sector 16384  uboot.img
16 MiB 起     FAT BOOT（Image / DTB / extlinux）
其后          ext4 rootfs（PARTLABEL=rootfs）
```

## 它不是什么

| 不是 | 说明 |
|---|---|
| 桌面发行版 | 无 GUI，默认真机串口 / SSH 调试用 |
| 厂商 SDK 仓库 | SDK 要 `fetch-*` 或本地导入 |
| Rockchip `update.img` 流程 | 输出是 GPT raw，不是 `update.img` |
| 硬件 bring-up 保证 | 离线校验只保证镜像结构；能否起板看串口 |

## 和 README 的关系

- **README**：仓库入口，命令速查
- **本站**：按使用路径说明“先做什么、为什么、失败看哪里”

细节以脚本与 `configs/boards/*.conf` 为准。文档写错时，以代码行为为准。
