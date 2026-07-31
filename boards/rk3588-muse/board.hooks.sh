#!/usr/bin/env bash
# =============================================================================
# MUSE RK3588 board hooks
# =============================================================================
# Sourced by scripts/lib/common.sh after board profile is loaded.
# Hook functions run in the same shell as the build script, so all build
# variables (KERNEL_DIR, BOARD_DIR, etc.) are available.
#
# Available hooks:
#   pre_build_kernel, post_build_kernel
#   pre_build_uboot, post_build_uboot
#   pre_build_rootfs, post_build_rootfs
#   pre_make_image, post_make_image
#   pre_fetch_sources, post_fetch_sources
#
# This file implements pre_build_kernel to auto-integrate the AIC8800 USB
# WiFi/BT driver (FCU761K-L / AIC8800DC) into the kernel source tree before
# compilation.  After this hook, make build-kernel compiles the modules
# (aic_load_fw.ko, aic8800_fdrv.ko, aic_btusb.ko) as part of the normal
# kernel build — no manual steps required.
# =============================================================================

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

AIC8800_REPO_URL="https://github.com/radxa-pkg/aic8800"
AIC8800_REPO_BRANCH="main"

# Patches relevant for kernel 5.10 USB interface.
# Applied in series order (matching debian/patches/series), skipping patches
# for other kernels (6.x/7.x), interfaces (SDIO/PCIe), or platforms (Allwinner).
AIC8800_USB_PATCHES_5_10=(
    "fix-debug-file-with-no-debug-symbols.patch"
    "fix-usb-firmware-path.patch"
    "fix-usb-build.patch"
    "fix-aic_btusb-use-bluez-by-default.patch"
    "fix-Lower-the-debugging-log-level.patch"
    "fix-vmalloc-not-include.patch"
    "fix-build-on-low-memory-devices.patch"
    "fix-usb-suspend-reboot-hang.patch"
)

# ---------------------------------------------------------------------------
# Helper: log (uses build system's log_info if available)
# ---------------------------------------------------------------------------

_aic8800_log() {
    if declare -F log_info >/dev/null 2>&1; then
        log_info "$1"
    else
        echo "[aic8800] $1"
    fi
}

# ---------------------------------------------------------------------------
# Helper: clone the aic8800 repo to a temp dir and apply patches
# ---------------------------------------------------------------------------

_aic8800_fetch_and_patch() {
    local repo_dir="$1"

    _aic8800_log "Cloning ${AIC8800_REPO_URL} (branch ${AIC8800_REPO_BRANCH})"
    if ! git clone --depth 1 --branch "${AIC8800_REPO_BRANCH}" \
            "${AIC8800_REPO_URL}" "${repo_dir}" 2>/dev/null; then
        echo "ERROR: failed to clone ${AIC8800_REPO_URL}" >&2
        return 1
    fi

    # Source files in the repo have CRLF line endings; patches are LF.
    # Convert CRLF → LF so patches apply cleanly.
    find "${repo_dir}/src" -type f \( -name '*.c' -o -name '*.h' -o -name '*.mk' \
        -o -name 'Makefile' -o -name 'Kconfig' \) -exec sed -i 's/\r$//' {} +

    # Apply patches in series order.  Each patch modifies files under
    # src/USB/driver_fw/drivers/ and is designed to be applied from the
    # repo root with git am or patch -p1.
    local patch_dir="${repo_dir}/debian/patches"
    local patch applied=0 skipped=0

    for patch in "${AIC8800_USB_PATCHES_5_10[@]}"; do
        if [ ! -f "${patch_dir}/${patch}" ]; then
            _aic8800_log "WARNING: patch not found, skipping: ${patch}"
            skipped=$((skipped + 1))
            continue
        fi

        # Try git am first (preserves commit history for debugging)
        if git -C "${repo_dir}" am --quiet "${patch_dir}/${patch}" 2>/dev/null; then
            applied=$((applied + 1))
        else
            # git am failed — reset and try patch -p1
            git -C "${repo_dir}" am --abort 2>/dev/null || true
            if patch -p1 -d "${repo_dir}" --no-backup-if-mismatch \
                    < "${patch_dir}/${patch}" >/dev/null 2>&1; then
                applied=$((applied + 1))
            else
                _aic8800_log "WARNING: patch did not apply cleanly: ${patch}"
                skipped=$((skipped + 1))
            fi
        fi
    done

    _aic8800_log "Patches: ${applied} applied, ${skipped} skipped"
    return 0
}

# ---------------------------------------------------------------------------
# Helper: copy driver source into kernel tree
# ---------------------------------------------------------------------------

_aic8800_copy_driver_source() {
    local repo_dir="$1"
    local kernel_dir="$2"

    local src_wifi="${repo_dir}/src/USB/driver_fw/drivers/aic8800"
    local dst_wifi="${kernel_dir}/drivers/net/wireless/aic8800"
    local src_bt="${repo_dir}/src/USB/driver_fw/drivers/aic_btusb"
    local dst_bt="${kernel_dir}/drivers/bluetooth/aic_btusb"

    # WiFi driver: aic8800_fdrv (main WiFi) + aic_load_fw (firmware loader)
    if [ ! -d "${src_wifi}" ]; then
        echo "ERROR: WiFi driver source not found: ${src_wifi}" >&2
        return 1
    fi
    _aic8800_log "Copying WiFi driver → drivers/net/wireless/aic8800/"
    cp -a "${src_wifi}" "${dst_wifi}"

    # BT USB driver: aic_btusb
    if [ ! -d "${src_bt}" ]; then
        echo "ERROR: BT driver source not found: ${src_bt}" >&2
        return 1
    fi
    _aic8800_log "Copying BT driver → drivers/bluetooth/aic_btusb/"
    cp -a "${src_bt}" "${dst_bt}"

    return 0
}

# ---------------------------------------------------------------------------
# Helper: wire driver into kernel Makefile/Kconfig
# ---------------------------------------------------------------------------

_aic8800_wire_makefiles() {
    local kernel_dir="$1"

    local wireless_make="${kernel_dir}/drivers/net/wireless/Makefile"
    local wireless_kconfig="${kernel_dir}/drivers/net/wireless/Kconfig"
    local bt_make="${kernel_dir}/drivers/bluetooth/Makefile"

    # drivers/net/wireless/Makefile — add WiFi driver subdirectory
    if ! grep -q 'aic8800/' "${wireless_make}" 2>/dev/null; then
        printf '\n# AIC8800 USB WiFi driver (FCU761K-L / AIC8800DC)\nobj-$(CONFIG_AIC_WLAN_SUPPORT) += aic8800/\n' \
            >> "${wireless_make}"
        _aic8800_log "Wired aic8800 into drivers/net/wireless/Makefile"
    fi

    # drivers/net/wireless/Kconfig — source the driver's Kconfig
    if ! grep -q 'aic8800/Kconfig' "${wireless_kconfig}" 2>/dev/null; then
        printf '\n# AIC8800 USB WiFi driver (FCU761K-L / AIC8800DC)\nsource "drivers/net/wireless/aic8800/Kconfig"\n' \
            >> "${wireless_kconfig}"
        _aic8800_log "Wired aic8800 into drivers/net/wireless/Kconfig"
    fi

    # drivers/bluetooth/Makefile — add BT driver subdirectory
    # Use CONFIG_AIC_WLAN_SUPPORT as the gate so BT is built iff WiFi is.
    if ! grep -q 'aic_btusb/' "${bt_make}" 2>/dev/null; then
        printf '\n# AIC8800 USB BT driver (FCU761K-L / AIC8800DC)\nobj-$(CONFIG_AIC_WLAN_SUPPORT) += aic_btusb/\n' \
            >> "${bt_make}"
        _aic8800_log "Wired aic_btusb into drivers/bluetooth/Makefile"
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Hook: pre_build_kernel
# ---------------------------------------------------------------------------
# Runs after the kernel source view is prepared but before make defconfig.
# Integrates the AIC8800 USB driver into the kernel tree so that the
# subsequent make modules compiles aic_load_fw.ko, aic8800_fdrv.ko, and
# aic_btusb.ko automatically.
#
# Always re-clones and re-integrates to pick up upstream changes.
# ---------------------------------------------------------------------------

pre_build_kernel() {
    local kernel_dir="${KERNEL_DIR:?KERNEL_DIR not set}"

    # Remove stale driver dirs from previous runs
    rm -rf "${kernel_dir}/drivers/net/wireless/aic8800" \
           "${kernel_dir}/drivers/bluetooth/aic_btusb"

    _aic8800_log "Integrating AIC8800 USB WiFi/BT driver (FCU761K-L / AIC8800DC)"

    local repo_dir
    repo_dir="$(mktemp -d)"
    local rc=0

    # 1. Fetch + patch driver source
    if ! _aic8800_fetch_and_patch "${repo_dir}"; then
        rc=1
    fi

    # 2. Copy patched source into kernel tree
    if [ "${rc}" -eq 0 ] && ! _aic8800_copy_driver_source "${repo_dir}" "${kernel_dir}"; then
        rc=1
    fi

    # 3. Wire into kernel Makefile/Kconfig
    if [ "${rc}" -eq 0 ] && ! _aic8800_wire_makefiles "${kernel_dir}"; then
        rc=1
    fi

    # Cleanup temp clone
    rm -rf "${repo_dir}"

    if [ "${rc}" -eq 0 ]; then
        _aic8800_log "AIC8800 USB driver integration complete"
        _aic8800_log "Modules: aic_load_fw.ko + aic8800_fdrv.ko (WiFi), aic_btusb.ko (BT)"
    else
        echo "ERROR: AIC8800 driver integration failed" >&2
        return 1
    fi
}
