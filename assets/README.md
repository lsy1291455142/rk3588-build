# assets/

Host-side optional blobs that are **not** part of the pure build core.

## Custom firmware (`firmware/`)

Generic firmware blobs installed by the build core into `/lib/firmware`
(see `install_custom_firmware`). Board-specific blobs may also live under
`configs/boards/<board>/firmware/`.

## Legacy `wifibt/` (deprecated)

WiFi/BT firmware is owned by the optional overlay plugin:

```text
rootfs/debian/overlays/wifibt/
  plugin.sh
  lib.sh
  sync-assets.sh
  firmware/          # preferred local tree
  README.md
```

Populate with:

```bash
./rootfs/debian/overlays/wifibt/sync-assets.sh /path/to/full-bsp AP6275S
```

`assets/wifibt/` is still searched as a **legacy fallback** by the overlay for
older checkouts. New trees should use `overlays/wifibt/firmware/` only.

See [rootfs/debian/overlays/wifibt/README.md](../rootfs/debian/overlays/wifibt/README.md)
and [docs/usage/debian-features.md](../docs/usage/debian-features.md).
