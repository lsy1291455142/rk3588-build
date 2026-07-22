# assets/

Host-side optional blobs that are **not** part of the pure build core.

## Custom firmware (`firmware/`)

Generic firmware blobs installed by the build core into `/lib/firmware`
(see `install_custom_firmware`). Board-specific blobs may also live under
`configs/boards/<board>/firmware/`.

## Board-local firmware staging

Board-specific firmware (e.g. CokePi AIC8800) is managed by board-local plugins under
`rootfs/debian/boards/<board>/` (e.g. `stage-aic8800-firmware.sh`).

`assets/wifibt/` remains a legacy fallback location.
