# CokePi Model LP4 V1.0 — board Debian plugin

Board-specific attachments for `rk3588s-cokepi-model-lp4-v10`. Same convention
as optional `overlays/<name>/plugin.sh`, but always applied when `BOARD` matches
(no `DEBIAN_OVERLAYS` selection).

## Layout

```text
plugin.sh                    # board_plugin_apply(root_dir) — auto at build
lib-aic8800.sh               # install/stage helpers
stage-aic8800-firmware.sh    # optional host-only CLI
overlay/
  lib/firmware/aic8800D80/   # optional pre-staged blobs (gitignored except SOURCE.txt)
  vendor -> /system
  system/etc/firmware -> /lib/firmware
packages/                    # aic8800-firmware_*.deb input (gitignored)
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

## WiFi/BT

Drivers come from the CokePi kernel modules. Firmware is board-local: the plugin
installs Radxa `aic8800-firmware` (default **3.0**, `info_len=4`) into the
rootfs from `packages/*.deb` (or host-pre-staged overlay blobs). No generic
`wifibt` plugin, no `WIFIBT_*` env.

**Firmware pin:** Radxa **3.0** line matches the CokePi BSP driver. **4.0/5.0**
uses `info_len=6` and can panic. Keep adid/patch/fmac from the **same** package.

```bash
# Normal: put deb in packages/, then build
cp aic8800-firmware_3.0+git20240327.3561b08f-7_all.deb \
  rootfs/debian/boards/rk3588s-cokepi-model-lp4-v10/packages/
make build-rootfs

# Optional host-only: materialize blobs into overlay/ for inspection
./rootfs/debian/boards/rk3588s-cokepi-model-lp4-v10/stage-aic8800-firmware.sh
```

Source: https://github.com/radxa-pkg/aic8800/releases (`aic8800-firmware`, 3.0 line).
