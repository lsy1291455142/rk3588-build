# assets/

Host-side optional blobs that are **not** part of the minimal kernel/u-boot/rkbin SDK.

## `wifibt/`

Rockchip WiFi/BT firmware tree, same layout as BSP `external/rkwifibt/firmware/`:

```text
assets/wifibt/
  broadcom/AP6275S/{wifi,bt}/...
  broadcom/AP6256/...
  realtek/RTL8822CS/...
  infineon/CYW43455/...
  aicsemi/AIC8800D80/          # flat files; installed to /lib/firmware/aic8800D80/
```

### Populate

From a full vendor BSP (e.g. CokePi):

```bash
make sync-wifibt-assets SDK_PATH=/path/to/full-bsp WIFIBT_CHIP=AP6275S
# or all Broadcom AP6xxx:
make sync-wifibt-assets SDK_PATH=/path/to/full-bsp WIFIBT_CHIP=ALL_AP
```

If the Docker SDK volume already contains `external/rkwifibt`, you do **not** need assets;
the wifibt plugin prefers the SDK tree, then falls back here.

### Use

Board profile or CLI:

```bash
# board conf
DEBIAN_PACKAGES_DEFAULT="network-manager,wpasupplicant,i2c-tools,usbutils,pciutils,mmc-utils"
: "${WIFIBT_CHIP:=AP6275S}"
: "${WIFIBT_REQUIRED:=no}"   # yes = fail build if firmware missing

make build-rootfs BOARD=... ROOTFS=debian DEBIAN_PACKAGES=network-manager,wpasupplicant WIFIBT_CHIP=AP6275S
```

Firmware is installed to `/lib/firmware` with Rockchip-compatible links:

- `/vendor` → `/system`
- `/system/etc/firmware` → `/lib/firmware`
- optional `fw_bcmdhd.bin` / `nvram.txt` compatibility symlinks (Broadcom)
- AIC chips keep a **subdirectory** (e.g. `/lib/firmware/aic8800D80/`), because
  the kernel sets `CONFIG_AIC_FW_PATH="/vendor/etc/firmware"` and appends
  `aic8800D80/` at runtime

### AIC8800 (CokePi)

Rockchip `external/rkwifibt` has **drivers/docs for Broadcom/Realtek/Infineon only**.
CokePi hardware uses **AIC8800D80** (SDIO `vid:0xC8A1`). Firmware is not in the
SDK tree; place files under `assets/wifibt/aicsemi/AIC8800D80/` (or extract from
[radxa-pkg/aic8800](https://github.com/radxa-pkg/aic8800) `aic8800-firmware` deb,
`lib/firmware/aic8800_fw/SDIO/aic8800D80/`).

```bash
make build-rootfs BOARD=rk3588s-cokepi-model-lp4-v10 ROOTFS=debian \
  DEBIAN_PACKAGES=network-manager,wpasupplicant,i2c-tools \
  WIFIBT_CHIP=AIC8800D80 WIFIBT_REQUIRED=yes
```

### License

Firmware binaries are proprietary to the module vendors. Do not redistribute
without checking the original BSP/module license. This directory is gitignored
for binary content by default; only this README is tracked if you choose so.
