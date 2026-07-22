# Debian rootfs layout

This tree holds optional attachments for the Debian rootfs. The build core in
`scripts/build_debian.sh` stays pure: packages, users, modules, and image pack.
Everything policy-shaped (ssh lab conf, console, firstboot, network stack, WiFi
firmware) is an optional overlay plugin selected by `DEBIAN_OVERLAYS`.

## Layout

| Path | When applied |
|---|---|
| `boards/<board>/plugin.sh` | Always, when `BOARD` matches and file exists |
| `boards/<board>/overlay/` | Always (via board plugin, or static fallback) |
| `overlays/<name>/plugin.sh` | When selected via `DEBIAN_OVERLAYS` |
| `overlays/<name>/overlay/` (or `overlay-*`) | Applied by that plugin |

Apply order: board plugin/overlay → selected overlay plugins (list order).
Later trees overwrite earlier files at the same relative path.

Core build does **not** always copy a global `overlay/`. Attachments only land
when board/plugin selection applies.

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

Each optional plugin exports `plugin_apply root_dir`. Add a new overlay by
creating `overlays/<name>/plugin.sh` (plus optional static files). Keep package
names out of plugins; packages come only from `DEBIAN_PACKAGES`.

### Board plugins

Board attachments use the same pattern under `boards/<BOARD>/`:

| File | Role |
|---|---|
| `plugin.sh` | Optional; must define `board_plugin_apply(root_dir)` |
| `overlay/` | Static tree (or files prepared by the board plugin) |
| `lib-*.sh` | Board-local helpers (not core Makefile targets) |

If `plugin.sh` is present, core sources it and runs `board_plugin_apply`.
Otherwise, if only `overlay/` exists, core copies that static tree.

Board-local WiFi/BT (CokePi AIC) is an example: `boards/rk3588s-cokepi-model-lp4-v10/plugin.sh`
installs firmware into the rootfs during `make build-rootfs` from
`packages/*.deb` (or host-pre-staged overlay blobs). Docker mounts `rootfs/:ro`,
so the board tree is never written at build time. Manual stage CLI is host-only.

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

## Board plugin example

```text
rootfs/debian/boards/rk3588s-cokepi-model-lp4-v10/
  plugin.sh
  lib-aic8800.sh
  overlay/lib/firmware/aic8800D80/
  packages/                 # deb cache (gitignored)
```

Only files you need; boards without `plugin.sh`/`overlay/` are no-ops.
See `rootfs/debian/boards/README.md` for the board plugin convention.
