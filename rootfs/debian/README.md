# Debian rootfs layout

Static files and optional plugins live here. `scripts/build_debian.sh`
installs packages and runs dynamic steps; configuration should prefer overlays
and plugins over heredocs in the build script.

## Layout

| Path | When applied |
|---|---|
| `overlay/` | Always (minbase and package builds) |
| `boards/<board>/overlay/` | When `BOARD` matches a directory name |
| `plugins/*.sh` | Always, after packages + base overlay |
| `plugins/<name>/overlay*` | Applied by the matching plugin |

Apply order: base `overlay` → board overlay → plugins (sorted by filename).
Later trees overwrite earlier files at the same relative path.

## Packages

`DEBIAN_PACKAGES` / board `DEBIAN_PACKAGES_DEFAULT` is an exact APT package list
(comma or space separated). Write what you want installed; only those names are
installed on top of minbase. There are no feature aliases (`nm`, `hwdebug`, …).

Examples:

```bash
DEBIAN_PACKAGES=network-manager,wpasupplicant,i2c-tools,htop
DEBIAN_PACKAGES=none   # force minbase only
```

## Plugins

Plugins under `plugins/*.sh` export `plugin_apply root_dir` and own optional
project behavior:

| Plugin | Role |
|---|---|
| `00-systemd-base.sh` | Enable ssh, firstboot, serial-getty, resolved |
| `10-firstboot-info.sh` | Board banner / MOTD overlay (disable with `DEBIAN_FIRSTBOOT_INFO=no`) |
| `network.sh` | If `/usr/sbin/NetworkManager` exists → NM conf + enable; else networkd overlay + enable |
| `20-wifibt.sh` | Install WiFi/BT firmware when `WIFIBT_CHIP` is set |

Add a new plugin by dropping `plugins/NN-name.sh` (and optional overlay files
next to it). Keep package names out of plugins; packages come only from
`DEBIAN_PACKAGES`.

## Templates

Files ending in `.in` are treated as templates. Placeholders use `@NAME@` form
and are expanded at install time (for example `@BOARD@`, `@ROOTFS_HOSTNAME@`,
`@CONSOLE_SPEED@`, `@DEBIAN_PACKAGES@`). The installed path drops the `.in`
suffix.

Executable bit is preserved from the source file (`chmod +x` on scripts).

## What stays in the build script

- Package selection (`mmdebstrap` / `DEBIAN_PACKAGES`)
- User/password/hostname generation
- Kernel modules extract + `depmod`
- Custom firmware from `assets/firmware` / board `firmware/`
- systemd unit enable helpers + image packing
- Paths that depend on runtime variables without a fixed tree path
  (for example `serial-getty@${CONSOLE_DEVICE}.service.d`)

## Board overlay example

```text
rootfs/debian/boards/rk3588-muse/overlay/etc/issue
```

Only files you need; empty board dirs are ignored.
