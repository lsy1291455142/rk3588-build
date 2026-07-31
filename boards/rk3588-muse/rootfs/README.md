# MUSE RK3588 — board Debian plugin

Board-specific attachments for `rk3588-muse`. Same convention as optional
`overlays/<name>/plugin.sh`, but always applied when `BOARD` matches
(no `DEBIAN_OVERLAYS` selection).

## Layout

```text
plugin.sh                              # board_plugin_apply(root_dir) — auto at build
lib-fcu761k.sh                         # install/stage helpers
stage-fcu761k-firmware.sh              # optional host-only CLI
overlay/
  lib/firmware/aic8800_fw/USB/         # optional pre-staged blobs (gitignored except SOURCE.txt)
  vendor -> /system
  system/etc/firmware -> /lib/firmware
packages/                              # aic8800-firmware_*.deb input (gitignored)
```

## Convention

| Piece | Role |
|---|---|
| `plugin.sh` | Required entry when board needs logic; core sources it and calls `board_plugin_apply` |
| `overlay/` | Static files copied into rootfs |
| `packages/` | Local deb inputs read by the plugin (build does not write here) |
| helpers | Board-local `lib-*.sh` / scripts; **not** Makefile core targets |

Boards with only static files may omit `plugin.sh`; core then copies `overlay/` only.

Docker mounts `./rootfs:ro`. Board plugins must install into `root_dir` only;
they must not write back into the board tree during build.

## WiFi/BT: FCU761K-L (AIC8800DC, USB)

| Property | Value |
|----------|-------|
| Module | FCU761K-L (Quectel) |
| Chip | AIC8800DC (AIC semi) |
| Interface | USB (not SDIO) |
| USB path | `usb_host1` → CH334H hub → FCU761K-L downstream |
| Firmware source | [radxa-pkg/aic8800](https://github.com/radxa-pkg/aic8800/releases) (public, no auth) |
| Deb package | `aic8800-firmware_*_all.deb` (same package covers SDIO/USB/PCIE) |
| Deb firmware path | `lib/firmware/aic8800_fw/USB/{aic8800DC/,aic8800/}` |
| Driver | Integrated into kernel tree via `board.hooks.sh` (auto at `make build-kernel`) |

Firmware is board-local: the plugin installs Radxa `aic8800-firmware` into the
rootfs from `packages/*.deb` (or host-pre-staged overlay blobs). No generic
`wifibt` plugin, no `WIFIBT_*` env.

Same pattern as CokePi Model (`lib-aic8800.sh`), adapted for USB/AIC8800DC
instead of SDIO/AIC8800D80.

```bash
# Normal: put deb in packages/, then build
cp aic8800-firmware_5.0+git20260123.5f7be68d-7_all.deb \
  boards/rk3588-muse/rootfs/packages/
make build-rootfs

# Optional host-only: materialize blobs into overlay/ for inspection
./boards/rk3588-muse/rootfs/stage-fcu761k-firmware.sh
```

Source: https://github.com/radxa-pkg/aic8800/releases (`aic8800-firmware`).

### Driver integration (automatic via board.hooks.sh)

The AIC8800 driver is **not in the mainline kernel**.  Integration is
**fully automated** by `boards/rk3588-muse/board.hooks.sh` via the
`pre_build_kernel` hook — no manual steps required.

```text
make build-kernel
  └─ build_kernel.sh
       ├─ run_hook pre_build_kernel        ← board.hooks.sh runs here
       │    ├─ git clone radxa-pkg/aic8800
       │    ├─ apply 8 USB patches (firmware path, BlueZ, build fixes, …)
       │    ├─ copy aic8800/  → drivers/net/wireless/aic8800/
       │    ├─ copy aic_btusb/ → drivers/bluetooth/aic_btusb/
       │    └─ wire Makefile + Kconfig
       ├─ make defconfig                    ← picks up new Kconfig
       ├─ merge_config.sh + kernel.config   ← CONFIG_AIC_WLAN_SUPPORT=m
       ├─ make olddefconfig
       └─ make Image … modules              ← compiles aic8800 modules ✅
```

**What the hook does** (idempotent — safe for repeated builds):

| Step | Action |
|------|--------|
| 1 | Shallow-clone `radxa-pkg/aic8800` (branch `main`) to a temp dir |
| 2 | Apply 8 patches relevant for kernel 5.10 USB (skip 6.x/7.x, SDIO, PCIe) |
| 3 | Copy WiFi driver → `drivers/net/wireless/aic8800/` |
| 4 | Copy BT driver → `drivers/bluetooth/aic_btusb/` |
| 5 | Append `obj-$(CONFIG_AIC_WLAN_SUPPORT) += aic8800/` to wireless Makefile |
| 6 | Append `source "...aic8800/Kconfig"` to wireless Kconfig |
| 7 | Append `obj-$(CONFIG_AIC_WLAN_SUPPORT) += aic_btusb/` to bluetooth Makefile |

**Patches applied** (in series order, from `debian/patches/`):

1. `fix-usb-firmware-path.patch` — firmware path → `/lib/firmware/aic8800_fw/USB/`
2. `fix-aic_btusb-use-bluez-by-default.patch` — `CONFIG_BLUEDROID=0` (use BlueZ)
3. `fix-usb-build.patch` — suppress unused-variable warnings
4. `fix-usb-suspend-reboot-hang.patch` — fix USB suspend/reboot hang
5. `fix-debug-file-with-no-debug-symbols.patch` — debug symbol fix
6. `fix-Lower-the-debugging-log-level.patch` — reduce log verbosity
7. `fix-vmalloc-not-include.patch` — vmalloc header fix
8. `fix-build-on-low-memory-devices.patch` — low-memory build fix

**Driver modules** (compiled as part of `make modules`):

| Module | Function |
|--------|----------|
| `aic_load_fw.ko` | Firmware loader (shared by WiFi + BT) |
| `aic8800_fdrv.ko` | WiFi driver (main) |
| `aic_btusb.ko` | BT USB driver |

**Kernel configs** (in `boards/rk3588-muse/kernel.config`):

```
CONFIG_AIC_WLAN_SUPPORT=m     # gate for aic8800/ + aic_btusb/
CONFIG_CFG80211=y             # wireless core
CONFIG_MAC80211=y             # MAC layer
```

The driver Makefile self-contains `CONFIG_PLATFORM_UBUNTU ?= y` and adds
`-DCONFIG_PLATFORM_UBUNTU` to `ccflags-y`, so the patched firmware path
(`/lib/firmware/aic8800_fw/USB/`) is used without any kernel config change.
