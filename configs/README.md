# Configuration

The image pipeline is driven by board profiles in `configs/boards/`.

## Board profiles

The included profiles are:

```text
configs/boards/rk3588-evb1-lp4-v10-linux.conf
configs/boards/rk3588-cokepi-plus-lp4-v10.conf
configs/boards/rk3588s-rock-5c.conf
configs/boards/rk3588s-cokepi-model-lp4-v10.conf
```

The CokePi SDK provides separate official defaults for CokePi Plus (RK3588)
and CokePi Model (RK3588S). Select the profile matching the printed board
model; these project profiles select the SDK's HDMI DTB variants.

It selects:

- Kernel defconfig and one exact DTB.
- Rockchip U-Boot `make.sh` board.
- Loader and U-Boot artifact names.
- Serial console and extra kernel arguments.
- Raw image size, partition geometry, and bootloader sectors.

Copy the closest profile when adding hardware support. All component and
image builds require `BOARD=<profile-name>` from `.env`, `make use-board-*`,
or the command line. There is no default board profile.

The loader and U-Boot regions must remain before `BOOT_START_MIB`. The current
layout reserves the first 16 MiB, writes the loader at sector 64, writes
`uboot.img` at sector 16384, and starts the FAT boot partition at 16 MiB.

## Kernel fragment

`configs/kernel/rootfs-base.config` is merged after the board defconfig. It
enables the minimum kernel facilities needed by the generated Buildroot and
Debian systems, including ext4, MMC, devtmpfs, namespaces, and cgroups.

Board-specific kernel configuration still belongs in the BSP defconfig or an
additional board adaptation, not in this shared baseline.
