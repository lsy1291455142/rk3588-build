#!/usr/bin/env bash
# WiFi/BT firmware helpers for the optional wifibt overlay.
# Not part of the pure build core; sourced only by this overlay (and its tests).
# Requires scripts/lib/common.sh already sourced (die/log_*/PROJECT_DIR/SDK_DIR).

# WiFi/BT firmware install for Debian rootfs.
# Board profile / env:
#   WIFIBT_CHIP      none|ALL_AP|ALL_CY|ALL|<chip e.g. AP6275S|AIC8800D80>
#   WIFIBT_SOURCE    sdk-or-assets|sdk|assets  (default sdk-or-assets)
#   WIFIBT_REQUIRED  yes|no  (default no; yes fails build when firmware missing)
# AIC modules keep a subdirectory under /lib/firmware (e.g. aic8800D80/).
resolve_wifibt_config() {
    local chip source required

    chip="${WIFIBT_CHIP:-none}"
    chip="${chip//[[:space:]]/}"
    case "${chip}" in
        ''|none|off|-)
            chip="none"
            ;;
        *)
            chip="$(printf '%s' "${chip}" | tr '[:lower:]' '[:upper:]')"
            ;;
    esac

    # Normalize common AIC aliases to the canonical board token.
    case "${chip}" in
        AIC8800D80|AIC_8800D80|AIC-8800D80)
            chip="AIC8800D80"
            ;;
        AIC8800DC|AIC_8800DC|AIC-8800DC)
            chip="AIC8800DC"
            ;;
        AIC8800D80N|AIC_8800D80N)
            chip="AIC8800D80N"
            ;;
        AIC8800D80X2|AIC_8800D80X2)
            chip="AIC8800D80X2"
            ;;
        AIC8800|AIC_8800|AIC-8800)
            chip="AIC8800"
            ;;
    esac

    source="${WIFIBT_SOURCE:-sdk-or-assets}"
    source="${source//[[:space:]]/}"
    source="$(printf '%s' "${source}" | tr '[:upper:]' '[:lower:]')"
    case "${source}" in
        sdk-or-assets|sdk|assets) ;;
        *)
            die "Unsupported WIFIBT_SOURCE=${WIFIBT_SOURCE}; expected sdk-or-assets, sdk, or assets"
            ;;
    esac

    required="${WIFIBT_REQUIRED:-no}"
    required="${required//[[:space:]]/}"
    required="$(printf '%s' "${required}" | tr '[:upper:]' '[:lower:]')"
    case "${required}" in
        yes|true|1|on) required="yes" ;;
        no|false|0|off|-) required="no" ;;
        *)
            die "Unsupported WIFIBT_REQUIRED=${WIFIBT_REQUIRED}; expected yes or no"
            ;;
    esac

    WIFIBT_CHIP="${chip}"
    WIFIBT_SOURCE="${source}"
    WIFIBT_REQUIRED="${required}"
    WIFIBT_FIRMWARE_SYMLINKS="${WIFIBT_FIRMWARE_SYMLINKS:-rockchip-vendor}"
    WIFIBT_RESOLVED_SOURCE=""
    WIFIBT_RESOLVED_DIR=""
    WIFIBT_FILE_COUNT=0
}

# Directory containing this library (overlays/wifibt).
wifibt_overlay_dir() {
    local here
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    printf '%s\n' "${here}"
}

# Overlay-owned firmware tree (preferred), plus legacy project assets/wifibt.
wifibt_assets_dirs() {
    local o
    o="$(wifibt_overlay_dir)"
    printf '%s\n' "${o}/firmware"
    # Legacy path kept for existing checkouts that still store blobs under assets/.
    printf '%s\n' "${PROJECT_DIR}/assets/wifibt"
}

wifibt_firmware_roots() {
    local source="${WIFIBT_SOURCE:-sdk-or-assets}"
    local sdk_fw="${SDK_DIR}/external/rkwifibt/firmware"
    local d

    case "${source}" in
        sdk)
            printf '%s\n' "${sdk_fw}"
            ;;
        assets)
            wifibt_assets_dirs
            ;;
        *)
            printf '%s\n' "${sdk_fw}"
            wifibt_assets_dirs
            ;;
    esac
}

wifibt_chip_vendor() {
    local chip="$1"
    case "${chip}" in
        AP*|BCM*) printf 'broadcom\n' ;;
        RTL*) printf 'realtek\n' ;;
        CYW*) printf 'infineon\n' ;;
        RK*) printf 'rockchip\n' ;;
        AIC*) printf 'aicsemi\n' ;;
        *) return 1 ;;
    esac
}

# Rockchip AIC driver appends chip dir under CONFIG_AIC_FW_PATH
# (default /vendor/etc/firmware -> .../aic8800D80/...).
wifibt_aic_fw_subdir() {
    local chip="$1"
    case "${chip}" in
        AIC8800D80) printf 'aic8800D80\n' ;;
        AIC8800DC) printf 'aic8800DC\n' ;;
        AIC8800D80N) printf 'aic8800D80N\n' ;;
        AIC8800D80X2) printf 'aic8800D80X2\n' ;;
        AIC8800) printf 'aic8800\n' ;;
        *) return 1 ;;
    esac
}

wifibt_is_aic_chip() {
    case "${1:-}" in
        AIC*) return 0 ;;
        *) return 1 ;;
    esac
}

# Print candidate chip directories under a firmware root (absolute paths).
wifibt_chip_dirs_for_root() {
    local root="$1"
    local chip="${WIFIBT_CHIP}"
    local vendor chip_dir subdir cand

    [ -d "${root}" ] || return 1

    case "${chip}" in
        none)
            return 1
            ;;
        ALL)
            find "${root}" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | sort
            ;;
        ALL_AP)
            [ -d "${root}/broadcom" ] || return 1
            find "${root}/broadcom" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort
            ;;
        ALL_CY)
            [ -d "${root}/infineon" ] || return 1
            find "${root}/infineon" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort
            ;;
        *)
            vendor="$(wifibt_chip_vendor "${chip}" || true)"
            [ -n "${vendor}" ] || return 1
            if wifibt_is_aic_chip "${chip}"; then
                subdir="$(wifibt_aic_fw_subdir "${chip}" || true)"
                for cand in \
                    "${root}/${vendor}/${chip}" \
                    "${root}/${vendor}/${subdir}" \
                    "${root}/${subdir}" \
                    "${root}/aic8800_fw/SDIO/${subdir}" \
                    "${root}/SDIO/${subdir}"
                do
                    if [ -n "${cand}" ] && [ -d "${cand}" ]; then
                        printf '%s\n' "${cand}"
                        return 0
                    fi
                done
                return 1
            fi
            chip_dir="${root}/${vendor}/${chip}"
            [ -d "${chip_dir}" ] || return 1
            printf '%s\n' "${chip_dir}"
            ;;
    esac
}

wifibt_copy_chip_dir() {
    local chip_dir="$1"
    local dest_fw="$2"
    local f dest_dir subdir
    local copied=0

    # AIC: keep subdirectory so driver path
    #   /vendor/etc/firmware/aic8800D80/<file>
    # resolves via /vendor -> /system and /system/etc/firmware -> /lib/firmware.
    if wifibt_is_aic_chip "${WIFIBT_CHIP}"; then
        subdir="$(wifibt_aic_fw_subdir "${WIFIBT_CHIP}")" || return 1
        dest_dir="${dest_fw}/${subdir}"
        install -d "${dest_dir}"
        while IFS= read -r -d '' f; do
            case "$(basename "${f}")" in
                SOURCE.txt|README*|*.7z|*.md) continue ;;
            esac
            install -m 0644 "${f}" "${dest_dir}/"
            copied=1
        done < <(find "${chip_dir}" -maxdepth 1 -type f -print0 2>/dev/null)
        [ "${copied}" = "1" ]
        return $?
    fi

    if [ -d "${chip_dir}/wifi" ] || [ -d "${chip_dir}/bt" ]; then
        if [ -d "${chip_dir}/wifi" ]; then
            while IFS= read -r -d '' f; do
                install -m 0644 "${f}" "${dest_fw}/"
                copied=1
            done < <(find "${chip_dir}/wifi" -type f -print0 2>/dev/null)
        fi
        if [ -d "${chip_dir}/bt" ]; then
            while IFS= read -r -d '' f; do
                install -m 0644 "${f}" "${dest_fw}/"
                copied=1
            done < <(find "${chip_dir}/bt" -type f -print0 2>/dev/null)
        fi
    else
        # Infineon/Realtek flat layout: files directly under chip dir.
        while IFS= read -r -d '' f; do
            install -m 0644 "${f}" "${dest_fw}/"
            copied=1
        done < <(find "${chip_dir}" -maxdepth 1 -type f -print0 2>/dev/null)
    fi
    [ "${copied}" = "1" ]
}

# Install firmware into a rootfs tree. Sets WIFIBT_RESOLVED_* metadata.
install_wifibt_firmware() {
    local root_dir="${1:-}"
    local dest_fw chip_dirs_file root chip_dir count primary_fw primary_nvram msg

    [ -n "${root_dir}" ] || die "install_wifibt_firmware: root_dir required"
    resolve_wifibt_config

    # Firmware is driven by WIFIBT_CHIP (board/env), not package tokens.
    if [ "${WIFIBT_CHIP}" = "none" ]; then
        if [ "${WIFIBT_REQUIRED}" = "yes" ]; then
            die "WIFIBT_REQUIRED=yes but WIFIBT_CHIP is none/empty"
        fi
        WIFIBT_RESOLVED_SOURCE="skipped"
        return 0
    fi

    chip_dirs_file="$(mktemp)"
    : >"${chip_dirs_file}"
    for root in $(wifibt_firmware_roots); do
        wifibt_chip_dirs_for_root "${root}" >>"${chip_dirs_file}" || true
        if [ -s "${chip_dirs_file}" ]; then
            WIFIBT_RESOLVED_DIR="${root}"
            case "${root}" in
                "${SDK_DIR}/external/rkwifibt/firmware")
                    WIFIBT_RESOLVED_SOURCE="sdk"
                    ;;
                */overlays/wifibt/firmware|"${PROJECT_DIR}/assets/wifibt")
                    WIFIBT_RESOLVED_SOURCE="assets"
                    ;;
                *)
                    WIFIBT_RESOLVED_SOURCE="${root}"
                    ;;
            esac
            break
        fi
    done

    if [ ! -s "${chip_dirs_file}" ]; then
        rm -f "${chip_dirs_file}"
        msg="WiFi/BT firmware not found for WIFIBT_CHIP=${WIFIBT_CHIP} (source=${WIFIBT_SOURCE})"
        if [ "${WIFIBT_REQUIRED}" = "yes" ]; then
            die "${msg}"
        fi
        log_warn "${msg}"
        log_warn "Searched: $(wifibt_firmware_roots | tr '\n' ' ')"
        log_warn "Import full BSP external/rkwifibt or run: rootfs/debian/overlays/wifibt/sync-assets.sh"
        WIFIBT_RESOLVED_SOURCE="missing"
        return 0
    fi

    dest_fw="${root_dir}/lib/firmware"
    install -d "${dest_fw}"
    if [ "${WIFIBT_FIRMWARE_SYMLINKS:-rockchip-vendor}" = "rockchip-vendor" ]; then
        install -d "${root_dir}/system/etc"
    fi

    while IFS= read -r chip_dir; do
        [ -n "${chip_dir}" ] || continue
        log_info "Installing WiFi/BT firmware from ${chip_dir}"
        wifibt_copy_chip_dir "${chip_dir}" "${dest_fw}" || true
    done <"${chip_dirs_file}"
    rm -f "${chip_dirs_file}"

    # Count all installed firmware files (AIC lives in a subdirectory).
    count="$(find "${dest_fw}" -type f \
        ! -name 'SOURCE.txt' ! -name 'README*' ! -name '*.md' \
        2>/dev/null | wc -l | tr -d ' ')"
    WIFIBT_FILE_COUNT="${count}"
    if [ "${count}" = "0" ]; then
        msg="WiFi/BT firmware directories were empty for WIFIBT_CHIP=${WIFIBT_CHIP}"
        if [ "${WIFIBT_REQUIRED}" = "yes" ]; then
            die "${msg}. Place blobs under rootfs/debian/overlays/wifibt/firmware/ or run overlays/wifibt/sync-assets.sh"
        fi
        log_warn "${msg}"
        log_warn "Found chip dir but no firmware files (SOURCE.txt alone does not count)."
        log_warn "Populate overlays/wifibt/firmware/aicsemi/${WIFIBT_CHIP}/ or run overlays/wifibt/sync-assets.sh"
        WIFIBT_RESOLVED_SOURCE="empty"
        return 0
    fi

    # Rockchip bcmdhd / AIC drivers look under /vendor/etc/firmware.
    # Controlled by WIFIBT_FIRMWARE_SYMLINKS in board profile.
    case "${WIFIBT_FIRMWARE_SYMLINKS:-rockchip-vendor}" in
        rockchip-vendor)
            ln -sfn /lib/firmware "${root_dir}/system/etc/firmware"
            ln -sfn /system "${root_dir}/vendor"
            ;;
        none)
            log_info "WIFIBT_FIRMWARE_SYMLINKS=none; skipping vendor symlinks"
            ;;
        *)
            die "Unsupported WIFIBT_FIRMWARE_SYMLINKS=${WIFIBT_FIRMWARE_SYMLINKS}"
            ;;
    esac

    # Compatibility names used by CONFIG_BCMDHD_*_PATH defaults.
    primary_fw="$(find "${dest_fw}" -maxdepth 1 -type f -name 'fw_bcm*.bin' ! -name '*_mfg*' ! -name '*_apsta*' 2>/dev/null | sort | head -n 1 || true)"
    primary_nvram="$(find "${dest_fw}" -maxdepth 1 -type f -name 'nvram_*.txt' 2>/dev/null | sort | head -n 1 || true)"
    if [ -n "${primary_fw}" ] && [ ! -e "${dest_fw}/fw_bcmdhd.bin" ]; then
        ln -sfn "$(basename "${primary_fw}")" "${dest_fw}/fw_bcmdhd.bin"
    fi
    if [ -n "${primary_nvram}" ] && [ ! -e "${dest_fw}/nvram.txt" ]; then
        ln -sfn "$(basename "${primary_nvram}")" "${dest_fw}/nvram.txt"
    fi

    log_info "WiFi/BT firmware installed: chip=${WIFIBT_CHIP} source=${WIFIBT_RESOLVED_SOURCE} files=${count}"
}

