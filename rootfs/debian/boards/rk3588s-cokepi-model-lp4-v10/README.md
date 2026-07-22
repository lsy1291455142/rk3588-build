# CokePi Model LP4 V1.0 — board Debian overlay

Board-specific attachments for `rk3588s-cokepi-model-lp4-v10`. Applied
automatically by the pure build core when `BOARD` matches (no plugin list).

## Layout

```text
overlay/
  lib/firmware/aic8800D80/   # AIC WiFi/BT firmware (stage from Radxa deb)
  vendor -> /system
  system/etc/firmware -> /lib/firmware
packages/                    # optional staged aic8800-firmware_*.deb
stage-aic8800-firmware.sh    # host helper (not a make target)
```

## WiFi/BT

Drivers come from the CokePi kernel modules. Firmware is board-local static
files (no generic `wifibt` plugin, no `WIFIBT_*` env).

**Firmware pin:** use Radxa **3.0** `aic8800-firmware` (default in
`stage-aic8800-firmware.sh`). That line has patch-table `info_len=4`.
Radxa **4.0/5.0** firmware uses `info_len=6` and can overflow/panic with the
CokePi BSP driver. Keep adid/patch/fmac from the **same** package.

```bash
./rootfs/debian/boards/rk3588s-cokepi-model-lp4-v10/stage-aic8800-firmware.sh
make build-rootfs
```

Without staging, rootfs still builds; `/lib/firmware/aic8800D80/` only has
`SOURCE.txt` and WiFi will not load firmware on device.

Source: https://github.com/radxa-pkg/aic8800/releases (`aic8800-firmware`, 3.0 line).
