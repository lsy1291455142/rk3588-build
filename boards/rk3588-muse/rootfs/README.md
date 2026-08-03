# MUSE RK3588 — board Debian plugin

Board-specific attachments for `rk3588-muse`. Same convention as optional
`overlays/<name>/plugin.sh`, but always applied when `BOARD` matches
(no `DEBIAN_OVERLAYS` selection).

## Layout

```text
plugin.sh                              # board_plugin_apply(root_dir) — auto at build
lib-fcu761k.sh                         # AIC8800 install/stage helpers
lib-rm500q.sh                          # RM500Q-GL runtime lib + install helpers
stage-fcu761k-firmware.sh              # optional host-only CLI (AIC8800)
overlay/
  lib/firmware/aic8800_fw/USB/         # optional pre-staged blobs (gitignored except SOURCE.txt)
  lib/firmware/sdx55m/                 # optional pre-staged modem firmware (.mbn)
  usr/local/lib/rm500q.sh              # runtime helper library (installed to rootfs)
  usr/local/sbin/rm500q-connect.sh     # CLI: status / connect / disconnect / at
  usr/local/sbin/quectel-CM            # QConnectManager V1.6.8 (aarch64, pre-compiled)
  usr/local/sbin/quectel-qmi-proxy     # QMI proxy (for multi-client QMI access)
  usr/local/sbin/quectel-mbim-proxy    # MBIM proxy
  usr/local/sbin/quectel-atc-proxy     # AT command proxy
  usr/share/udhcpc/default.script      # udhcpc dispatcher (IPv4)
  usr/share/udhcpc/default.script_ip   # udhcpc dispatcher (IPv6)
  etc/systemd/system/rm500q-modem.service  # auto-connect service (enabled)
  vendor -> /system
  system/etc/firmware -> /lib/firmware
packages/                              # aic8800-firmware_*.deb, rm500q*firmware* (gitignored)
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

## WiFi/BT: FCU761K-L (AIC8800DC, USB)

| Property | Value |
|----------|-------|
| Module | FCU761K-L (Quectel) |
| Chip | AIC8800DC (AIC semi) |
| Interface | USB (not SDIO) |
| USB path | `usb_host1` → CH334H hub → FCU761K-L downstream |
| Firmware source | [radxa-pkg/aic8800](https://github.com/radxa-pkg/aic8800/releases) (public, no auth) |
| Deb package | `aic8800-firmware_*_all.deb` (same package covers SDIO/USB/PCIE) |
| Deb firmware path | `lib/firmware/aic8800_fw/USB/{aic8800DC/,aic8800/}` |
| Driver | Integrated into kernel tree via `board.hooks.sh` (auto at `make build-kernel`) |

Firmware is board-local: the plugin installs Radxa `aic8800-firmware` into the
rootfs from `packages/*.deb` (or host-pre-staged overlay blobs). No generic
`wifibt` plugin, no `WIFIBT_*` env.

Same pattern as CokePi Model (`lib-aic8800.sh`), adapted for USB/AIC8800DC
instead of SDIO/AIC8800D80.

```bash
# Normal: put deb in packages/, then build
cp aic8800-firmware_5.0+git20260123.5f7be68d-7_all.deb \
  boards/rk3588-muse/rootfs/packages/
make build-rootfs

# Optional host-only: materialize blobs into overlay/ for inspection
./boards/rk3588-muse/rootfs/stage-fcu761k-firmware.sh
```

Source: https://github.com/radxa-pkg/aic8800/releases (`aic8800-firmware`).

### Driver integration (automatic via board.hooks.sh)

The AIC8800 driver is **not in the mainline kernel**.  Integration is
**fully automated** by `boards/rk3588-muse/board.hooks.sh` via the
`pre_build_kernel` hook — no manual steps required.

```text
make build-kernel
  └─ build_kernel.sh
       ├─ run_hook pre_build_kernel        ← board.hooks.sh runs here
       │    ├─ git clone radxa-pkg/aic8800
       │    ├─ apply 8 USB patches (firmware path, BlueZ, build fixes, …)
       │    ├─ copy aic8800/  → drivers/net/wireless/aic8800/
       │    ├─ copy aic_btusb/ → drivers/bluetooth/aic_btusb/
       │    └─ wire Makefile + Kconfig
       ├─ make defconfig                    ← picks up new Kconfig
       ├─ merge_config.sh + kernel.config   ← CONFIG_AIC_WLAN_SUPPORT=m
       ├─ make olddefconfig
       └─ make Image … modules              ← compiles aic8800 modules ✅
```

**What the hook does** (idempotent — safe for repeated builds):

| Step | Action |
|------|--------|
| 1 | Shallow-clone `radxa-pkg/aic8800` (branch `main`) to a temp dir |
| 2 | Apply 8 patches relevant for kernel 5.10 USB (skip 6.x/7.x, SDIO, PCIe) |
| 3 | Copy WiFi driver → `drivers/net/wireless/aic8800/` |
| 4 | Copy BT driver → `drivers/bluetooth/aic_btusb/` |
| 5 | Append `obj-$(CONFIG_AIC_WLAN_SUPPORT) += aic8800/` to wireless Makefile |
| 6 | Append `source "...aic8800/Kconfig"` to wireless Kconfig |
| 7 | Append `obj-$(CONFIG_AIC_WLAN_SUPPORT) += aic_btusb/` to bluetooth Makefile |

**Patches applied** (in series order, from `debian/patches/`):

1. `fix-usb-firmware-path.patch` — firmware path → `/lib/firmware/aic8800_fw/USB/`
2. `fix-aic_btusb-use-bluez-by-default.patch` — `CONFIG_BLUEDROID=0` (use BlueZ)
3. `fix-usb-build.patch` — suppress unused-variable warnings
4. `fix-usb-suspend-reboot-hang.patch` — fix USB suspend/reboot hang
5. `fix-debug-file-with-no-debug-symbols.patch` — debug symbol fix
6. `fix-Lower-the-debugging-log-level.patch` — reduce log verbosity
7. `fix-vmalloc-not-include.patch` — vmalloc header fix
8. `fix-build-on-low-memory-devices.patch` — low-memory build fix

**Driver modules** (compiled as part of `make modules`):

| Module | Function |
|--------|----------|
| `aic_load_fw.ko` | Firmware loader (shared by WiFi + BT) |
| `aic8800_fdrv.ko` | WiFi driver (main) |
| `aic_btusb.ko` | BT USB driver |

**Kernel configs** (in `boards/rk3588-muse/kernel.config`):

```
CONFIG_AIC_WLAN_SUPPORT=m     # gate for aic8800/ + aic_btusb/
CONFIG_CFG80211=y             # wireless core
CONFIG_MAC80211=y             # MAC layer
```

The driver Makefile self-contains `CONFIG_PLATFORM_UBUNTU ?= y` and adds
`-DCONFIG_PLATFORM_UBUNTU` to `ccflags-y`, so the patched firmware path
(`/lib/firmware/aic8800_fw/USB/`) is used without any kernel config change.

## 5G Modem: Quectel RM500Q-GL (PCIe/MHI)

| Property | Value |
|----------|-------|
| Module | RM500Q-GL (Quectel) |
| Chip | Qualcomm SDX55 |
| Interface | PCIe 2.0 x1 (pcie2x1l2, combphy0_ps PCIe mode) |
| Protocol | MHI (Modem Host Interface) over PCIe |
| Driver | Quectel PCIe MHI Driver V1.4 (2025-08-08) |
| Driver module | `pcie_mhi.ko` (single self-contained module) |
| PCI Vendor:Device | `17cb:0306` (SDX55, built into driver) |
| AT channel | `/dev/mhi_DUN` |
| QMI channel | `/dev/mhi_QMI0` |
| MBIM channel | `/dev/mhi_MBIM` |
| DIAG channel | `/dev/mhi_DIAG` |
| Data channel | `rmnet_mhi0` + `rmnet_mhi0.1` (QMAP multiplex) |
| Firmware source | Quectel FAE / customer portal (NOT public) |
| Firmware path | `/lib/firmware/sdx55m/*.mbn` |

### Driver: Quectel PCIe MHI V1.4

The V1.4 driver is **fully self-contained** — it includes its own MHI bus
core, PCI controller, UCI channel driver, and network driver.  It does
**not** depend on the mainline MHI bus (`drivers/bus/mhi/`).

| Component | Source file | Function |
|-----------|------------|----------|
| MHI core | `core/mhi_*.c` | MHI protocol, event rings, state machine |
| PCI controller | `controllers/mhi_qcom.c` | PCI glue, firmware loading |
| Firmware paths | `controllers/mhi_qti.c` | BHI/BHIe boot image paths |
| UCI channel | `devices/mhi_uci.c` | `/dev/mhi_DUN`, `/dev/mhi_QMI0`, etc. |
| Network driver | `devices/mhi_netdev_quectel.c` | `rmnet_mhi0` interface + QMAP |

**Module parameters** (insmod/rmmod or `/etc/modprobe.d/`):

| Parameter | Default | Description |
|-----------|---------|-------------|
| `mhi_mbim_enabled` | 0 | Enable MBIM channel |
| `qmap_mode` | 1 | QMAP multiplexing mode |
| `bridge_mode` | 0 | Bridge mode (0=disabled) |
| `debug_mode` | 0 | Debug verbosity |

**Supported kernel versions**: 3.10 ~ 6.12 (5.10 ✅)

### Kernel configuration

The V1.4 driver is built as `obj-y` (unconditionally) — no Kconfig
gating needed.  The only kernel config requirement is PCIe MSI
interrupts.

**Kernel configs** (in `boards/rk3588-muse/kernel.config`):

```
CONFIG_PCI_MSI=y                # PCIe MSI (required by MHI event rings)
```

Mainline MHI bus configs (`CONFIG_MHI_BUS`, `CONFIG_MHI_BUS_PCI_GENERIC`)
are **not** used — the V1.4 driver is self-contained.

### Driver integration (automatic via board.hooks.sh)

The `pre_build_kernel` hook in `board.hooks.sh` handles:

1. **Copy driver** → `drivers/pcie_mhi/` (full tree: core/ + controllers/ + devices/)
2. **Wire Makefile** — append `obj-y += pcie_mhi/` to `drivers/Makefile`
3. **Disable mainline conflict** — comment out `0x0306` in `pci_generic.c`
   to prevent both V1.4 and mainline from claiming the device

Driver source resolution (first match wins):

| Priority | Source | Env var |
|----------|--------|---------|
| 1 | Local directory | `PCIE_MHI_DRIVER_DIR=/path/to/quectel-pcie-mhi` |
| 2 | Local tarball | `PCIE_MHI_DRIVER_TAR=/path/to/driver.tar.gz` |
| 3 | Git URL (shallow clone) | `PCIE_MHI_DRIVER_URL=https://...` |
| 4 | Skip (build succeeds, modem won't work) | — |

```bash
# Build with V1.4 driver from local directory
PCIE_MHI_DRIVER_DIR=/path/to/quectel-pcie-mhi make build-kernel

# Build with V1.4 driver from tarball
PCIE_MHI_DRIVER_TAR=/path/to/Quectel_Linux_PCIE_MHI_Driver_V1.4.tar.gz make build-kernel

# Build with V1.4 driver from git
PCIE_MHI_DRIVER_URL=https://gitcode.com/MUSEInstitute/Quectel_Linux_PCIE_MHI_Driver.git make build-kernel

# Build without driver (modem won't work)
make build-kernel
```

### Firmware installation

RM500Q-GL modem firmware (`.mbn` files) is **not publicly available**.
Obtain from Quectel FAE and install via one of:

```bash
# Option 1: place in packages/ directory
cp rm500q-gl-firmware.tar.gz boards/rk3588-muse/rootfs/packages/
make build-rootfs

# Option 2: pre-stage in overlay
mkdir -p boards/rk3588-muse/rootfs/overlay/lib/firmware/sdx55m/
cp sbl1.mbn amss.mbn boards/rk3588-muse/rootfs/overlay/lib/firmware/sdx55m/
make build-rootfs

# Option 3: set URL (if hosted internally)
RM500Q_FIRMWARE_URL=https://internal.repo/rm500q-fw.tar.gz make build-rootfs
```

Firmware path: `/lib/firmware/sdx55m/` (NOT `/lib/firmware/qcom/sdx55m/`).
Expected files: `sbl1.mbn`, `amss.mbn`, `boot1.mbn` (names may vary).

If firmware is not found, the build **succeeds with a warning** — the modem
will be detected but won't boot without firmware.

### Connection manager: quectel-CM V1.6.8

The V1.4 driver creates network interfaces but does **not** establish data
connections.  `quectel-CM` (Quectel QConnectManager) handles the full
connection sequence over PCIe/MHI:

1. Detect MHI device via `/sys/bus/mhi_q/devices/`
2. Open QMI channel (`/dev/mhi_QMI0`)
3. Establish PDN connection via QMI protocol
4. Configure QMAP multiplexing on `rmnet_mhi0.1`
5. Obtain IP address via `udhcpc`

**Source**: [QuectelWB/q_drivers](https://github.com/QuectelWB/q_drivers)
(`Quectel_QConnectManager_Linux_V1.6.8`)

**Pre-compiled binaries** (aarch64, stripped) are included in the overlay:

| Binary | Size | Function |
|--------|------|----------|
| `quectel-CM` | 195K | Main connection manager |
| `quectel-qmi-proxy` | 67K | QMI proxy (multi-client) |
| `quectel-mbim-proxy` | 67K | MBIM proxy |
| `quectel-atc-proxy` | 67K | AT command proxy |

Dependencies: glibc only (statically linked pthread).  No external libraries.

AT commands (via `/dev/mhi_DUN`) are used only for status/signal/registration
queries — data connection is managed entirely by `quectel-CM` via QMI.

### Runtime usage

The `rm500q-connect` CLI is installed to `/usr/local/sbin/` in the rootfs:

```bash
# Check modem status
rm500q-connect status

# Establish data connection (default APN: cmnet)
rm500q-connect connect
rm500q-connect connect internet    # custom APN

# Disconnect
rm500q-connect disconnect

# Send raw AT command
rm500q-connect at "+CEREG?"

# Check if modem is present
rm500q-connect detect
```

**Systemd auto-connect** (`rm500q-modem.service`):
- Enabled by default in `multi-user.target`
- `Type=simple` — runs `quectel-CM` in foreground (systemd tracks process)
- Waits up to 30s for `/dev/mhi_DUN` to appear (modem boot)
- Connects with APN from `RM500Q_APN` env (default: `cmnet`)
- Auto-restart on failure (`Restart=on-failure`, 5s delay)
- Logs to `/var/log/quectel-CM.log`
- Disable: `systemctl disable rm500q-modem`

**Environment overrides** (in `/etc/systemd/system/rm500q-modem.service` or shell):

| Variable | Default | Description |
|----------|---------|-------------|
| `RM500Q_AT_PORT` | `/dev/mhi_DUN` | AT command character device |
| `RM500Q_DATA_IFACE` | `rmnet_mhi0.1` | Data network interface (QMAP) |
| `RM500Q_APN` | `cmnet` | APN for data connection |
| `RM500Q_AT_TIMEOUT` | `5` | AT command timeout (seconds) |
| `RM500Q_CM_BIN` | `/usr/local/sbin/quectel-CM` | quectel-CM binary path |
| `RM500Q_CM_LOG` | `/var/log/quectel-CM.log` | quectel-CM log file |
| `RM500Q_CM_PID` | `/var/run/quectel-CM.pid` | quectel-CM PID file |

### DTS hardware configuration

PCIe controller, GPIO power/reset, and combphy PCIe mode are configured in
`rk3588-muse.dts`:

| GPIO | Function | Active |
|------|----------|--------|
| GPIO0_C6 | Modem power (FULL_CARD_POWER_OFF#) | HIGH = ON |
| GPIO0_B2 | Modem reset (4G_5G_RSTn) | HIGH = running |
| GPIO4_C1 | PCIe PERST# (controller-managed) | — |

PCIe controller `pcie2x1l2` uses `combphy0_ps` in PCIe mode.
