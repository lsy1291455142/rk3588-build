# assets/

Host-side optional blobs that are **not** part of the pure build core.

## Custom firmware (`firmware/`)

Generic firmware blobs installed by the build core into `/lib/firmware`
(see `install_custom_firmware`). Board-specific blobs may also live under
`configs/boards/<board>/firmware/`.

## Legacy `wifibt/` (deprecated)

WiFi/BT is the optional overlay plugin:

```bash
./rootfs/debian/overlays/wifibt/sync-assets.sh --deb-aic
# or --deb /path/to/firmware.deb
```

Prefer `overlays/wifibt/packages/*.deb` or `overlays/wifibt/firmware/<CHIP>/`.
`assets/wifibt/` remains a legacy fallback only.

See [rootfs/debian/overlays/wifibt/README.md](../rootfs/debian/overlays/wifibt/README.md).
