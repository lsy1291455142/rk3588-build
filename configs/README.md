# Configuration

The image pipeline is driven by board profiles in `configs/boards/`.

## Board profiles

The included profiles are:

```text
configs/boards/rk3588-evb1-lp4-v10-linux.conf
configs/boards/rk3588s-rock-5c.conf
```

It selects:

- Kernel defconfig and one exact DTB.
- Rockchip U-Boot `make.sh` board.
- Loader and U-Boot artifact names.
- Serial console and extra kernel arguments.
- Raw image size, partition geometry, and bootloader sectors.

Copy the closest profile when adding hardware support. A final image build
requires `BOARD=<profile-name>` and refuses to guess a board.

The loader and U-Boot regions must remain before `BOOT_START_MIB`. The current
layout reserves the first 16 MiB, writes the loader at sector 64, writes
`uboot.img` at sector 16384, and starts the FAT boot partition at 16 MiB.

## Kernel fragment

`configs/kernel/rootfs-base.config` is merged after the board defconfig. It
enables the minimum kernel facilities needed by the generated Buildroot and
Debian systems, including ext4, MMC, devtmpfs, namespaces, and cgroups.

Board-specific kernel configuration still belongs in the BSP defconfig or an
additional board adaptation, not in this shared baseline.
