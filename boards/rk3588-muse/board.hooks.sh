#!/usr/bin/env bash
# =============================================================================
# MUSE RK3588 board hooks
# =============================================================================
# Sourced by scripts/lib/common.sh after board profile is loaded.
# Hook functions run in the same shell as the build script, so all build
# variables (KERNEL_DIR, BOARD_DIR, PROJECT_DIR, etc.) are available.
#
# Available hooks:
#   pre_build_kernel, post_build_kernel
#   pre_build_uboot, post_build_uboot
#   pre_build_rootfs, post_build_rootfs
#   pre_make_image, post_make_image
#   pre_fetch_sources, post_fetch_sources
#
# AIC8800 USB WiFi/BT driver (FCU761K-L / AIC8800DC) is integrated directly
# into the MUSE kernel fork (MUSEInstitute/kernel, develop-5.10 branch).
# No pre_build_kernel hook is needed for AIC8800 — the driver source,
# Makefile, and Kconfig wiring are committed to the kernel repo and pulled
# in by make fetch.
#
# RM500Q-GL 5G modem (Quectel, PCIe/MHI on pcie2x1l2) uses the Quectel
# PCIe MHI Driver V1.4 (2025-08-08), a self-contained out-of-tree driver
# package that produces a single pcie_mhi.ko module.  It includes its own
# MHI bus core, PCI controller, UCI channel, and network driver — it does
# NOT depend on the mainline MHI bus (drivers/bus/mhi/).
#
# Integration is handled by pre_build_kernel below:
#   1. Copy driver source → drivers/pcie_mhi/
#   2. Wire into drivers/Makefile (obj-y += pcie_mhi/)
#   3. Disable mainline MHI pci_generic 0x0306 entry to prevent conflict
# =============================================================================

# -----------------------------------------------------------------------------
# pre_build_kernel: integrate Quectel PCIe MHI Driver V1.4 into kernel tree
# -----------------------------------------------------------------------------
# Runs BEFORE make defconfig + merge_config.sh.  Idempotent — safe for
# repeated builds.
#
# Driver source resolution (first match wins):
#   1. PCIE_MHI_DRIVER_DIR  — local directory (e.g. /path/to/quectel-pcie-mhi)
#   2. PCIE_MHI_DRIVER_URL  — git URL to shallow-clone
#   3. PCIE_MHI_DRIVER_TAR  — local tarball (.tar.gz / .tar.xz / .tar.zst)
#   4. Skip with warning (modem won't work, but build succeeds)
#
# Expected V1.4 driver package layout (self-contained):
#   <src>/
#   ├── Makefile              # top-level Kbuild Makefile (produces pcie_mhi.ko)
#   ├── core/                 # MHI bus core (self-contained, not mainline)
#   ├── controllers/          # PCI controller (mhi_qcom.c) + firmware paths
#   └── devices/              # UCI channel (mhi_uci.c) + net driver (mhi_netdev_quectel.c)
#
# After integration the kernel tree has:
#   drivers/pcie_mhi/         ← full driver tree
#   drivers/Makefile          ← obj-y += pcie_mhi/  appended
#
# PCI Device ID 0x17cb:0x0306 (SDX55 = RM500Q-GL) is built into the driver.
# The mainline MHI pci_generic.c also matches 0x0306, so we must disable
# that entry to prevent both drivers from claiming the device.
# -----------------------------------------------------------------------------
pre_build_kernel() {
    local mhi_pci_generic="${KERNEL_DIR}/drivers/bus/mhi/host/pci_generic.c"
    local pcie_mhi_dst="${KERNEL_DIR}/drivers/pcie_mhi"
    local drivers_makefile="${KERNEL_DIR}/drivers/Makefile"

    # ---- Step 1: Resolve driver source -------------------------------------
    local mhi_src=""
    local cleanup_src=""

    if [ -n "${PCIE_MHI_DRIVER_DIR:-}" ] && [ -d "${PCIE_MHI_DRIVER_DIR}" ]; then
        mhi_src="${PCIE_MHI_DRIVER_DIR}"
        log_info "[pcie_mhi] Using local driver source: ${mhi_src}"
    elif [ -n "${PCIE_MHI_DRIVER_TAR:-}" ] && [ -f "${PCIE_MHI_DRIVER_TAR}" ]; then
        mhi_src="$(mktemp -d)"
        cleanup_src="${mhi_src}"
        log_info "[pcie_mhi] Extracting driver tarball: ${PCIE_MHI_DRIVER_TAR}"
        case "${PCIE_MHI_DRIVER_TAR}" in
            *.tar.gz|*.tgz)   tar -xzf "${PCIE_MHI_DRIVER_TAR}" -C "${mhi_src}" ;;
            *.tar.xz|*.txz)   tar -xJf "${PCIE_MHI_DRIVER_TAR}" -C "${mhi_src}" ;;
            *.tar.zst)        tar --zstd -xf "${PCIE_MHI_DRIVER_TAR}" -C "${mhi_src}" ;;
            *.tar)            tar -xf "${PCIE_MHI_DRIVER_TAR}" -C "${mhi_src}" ;;
            *) die "[pcie_mhi] Unsupported tarball format: ${PCIE_MHI_DRIVER_TAR}" ;;
        esac
        # Handle tarball with top-level wrapper directory
        local subdirs=("${mhi_src}"/*)
        if [ "${#subdirs[@]}" -eq 1 ] && [ -d "${subdirs[0]}" ] \
           && [ -f "${subdirs[0]}/Makefile" ]; then
            mhi_src="${subdirs[0]}"
        fi
    elif [ -n "${PCIE_MHI_DRIVER_URL:-}" ]; then
        mhi_src="$(mktemp -d)"
        cleanup_src="${mhi_src}"
        log_info "[pcie_mhi] Cloning driver from: ${PCIE_MHI_DRIVER_URL}"
        git clone --depth 1 "${PCIE_MHI_DRIVER_URL}" "${mhi_src}" \
            || die "[pcie_mhi] Failed to clone: ${PCIE_MHI_DRIVER_URL}"
    elif [ -d "${BOARD_DIR}/pcie-mhi-driver" ] \
         && [ -f "${BOARD_DIR}/pcie-mhi-driver/Makefile" ]; then
        mhi_src="${BOARD_DIR}/pcie-mhi-driver"
        log_info "[pcie_mhi] Using board-local driver source: ${mhi_src}"
    else
        log_warn "[pcie_mhi] No driver source (set PCIE_MHI_DRIVER_DIR / _URL / _TAR)"
        log_warn "[pcie_mhi] Or place driver in: boards/rk3588-muse/pcie-mhi-driver/"
        log_warn "[pcie_mhi] Build will succeed but modem won't have PCIe/MHI driver"
        log_warn "[pcie_mhi] Get V1.4 driver from Quectel FAE or MUSEInstitute/Quectel_Linux_PCIE_MHI_Driver"
        return 0
    fi

    # ---- Step 2: Validate driver structure ---------------------------------
    if [ ! -f "${mhi_src}/Makefile" ]; then
        die "[pcie_mhi] No Makefile found in driver source: ${mhi_src}"
    fi
    if [ ! -d "${mhi_src}/core" ] || [ ! -d "${mhi_src}/controllers" ] \
       || [ ! -d "${mhi_src}/devices" ]; then
        die "[pcie_mhi] Expected layout core/ + controllers/ + devices/ not found in: ${mhi_src}"
    fi
    log_info "[pcie_mhi] Driver structure validated (core/ + controllers/ + devices/)"

    # ---- Step 3: Copy driver into kernel tree ------------------------------
    log_info "[pcie_mhi] Integrating driver → drivers/pcie_mhi/"
    rm -rf "${pcie_mhi_dst}"
    mkdir -p "${pcie_mhi_dst}"
    cp -r "${mhi_src}/"* "${pcie_mhi_dst}/"

    # ---- Step 4: Wire into drivers/Makefile --------------------------------
    # Use obj-y (unconditionally built) — the V1.4 driver is self-contained
    # and does not use Kconfig gating.
    if ! grep -q 'pcie_mhi' "${drivers_makefile}" 2>/dev/null; then
        log_info "[pcie_mhi] Wiring into drivers/Makefile"
        # Append near the end, before any trailing blank lines
        echo 'obj-y += pcie_mhi/' >> "${drivers_makefile}"
    else
        log_info "[pcie_mhi] Already wired in drivers/Makefile"
    fi

    # ---- Step 5: Disable mainline MHI pci_generic 0x0306 conflict ----------
    # The V1.4 driver has 0x17cb:0x0306 built in.  The mainline
    # pci_generic.c also has this ID, so both drivers would try to claim
    # the device.  We comment out the 0x0306 entry in pci_generic.c to
    # prevent the conflict.
    if [ -f "${mhi_pci_generic}" ]; then
        if grep -q '0x0306' "${mhi_pci_generic}" 2>/dev/null; then
            # Check if already disabled by us (look for our marker)
            if grep -q 'pcie_mhi.*0x0306\|0x0306.*pcie_mhi' "${mhi_pci_generic}" 2>/dev/null; then
                log_info "[pcie_mhi] Mainline 0x0306 already disabled, skipping"
            else
                log_info "[pcie_mhi] Disabling mainline MHI pci_generic 0x0306 (conflict with V1.4 driver)"
                # Comment out the PCI_DEVICE(0x17cb, 0x0306) line.
                # The line typically looks like:
                #   { PCI_DEVICE(0x17cb, 0x0306) },
                # or in some versions:
                #   { .vendor = 0x17cb, .device = 0x0306, ... },
                # Use sed to comment out any line containing 0x0306 in mhi_pci_id_table.
                # We add a marker comment so we can detect idempotency.
                sed -i '/0x0306/s/^/\/\* pcie_mhi: disabled by board.hooks.sh *\//' "${mhi_pci_generic}"
            fi
        else
            log_info "[pcie_mhi] Mainline pci_generic.c has no 0x0306 entry, no conflict"
        fi
    else
        log_warn "[pcie_mhi] Mainline pci_generic.c not found: ${mhi_pci_generic}"
        log_warn "[pcie_mhi] (kernel may not have MHI bus — that's fine, V1.4 is self-contained)"
    fi

    # ---- Cleanup -----------------------------------------------------------
    if [ -n "${cleanup_src}" ]; then
        rm -rf "${cleanup_src}"
    fi

    log_info "[pcie_mhi] Driver integration complete (pcie_mhi.ko will be built)"
}
