# 构建流水线

## 顺序

```text
build / pull builder
        │
        ▼
   SDK volume 就绪
        │
        ├─► build-kernel  ──► Image, DTB, modules.tar
        │
        ├─► build-uboot   ──► idblock.img, uboot.img, download-loader.bin
        │
        └─► build-rootfs  ──► rootfs.ext4   （依赖 modules.tar）
                 │
                 ▼
              image  ──► GPT .img + .img.zst + SHA256
                 │
                 ▼
           verify-image（自动）
                 │
                 ▼
        可选 test-debian-qemu
```

`make build-all` 就是按这个顺序串起来。

## Kernel（`scripts/build_kernel.sh`）

1. 读 board profile  
2. 在 SDK kernel 上用 O= 外部构建目录（symlink source view，不污染 / 不 `mrproper` 导入树）  
3. 应用 `KERNEL_DEFCONFIG`，再 merge `configs/kernel/rootfs-base.config`  
4. 只产出 profile 指定的那一个 `KERNEL_DTB`  
5. **删掉 DTB 里的 `/chosen/bootargs`**  
6. 打包 `modules.tar`，写 build-info

删 bootargs 的原因：Rockchip U-Boot 会把 DTB bootargs 和 extlinux APPEND 合并，厂商写死的 `root=PARTUUID=...` 会盖掉我们的 `root=PARTLABEL=rootfs`。

## U-Boot（`scripts/build_uboot.sh`）

1. 调 BSP 的 `./make.sh`（`UBOOT_BOARD`）  
2. 按 `UBOOT_PYTHON` 在当前构建进程里切 python2/3  
3. 从产物里挑 `idblock.img`（必须 `RKNS`）和 `uboot.img`  
4. 另存 USB 用的 `download-loader.bin`（`LDR `）  
5. 检查体积是否越过 sector 预留  
6. 检查能力：MMC / FAT / extlinux / `booti` / `distro_bootcmd`  
7. 若开了与未签名 extlinux 冲突的 FIT/AVB 公钥校验，直接失败  

ARM64 宿主机上，部分 rkbin x86 工具会走 qemu-user。

## rootfs

| 类型 | 脚本 | 特征 |
|---|---|---|
| Buildroot | `build_buildroot.sh` | glibc + BusyBox init + Dropbear；external 在 `rootfs/buildroot/` |
| Debian | `build_debian.sh` | `mmdebstrap` + OpenSSH；默认 networkd，可选 `DEBIAN_FEATURES`（nm/nmtui 等）；11/12/13 |

两者都要先有 kernel 的 `modules.tar`，都会装匹配的 `/lib/modules`，都带串口/SSH/扩容相关配置。

Debian 在 **privileged `linux/arm64` 容器**里做。x86_64 主机依赖 binfmt。

## 打包（`scripts/make_image.sh`）

不用 loop 挂载。用 `sgdisk` + `mtools` + `dd` 直接写 raw：

1. 建 GPT：FAT `BOOT` + ext4 `rootfs`  
2. 做 FAT：放入 `Image`、DTB、`extlinux/extlinux.conf`  
3. 在固定 sector 写入 idblock / uboot  
4. 写入 FAT 与 rootfs 镜像  
5. 压 `.zst`、写 SHA256 与 metadata  

extlinux APPEND 形如：

```text
root=PARTLABEL=rootfs rootwait rw console=${CONSOLE} ${EXTRA_KERNEL_ARGS}
```

## 校验（`scripts/verify_image.sh`）

`image` 末尾自动跑。会查：

- GPT 与分区名  
- sector 上的 RKNS idblock  
- FAT 内容与 extlinux 契约  
- DTB 无 `/chosen/bootargs`  
- rootfs 标签、模块目录、默认用户、扩容钩子  
- raw 与 zst 的哈希  

通过 ≠ 板子一定能起。见 [磁盘与启动契约](./boot-contract.md)。
