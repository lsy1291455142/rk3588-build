# Debian rootfs overlays

Static files and optional feature content live here. `scripts/build_debian.sh`
installs packages and runs dynamic steps; configuration should prefer overlays
over heredocs in the build script.

## Layout

| Path | When applied |
|---|---|
| `overlay/` | Always (minbase and feature builds) |
| `overlay-networkd/` | When `nm` feature is **not** enabled |
| `features/<token>/overlay/` | When that `DEBIAN_FEATURES` token is enabled |
| `boards/<board>/overlay/` | When `BOARD` matches a directory name |

Apply order: `overlay` → network stack overlay → each enabled feature → board.
Later trees overwrite earlier files at the same relative path.

## Templates

Files ending in `.in` are treated as templates. Placeholders use `@NAME@` form
and are expanded at install time (for example `@BOARD@`, `@ROOTFS_HOSTNAME@`,
`@CONSOLE_SPEED@`). The installed path drops the `.in` suffix.

Executable bit is preserved from the source file (`chmod +x` on scripts).

## What stays in the build script

- Package selection (`mmdebstrap` / `DEBIAN_FEATURES`)
- User/password/hostname generation
- Kernel modules extract + `depmod`
- WiFi firmware install (`install_wifibt_firmware`)
- systemd unit enable + image packing
- Paths that depend on runtime variables without a fixed tree path
  (for example `serial-getty@${CONSOLE_DEVICE}.service.d`)

## Adding a feature overlay

1. Put static files under `features/<token>/overlay/...` matching rootfs paths.
2. If the feature needs packages, add them in `debian_feature_packages()` in
   `scripts/lib/common.sh`.
3. Document the token in `docs/usage/debian-features.md`.

## Board overlay example

```text
rootfs/debian/boards/rk3588-muse/overlay/etc/issue
```

Only files you need; empty board dirs are ignored.
