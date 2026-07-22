# Debian rootfs layout

This tree holds optional attachments for the Debian rootfs. The build core in
`scripts/build_debian.sh` stays pure: packages, users, modules, and image pack.
Everything policy-shaped (ssh lab conf, console, firstboot, network stack, WiFi
firmware) is an optional overlay plugin selected by `DEBIAN_OVERLAYS`.

## Layout

| Path | When applied |
|---|---|
| `boards/<board>/overlay/` | Always, when `BOARD` matches a directory name |
| `overlays/<name>/plugin.sh` | When selected via `DEBIAN_OVERLAYS` |
| `overlays/<name>/overlay/` (or `overlay-*`) | Applied by that plugin |

Apply order: board overlay → selected overlay plugins (list order).
Later trees overwrite earlier files at the same relative path.

Core build does **not** always copy a global `overlay/`. Attachments only land
when their plugin is selected.

## Packages

`DEBIAN_PACKAGES` / board `DEBIAN_PACKAGES_DEFAULT` is an exact APT package list
(comma or space separated). Write what you want installed; only those names are
installed on top of minbase. There are no feature aliases (`nm`, `hwdebug`, …).

Examples:

```bash
DEBIAN_PACKAGES=network-manager,wpasupplicant,i2c-tools,htop
DEBIAN_PACKAGES=none   # force minbase only
```

## Overlay plugins

Selection: `DEBIAN_OVERLAYS` (or board `DEBIAN_OVERLAYS_DEFAULT` when empty).

| Value | Meaning |
|---|---|
| (empty) | Board default if set, else none |
| `none` / `off` / `-` | No optional overlays |
| `all` | Every `overlays/*/plugin.sh` |
| `base,console,network` | Explicit ordered list |

Built-ins:

| Overlay | Role |
|---|---|
| `base` | SSH password/root conf, hostkey ExecStartPre, udev GPU perms; enable ssh + resolved |
| `console` | Serial-getty baud drop-in + enable `serial-getty@CONSOLE_DEVICE` |
| `firstboot` | Grow rootfs oneshot service/script |
| `firstboot-info` | MOTD / first-boot banner templates |
| `network` | If NetworkManager binary present → NM conf+enable; else networkd overlay+enable |
| `wifibt` | Optional plugin: WiFi/BT firmware (`WIFIBT_*`); see `overlays/wifibt/README.md` |

Each plugin exports `plugin_apply root_dir`. Add a new overlay by creating
`overlays/<name>/plugin.sh` (plus optional static files). Keep package names out
of plugins; packages come only from `DEBIAN_PACKAGES`.

Host-side WiFi/BT firmware sync (not a core make target):
`./rootfs/debian/overlays/wifibt/sync-assets.sh /path/to/full-bsp [CHIP]`.

```bash
make build-rootfs DEBIAN_OVERLAYS=base,console,firstboot,network
make build-rootfs DEBIAN_OVERLAYS=none
make build-rootfs DEBIAN_OVERLAYS=all
```

## Templates

Files ending in `.in` are treated as templates. Placeholders use `@NAME@` form
and are expanded at install time (for example `@BOARD@`, `@ROOTFS_HOSTNAME@`,
`@CONSOLE_SPEED@`, `@DEBIAN_PACKAGES@`, `@DEBIAN_OVERLAYS@`). The installed path
drops the `.in` suffix.

Executable bit is preserved from the source file (`chmod +x` on scripts).

## What stays in the build script

- Package selection (`mmdebstrap` / `DEBIAN_PACKAGES`)
- User/password/hostname generation
- Kernel modules extract + `depmod`
- Custom firmware from `assets/firmware` / board `firmware/`
- Overlay selection + `plugin_apply` dispatch
- systemd unit enable helpers + image packing

## Board overlay example

```text
rootfs/debian/boards/rk3588-muse/overlay/etc/issue
```

Only files you need; empty board dirs are ignored.
