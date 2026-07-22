# CokePi Model LP4 V1.0 — board Debian plugin

Board-specific attachments for `rk3588s-cokepi-model-lp4-v10`. Same convention
as optional `overlays/<name>/plugin.sh`, but always applied when `BOARD` matches
(no `DEBIAN_OVERLAYS` selection).

## Layout

```text
plugin.sh                    # board_plugin_apply(root_dir) — auto at build
lib-aic8800.sh               # stage_aic8800_firmware() helper
stage-aic8800-firmware.sh    # optional manual CLI (same staging)
overlay/
  lib/firmware/aic8800D80/   # AIC firmware blobs (gitignored except SOURCE.txt)
  vendor -> /system
  system/etc/firmware -> /lib/firmware
packages/                    # cached aic8800-firmware_*.deb (gitignored)
```

## Convention

| Piece | Role |
|---|---|
| `plugin.sh` | Required entry when board needs logic; core sources it and calls `board_plugin_apply` |
| `overlay/` | Static files (and/or files produced by the plugin before apply) |
| helpers | Board-local `lib-*.sh` / scripts; **not** Makefile core targets |

Boards with only static files may omit `plugin.sh`; core then copies `overlay/` only.

## WiFi/BT

Drivers come from the CokePi kernel modules. Firmware is board-local: the plugin
stages Radxa `aic8800-firmware` (default **3.0**, `info_len=4`) into `overlay/`
during `make build-rootfs`. No generic `wifibt` plugin, no `WIFIBT_*` env.

**Firmware pin:** Radxa **3.0** line matches the CokePi BSP driver. **4.0/5.0**
uses `info_len=6` and can panic. Keep adid/patch/fmac from the **same** package.

```bash
# Normal: build auto-stages (uses packages/*.deb cache or downloads 3.0)
make build-rootfs

# Optional manual re-stage / override
./rootfs/debian/boards/rk3588s-cokepi-model-lp4-v10/stage-aic8800-firmware.sh
./rootfs/debian/boards/rk3588s-cokepi-model-lp4-v10/stage-aic8800-firmware.sh /path/to.deb
```

Source: https://github.com/radxa-pkg/aic8800/releases (`aic8800-firmware`, 3.0 line).
