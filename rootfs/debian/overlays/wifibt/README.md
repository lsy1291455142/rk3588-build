# wifibt overlay

Optional WiFi/BT firmware plugin. **Not part of the pure build core.**

## Layout

```text
overlays/wifibt/
  plugin.sh          # DEBIAN_OVERLAYS entry (plugin_apply)
  lib.sh             # install/resolve helpers (overlay-owned)
  sync-assets.sh     # host helper: copy firmware from full BSP
  firmware/          # optional local firmware tree (preferred)
  README.md
```

Legacy path still searched: `assets/wifibt/` (older checkouts).

## Enable

```bash
DEBIAN_OVERLAYS=...,wifibt
# board conf also may set:
WIFIBT_CHIP=AIC8800D80          # or AP6275S / none / ALL_AP ...
WIFIBT_SOURCE=sdk-or-assets     # sdk | assets | sdk-or-assets
WIFIBT_REQUIRED=no              # yes fails build if missing
WIFIBT_FIRMWARE_SYMLINKS=rockchip-vendor  # or none
```

## Populate firmware

```bash
# From full vendor BSP (host, no Docker):
./rootfs/debian/overlays/wifibt/sync-assets.sh /path/to/full-bsp AP6275S
./rootfs/debian/overlays/wifibt/sync-assets.sh /path/to/full-bsp ALL_AP
./rootfs/debian/overlays/wifibt/sync-assets.sh /path/to/full-bsp AIC8800D80

# Or manually drop blobs under:
#   rootfs/debian/overlays/wifibt/firmware/aicsemi/AIC8800D80/
#   rootfs/debian/overlays/wifibt/firmware/broadcom/AP6275S/
```

If the Docker SDK volume already has `external/rkwifibt/firmware`, assets are optional
when `WIFIBT_SOURCE=sdk-or-assets` (default).

## AIC8800 (CokePi)

Often **not** in `rkwifibt`. Place files under `firmware/aicsemi/AIC8800D80/`
(or extract from Radxa `aic8800-firmware` deb). `SOURCE.txt` alone does not count.
