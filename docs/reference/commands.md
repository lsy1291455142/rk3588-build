# 常用命令

## 帮助与状态

```bash
make help
make check
make status
make shell          # 进入构建容器
make clean          # 停止容器
make clean-all      # 停止并删除 volume / 镜像
```

## 选择当前上下文

```bash
make use-volume-rock5c
make use-board-rock5c
make use-rootfs-debian
make use-current

make use-board-evb1
make use-board-cokepi-plus
make use-board-cokepi-model
make use-board-muse
make use-rootfs-buildroot
make use-rootfs-all
```

## 构建

```bash
make build
make build-debian-builder
make fetch-rock5c
make build-kernel
make build-uboot
make build-rootfs
make image
make verify-image
make build-all
make test-debian-qemu
make test-debian-all
```

## 示例：ROCK 5C

```bash
make build
make fetch-rock5c
make build-all \
  BOARD=rk3588s-rock-5c \
  SDK_VOLUME=rk3588-sdk-rock5c \
  ROOTFS=debian \
  DEBIAN_RELEASE=13
```
