# 产物与布局

## 构建目标

```bash
make build-kernel    # Image、DTB、modules.tar
make build-uboot     # idblock.img、uboot.img、download-loader.bin
make build-rootfs    # Buildroot 和/或 Debian rootfs
make image           # 打包 GPT 镜像，并自动 verify-image
make verify-image    # 单独离线校验
make build-all       # kernel + uboot + rootfs + image
make test-debian-qemu
make test-debian-all # 复用一次 bootloader/kernel，依次打 Debian 11/12/13
```

## 产物目录

```text
output/<board>/
├── common/
│   ├── Image
│   ├── <board-or-dtb-name>.dtb
│   ├── modules.tar
│   ├── idblock.img          # RKNS，写入 sector 64
│   ├── uboot.img
│   ├── download-loader.bin  # LDR，供 rkdeveloptool db
│   └── *-build-info.txt
├── buildroot/
│   ├── rootfs.ext4
│   ├── <board>-buildroot.img[.zst]
│   └── ...
└── debian-13/
    ├── rootfs.ext4
    ├── <board>-debian-13.img[.zst]
    └── ...
```

打包进 FAT 的 DTB 会去掉 `/chosen/bootargs`，保证启动参数以 extlinux 为准（`root=PARTLABEL=rootfs`），避免厂商 DTB 中固定 `root=PARTUUID=...` 覆盖。

## 镜像布局

```text
sector 0                    Protective MBR / GPT
sector 64                   idblock.img (RKNS)
sector 16384                uboot.img
16 MiB .. 272 MiB           FAT32 BOOT：Image、DTB、extlinux
272 MiB .. image end        ext4 rootfs（PARTLABEL=rootfs）
```

rootfs 文件系统初始约 2 GiB，分区占满镜像剩余空间。Debian 首次启动会修复备份 GPT、扩展分区与 ext4。

## 启动契约（摘要）

1. 磁盘启动链：sector 64 的 **RKNS** IDBlock → sector 16384 的 `uboot.img` → FAT 中 extlinux
2. 启动参数以 **extlinux** 为准；打包 DTB 不得保留 `/chosen/bootargs`
3. rootfs 通过 `PARTLABEL=rootfs` 定位
4. USB 下载用 `download-loader.bin`（LDR），与盘上 IDBlock 不是同一文件
