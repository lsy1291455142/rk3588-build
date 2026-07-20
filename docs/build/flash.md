# 烧录与登录

## 默认登录

```text
用户: rk3588
密码: rk3588
root 密码: rk3588
```

`ROOTFS_USERNAME` / `ROOTFS_PASSWORD` 可改。默认密码仅适合隔离实验环境。

## 烧录

务必核对目标设备名，写错会覆盖宿主机磁盘：

```bash
zstd -d output/<board>/<variant>/<board>-<variant>.img.zst
sudo dd if=output/<board>/<variant>/<board>-<variant>.img \
  of=/dev/sdX bs=4M status=progress conv=fsync
```

镜像为 GPT raw，可用 `dd` 写入 eMMC 或 SD；rootfs 通过 `PARTLABEL=rootfs` 挂载，不写死 `mmcblk` 设备名。

## USB 下载 loader

`download-loader.bin`（魔数 `LDR `）用于 USB 下载模式（如 `rkdeveloptool db`）。  
它与写入 sector 64 的 `idblock.img`（`RKNS`）不是同一文件，**不能**原样写入 sector 64。

## 串口

板级验收建议使用 1500000 8N1。具体 `console=` 以 board profile 中的 `CONSOLE` 为准。
