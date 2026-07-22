# wifibt overlay

Optional WiFi/BT **firmware package** plugin. Not part of the pure build core.

Mental model (same for AIC / Broadcom / others):

1. Get a firmware package (`.deb`) or static blobs  
2. Install into rootfs  
3. Remap paths for the board’s kernel driver  

## Layout

```text
overlays/wifibt/
  plugin.sh
  lib.sh
  sync-assets.sh
  packages/          # drop or download *.deb here (preferred)
  firmware/<CHIP>/   # optional static blobs (fallback)
  README.md
```

## Enable

```bash
DEBIAN_OVERLAYS=...,wifibt
WIFIBT_CHIP=AIC8800D80          # or AP6275S / none
WIFIBT_DEB=                     # optional path or URL to .deb
WIFIBT_SOURCE=auto              # auto|package|firmware|sdk
WIFIBT_REQUIRED=no
WIFIBT_FIRMWARE_SYMLINKS=rockchip-vendor
```

`auto` order: package (`.deb`) → `firmware/<CHIP>/` → SDK `external/rkwifibt` (last resort).

## Populate

### AIC8800 (CokePi) — package path

```bash
./rootfs/debian/overlays/wifibt/sync-assets.sh --deb-aic
# or a local/release URL:
./rootfs/debian/overlays/wifibt/sync-assets.sh --deb \
  https://github.com/radxa-pkg/aic8800/releases/download/.../aic8800-firmware_..._all.deb
```

Then build with board defaults (`WIFIBT_CHIP=AIC8800D80`). The plugin extracts
`lib/firmware/aic8800_fw/SDIO/aic8800D80/` from the deb and installs to
`/lib/firmware/aic8800D80/` plus Rockchip vendor symlinks.

### Other chips — same idea

- If you have a vendor `.deb`: put it in `packages/` or set `WIFIBT_DEB=...`
- Else drop blobs under `firmware/AP6275S/` (flat)  
  or stage from BSP only as fallback:

```bash
./rootfs/debian/overlays/wifibt/sync-assets.sh --from-bsp /path/to/full-bsp AP6275S
```

Debian `firmware-brcm80211` is for **mainline brcmfmac**, not Rockchip `bcmdhd`
file names — do not assume `apt install` alone matches vendor drivers.

## Not in core

No Makefile target. No feature tokens in `DEBIAN_PACKAGES`.
