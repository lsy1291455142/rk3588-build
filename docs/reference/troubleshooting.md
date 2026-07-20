# 排错

先分清是**构建失败**还是**镜像起不来**。离线 `verify-image` 只覆盖前者与镜像结构。

## 构建前：缺变量 / 缺 volume

症状：目标立刻失败，提示 `BOARD` / `SDK_VOLUME` / `ROOTFS` 未设置。

```bash
make use-current
# 或
make build-all BOARD=... SDK_VOLUME=... ROOTFS=...
```

症状：Compose 报 external volume 不存在。

```bash
docker volume ls --filter name=rk3588
make fetch-rock5c   # 或 import-local-sdk / 对应 fetch
```

## builder / binfmt

| 现象 | 处理 |
|---|---|
| 找不到 `rk3588-build:latest` | `make build`，或 GHCR pull 后 `docker tag ... rk3588-build:latest` |
| Debian rootfs 要求 arm64 | `make build-debian-builder`；x86_64 需 binfmt（`register-arm64-binfmt`） |
| 特权容器被拒 | Debian 路径需要 privileged；只在可信主机跑 |

## SDK

| 现象 | 处理 |
|---|---|
| 缺 `kernel/` `u-boot/` `rkbin/` `buildroot/` | 解压路径不对，或 import 的根目录层级多了一层 |
| `import-local-sdk` 后路径失效 | volume 是 bind；宿主机目录被移动/删除后要重新 import |
| ROCK 5C revision 不匹配 | profile 锁定了 commit；应用 `fetch-rock5c` 的 volume，或改 profile 锁定 |
| CokePi 校验失败 | `make verify-cokepi-sdk SDK_VOLUME=...` 看缺什么 |

## kernel / U-Boot

| 现象 | 处理 |
|---|---|
| 找不到 DTB | `KERNEL_DTB` 与 SDK 实际文件名不一致 |
| U-Boot `make.sh` / python 报错 | 检查 `UBOOT_PYTHON`（CokePi 常为 python2，EVB/MUSE/ROCK5C 多为 python3） |
| idblock 魔数不是 `RKNS` | 挑错了产物文件；看 `DOWNLOAD_LOADER_GLOBS` / 构建日志 |
| loader 体积越界 | 不要把 FAT 起点压到 U-Boot 区域；保持默认 16 MiB 预留 |

## rootfs / image

| 现象 | 处理 |
|---|---|
| `modules.tar` 缺失 | 先 `make build-kernel` |
| mmdebstrap / 源失败 | 查网络与 `DEBIAN_MIRROR`；Debian 11 可开 archive fallback |
| `verify-image` 报 DTB bootargs | 打包应删 `/chosen/bootargs`；确认用的是本仓库脚本产物 |
| `verify-image` 报 PARTLABEL | 不要手改成 `root=UUID=...` 却未同步校验预期 |
| zst 损坏 | 重新 `make image`；传输时保留 `.sha256` |

## 真机起不来

按串口阶段判断：

1. **完全无输出**：供电、串口线序/电平、波特率（多为 1500000 8N1）、是否烧到正确介质  
2. **无 IDBlock / 无 U-Boot**：写错盘、写了 zst 未解压、把 `download-loader.bin`（`LDR `）当成 idblock 写进 sector 64  
3. **U-Boot 起、进不了内核**：FAT 缺 `Image`/`extlinux`，或 DTB 名不对  
4. **内核 panic / 挂不上 root**：错 DTB、root 参数被覆盖、分区 label 不是 `rootfs`  
5. **能挂 root 但无登录**：账号密码被改、getty 不在该 console

```text
用户/密码默认: rk3588 / rk3588
root 密码: rk3588
```

## QEMU 通过、真机不过

`test-debian-qemu` 用的是 **ARM64 virt**，不是板级 U-Boot/DRAM/PMIC 路径。它只能证明 Debian rootfs 与通用内核用户态大致可用，**不能**替代串口验收。

## 清理过头

`make clean-all` 会删 volume 与镜像。

- `fetch-*` 进 volume 的源码会丢，需重新 fetch  
- `import-local-sdk` 的 bind **不删**宿主机源码，但 volume 引用没了，需重新 import  

## 还要看哪里

- 终端最后一段错误（脚本 `die` 信息）  
- `output/<BOARD>/common/*-build-info.txt` 与 rootfs 侧 metadata  
- [磁盘与启动契约](/how-it-works/boot-contract)  
- [构建流水线](/how-it-works/pipeline)  
- `make check`（静态契约，不替代真实构建）
