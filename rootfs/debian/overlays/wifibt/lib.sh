#!/usr/bin/env bash
# Thin WiFi/BT firmware installer for the optional wifibt overlay.
# Not part of the pure build core.
#
# Model: take a firmware package (deb / static files) → install into rootfs
# → apply driver path remaps. No BSP feature-token machinery.
#
# Env (board conf / CLI):
#   WIFIBT_CHIP      none | AIC8800D80 | AP6275S | <chip name>
#   WIFIBT_DEB       optional local path or URL to a .deb (firmware package)
#   WIFIBT_REQUIRED  yes|no  (default no)
#   WIFIBT_FIRMWARE_SYMLINKS  rockchip-vendor|none  (default rockchip-vendor)
#   WIFIBT_SOURCE    optional hint: auto|package|firmware|sdk  (default auto)
#                    legacy values sdk|assets|sdk-or-assets still accepted
#
# Search order when source=auto:
#   1) WIFIBT_DEB / packages/*.deb
#   2) firmware/ tree (overlay) and legacy assets/wifibt
#   3) SDK external/rkwifibt/firmware (optional blob source only)

resolve_wifibt_config() {
    local chip source required

    chip="${WIFIBT_CHIP:-none}"
    chip="${chip//[[:space:]]/}"
    case "${chip}" in
        ''|none|off|-) chip="none" ;;
        *) chip="$(printf '%s' "${chip}" | tr '[:lower:]' '[:upper:]')" ;;
    esac

    case "${chip}" in
        AIC8800D80|AIC_8800D80|AIC-8800D80) chip="AIC8800D80" ;;
        AIC8800DC|AIC_8800DC|AIC-8800DC) chip="AIC8800DC" ;;
        AIC8800D80N|AIC_8800D80N) chip="AIC8800D80N" ;;
        AIC8800D80X2|AIC_8800D80X2) chip="AIC8800D80X2" ;;
        AIC8800|AIC_8800|AIC-8800) chip="AIC8800" ;;
    esac

    source="${WIFIBT_SOURCE:-auto}"
    source="${source//[[:space:]]/}"
    source="$(printf '%s' "${source}" | tr '[:upper:]' '[:lower:]')"
    case "${source}" in
        auto|package|firmware|sdk) ;;
        sdk-or-assets|assets) source="auto" ;;
        *)
            die "Unsupported WIFIBT_SOURCE=${WIFIBT_SOURCE}; expected auto, package, firmware, or sdk"
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

wifibt_overlay_dir() {
    local self
    self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    printf '%s\n' "${self}"
}

wifibt_is_blob() {
    local f="$1" base
    base="$(basename "${f}")"
    case "${base}" in
        SOURCE.txt|README|README.*|*.md|.gitkeep) return 1 ;;
        *) return 0 ;;
    esac
}

wifibt_count_files() {
    local dir="$1"
    local n=0 f
    [ -d "${dir}" ] || { printf '0\n'; return 0; }
    while IFS= read -r f; do
        wifibt_is_blob "${f}" || continue
        n=$((n + 1))
    done < <(find "${dir}" -type f 2>/dev/null)
    printf '%s\n' "${n}"
}

wifibt_has_blobs() {
    local dir="$1"
    [ -d "${dir}" ] || return 1
    [ "$(wifibt_count_files "${dir}")" -gt 0 ]
}

# Known install target under /lib/firmware for Rockchip vendor drivers.
wifibt_dest_subdir() {
    case "${WIFIBT_CHIP}" in
        AIC8800D80) printf 'aic8800D80\n' ;;
        AIC8800DC) printf 'aic8800DC\n' ;;
        AIC8800D80N) printf 'aic8800D80N\n' ;;
        AIC8800D80X2) printf 'aic8800D80X2\n' ;;
        AIC8800) printf 'aic8800\n' ;;
        *) printf '\n' ;;
    esac
}

wifibt_is_aic() {
    case "${1:-${WIFIBT_CHIP}}" in
        AIC*) return 0 ;;
        *) return 1 ;;
    esac
}

# Candidate static trees for the selected chip (absolute paths).
wifibt_static_chip_dirs() {
    local o chip sub
    o="$(wifibt_overlay_dir)"
    chip="${WIFIBT_CHIP}"
    sub="$(wifibt_dest_subdir || true)"

    # Preferred flat layout: firmware/<CHIP>/
    printf '%s\n' "${o}/firmware/${chip}"
    # Legacy vendor layout kept for older checkouts.
    if wifibt_is_aic "${chip}"; then
        printf '%s\n' "${o}/firmware/aicsemi/${chip}"
        [ -n "${sub}" ] && printf '%s\n' "${o}/firmware/aicsemi/${sub}"
        [ -n "${sub}" ] && printf '%s\n' "${o}/firmware/${sub}"
        printf '%s\n' "${PROJECT_DIR}/assets/wifibt/aicsemi/${chip}"
        [ -n "${sub}" ] && printf '%s\n' "${PROJECT_DIR}/assets/wifibt/aicsemi/${sub}"
    else
        case "${chip}" in
            AP*|BCM*)
                printf '%s\n' "${o}/firmware/broadcom/${chip}"
                printf '%s\n' "${PROJECT_DIR}/assets/wifibt/broadcom/${chip}"
                ;;
            RTL*)
                printf '%s\n' "${o}/firmware/realtek/${chip}"
                printf '%s\n' "${PROJECT_DIR}/assets/wifibt/realtek/${chip}"
                ;;
            CYW*)
                printf '%s\n' "${o}/firmware/infineon/${chip}"
                printf '%s\n' "${PROJECT_DIR}/assets/wifibt/infineon/${chip}"
                ;;
            RK*)
                printf '%s\n' "${o}/firmware/rockchip/${chip}"
                printf '%s\n' "${PROJECT_DIR}/assets/wifibt/rockchip/${chip}"
                ;;
        esac
        printf '%s\n' "${PROJECT_DIR}/assets/wifibt/${chip}"
    fi
}

wifibt_sdk_chip_dirs() {
    local sdk_fw="${SDK_DIR:-}/external/rkwifibt/firmware"
    local chip="${WIFIBT_CHIP}"
    local sub vendor

    [ -d "${sdk_fw}" ] || return 1

    if wifibt_is_aic "${chip}"; then
        sub="$(wifibt_dest_subdir)"
        for cand in \
            "${sdk_fw}/aicsemi/${chip}" \
            "${sdk_fw}/aicsemi/${sub}" \
            "${sdk_fw}/${sub}" \
            "${sdk_fw}/aic8800_fw/SDIO/${sub}" \
            "${sdk_fw}/SDIO/${sub}"
        do
            [ -d "${cand}" ] && printf '%s\n' "${cand}"
        done
        return 0
    fi

    case "${chip}" in
        AP*|BCM*) vendor=broadcom ;;
        RTL*) vendor=realtek ;;
        CYW*) vendor=infineon ;;
        RK*) vendor=rockchip ;;
        *) return 1 ;;
    esac
    [ -d "${sdk_fw}/${vendor}/${chip}" ] && printf '%s\n' "${sdk_fw}/${vendor}/${chip}"
}

# Copy blob tree into dest, flattening one wifi/bt nesting if present.
wifibt_copy_blobs() {
    local src="$1"
    local dest="$2"
    local f rel

    install -d "${dest}"
    if [ -d "${src}/wifi" ] || [ -d "${src}/bt" ]; then
        [ -d "${src}/wifi" ] && cp -a "${src}/wifi"/. "${dest}"/
        [ -d "${src}/bt" ] && cp -a "${src}/bt"/. "${dest}"/
    else
        # Skip nested documentation-only files; copy real blobs.
        while IFS= read -r f; do
            wifibt_is_blob "${f}" || continue
            rel="${f#"${src}"/}"
            install -d "${dest}/$(dirname "${rel}")"
            cp -a "${f}" "${dest}/${rel}"
        done < <(find "${src}" -type f 2>/dev/null)
    fi
}

wifibt_apply_vendor_symlinks() {
    local root_dir="$1"
    local dest_fw="${root_dir}/lib/firmware"

    case "${WIFIBT_FIRMWARE_SYMLINKS:-rockchip-vendor}" in
        rockchip-vendor)
            install -d "${root_dir}/system/etc"
            ln -sfn /system "${root_dir}/vendor"
            ln -sfn /lib/firmware "${root_dir}/system/etc/firmware"
            ;;
        none)
            log_info "WIFIBT_FIRMWARE_SYMLINKS=none; skipping vendor symlinks"
            ;;
        *)
            die "Unsupported WIFIBT_FIRMWARE_SYMLINKS=${WIFIBT_FIRMWARE_SYMLINKS}"
            ;;
    esac

    # Rockchip bcmdhd often wants fixed names.
    if [ -d "${dest_fw}" ]; then
        local primary_fw
        primary_fw="$(find "${dest_fw}" -maxdepth 1 -type f \( -name 'fw_bcm*.bin' -o -name 'fw_bcmdhd*.bin' \) 2>/dev/null | sort | head -n 1 || true)"
        if [ -n "${primary_fw}" ] && [ ! -e "${dest_fw}/fw_bcmdhd.bin" ]; then
            ln -sfn "$(basename "${primary_fw}")" "${dest_fw}/fw_bcmdhd.bin"
        fi
        if [ -f "${dest_fw}/nvram_ap6275s.txt" ] && [ ! -e "${dest_fw}/nvram.txt" ]; then
            ln -sfn nvram_ap6275s.txt "${dest_fw}/nvram.txt"
        fi
    fi
}

# Extract a firmware .deb and map files into rootfs for the selected chip.
wifibt_install_from_deb() {
    local root_dir="$1"
    local deb="$2"
    local work extract dest_fw sub src_dir

    [ -f "${deb}" ] || return 1
    work="$(mktemp -d)"
    extract="${work}/root"
    mkdir -p "${extract}"

    if command -v dpkg-deb >/dev/null 2>&1; then
        dpkg-deb -x "${deb}" "${extract}"
    else
        # Fallback without dpkg: ar + tar
        (
            cd "${work}"
            ar x "${deb}"
            if [ -f data.tar.xz ]; then tar -C "${extract}" -xJf data.tar.xz
            elif [ -f data.tar.gz ]; then tar -C "${extract}" -xzf data.tar.gz
            elif [ -f data.tar.zst ]; then tar -C "${extract}" --zstd -xf data.tar.zst
            else die "Cannot extract ${deb}: missing dpkg-deb and unknown data.tar.*"
            fi
        )
    fi

    dest_fw="${root_dir}/lib/firmware"
    install -d "${dest_fw}"
    sub="$(wifibt_dest_subdir)"

    if wifibt_is_aic && [ -n "${sub}" ]; then
        # Radxa aic8800-firmware layout → Rockchip CONFIG_AIC_FW_PATH layout.
        for src_dir in \
            "${extract}/lib/firmware/aic8800_fw/SDIO/${sub}" \
            "${extract}/lib/firmware/aic8800_fw/PCIE/${sub}" \
            "${extract}/lib/firmware/${sub}" \
            "${extract}/lib/firmware/aic8800_fw/${sub}"
        do
            if wifibt_has_blobs "${src_dir}"; then
                wifibt_copy_blobs "${src_dir}" "${dest_fw}/${sub}"
                WIFIBT_RESOLVED_SOURCE="package"
                WIFIBT_RESOLVED_DIR="${deb}"
                WIFIBT_FILE_COUNT="$(wifibt_count_files "${dest_fw}/${sub}")"
                rm -rf "${work}"
                return 0
            fi
        done
        rm -rf "${work}"
        return 1
    fi

    # Generic: take package /lib/firmware payload as-is (plus optional chip subdir).
    if [ -d "${extract}/lib/firmware" ] && wifibt_has_blobs "${extract}/lib/firmware"; then
        cp -a "${extract}/lib/firmware"/. "${dest_fw}"/
        WIFIBT_RESOLVED_SOURCE="package"
        WIFIBT_RESOLVED_DIR="${deb}"
        WIFIBT_FILE_COUNT="$(wifibt_count_files "${dest_fw}")"
        rm -rf "${work}"
        return 0
    fi

    rm -rf "${work}"
    return 1
}

wifibt_resolve_deb() {
    local o deb
    o="$(wifibt_overlay_dir)"

    if [ -n "${WIFIBT_DEB:-}" ]; then
        deb="${WIFIBT_DEB}"
        if [[ "${deb}" =~ ^https?:// ]]; then
            local cache="${o}/packages/.cache"
            local name
            name="$(basename "${deb%%\?*}")"
            [ -n "${name}" ] || name="wifibt-firmware.deb"
            install -d "${cache}"
            if [ ! -f "${cache}/${name}" ]; then
                log_info "Downloading WiFi/BT package: ${deb}"
                if command -v curl >/dev/null 2>&1; then
                    curl -fsSL -o "${cache}/${name}.partial" "${deb}"
                elif command -v wget >/dev/null 2>&1; then
                    wget -q -O "${cache}/${name}.partial" "${deb}"
                else
                    die "Need curl or wget to fetch WIFIBT_DEB=${deb}"
                fi
                mv "${cache}/${name}.partial" "${cache}/${name}"
            fi
            printf '%s\n' "${cache}/${name}"
            return 0
        fi
        [ -f "${deb}" ] || die "WIFIBT_DEB not found: ${deb}"
        printf '%s\n' "${deb}"
        return 0
    fi

    # Local packages/ directory: prefer names matching chip / aic8800-firmware.
    if [ -d "${o}/packages" ]; then
        local match=""
        if wifibt_is_aic; then
            match="$(find "${o}/packages" -maxdepth 1 -type f -name 'aic8800-firmware*.deb' 2>/dev/null | sort | tail -n 1 || true)"
        fi
        if [ -z "${match}" ]; then
            match="$(find "${o}/packages" -maxdepth 1 -type f -name '*.deb' 2>/dev/null | sort | tail -n 1 || true)"
        fi
        if [ -n "${match}" ]; then
            printf '%s\n' "${match}"
            return 0
        fi
    fi
    return 1
}

wifibt_install_from_static() {
    local root_dir="$1"
    local dest_fw="${root_dir}/lib/firmware"
    local src sub dest

    while IFS= read -r src; do
        wifibt_has_blobs "${src}" || continue
        install -d "${dest_fw}"
        if wifibt_is_aic; then
            sub="$(wifibt_dest_subdir)"
            dest="${dest_fw}/${sub}"
            wifibt_copy_blobs "${src}" "${dest}"
            WIFIBT_FILE_COUNT="$(wifibt_count_files "${dest}")"
        else
            wifibt_copy_blobs "${src}" "${dest_fw}"
            WIFIBT_FILE_COUNT="$(wifibt_count_files "${dest_fw}")"
        fi
        WIFIBT_RESOLVED_SOURCE="firmware"
        WIFIBT_RESOLVED_DIR="${src}"
        return 0
    done < <(wifibt_static_chip_dirs)

    return 1
}

wifibt_install_from_sdk() {
    local root_dir="$1"
    local dest_fw="${root_dir}/lib/firmware"
    local src sub dest

    while IFS= read -r src; do
        wifibt_has_blobs "${src}" || continue
        install -d "${dest_fw}"
        if wifibt_is_aic; then
            sub="$(wifibt_dest_subdir)"
            dest="${dest_fw}/${sub}"
            wifibt_copy_blobs "${src}" "${dest}"
            WIFIBT_FILE_COUNT="$(wifibt_count_files "${dest}")"
        else
            wifibt_copy_blobs "${src}" "${dest_fw}"
            WIFIBT_FILE_COUNT="$(wifibt_count_files "${dest_fw}")"
        fi
        WIFIBT_RESOLVED_SOURCE="sdk"
        WIFIBT_RESOLVED_DIR="${src}"
        return 0
    done < <(wifibt_sdk_chip_dirs 2>/dev/null || true)

    return 1
}

install_wifibt_firmware() {
    local root_dir="$1"
    local deb msg

    [ -n "${root_dir}" ] || die "install_wifibt_firmware: root_dir required"
    resolve_wifibt_config

    if [ "${WIFIBT_CHIP}" = "none" ]; then
        if [ "${WIFIBT_REQUIRED}" = "yes" ]; then
            die "WIFIBT_REQUIRED=yes but WIFIBT_CHIP is none/empty"
        fi
        WIFIBT_RESOLVED_SOURCE="skipped"
        return 0
    fi

    case "${WIFIBT_SOURCE}" in
        package)
            deb="$(wifibt_resolve_deb)" || {
                msg="No WiFi/BT package for WIFIBT_CHIP=${WIFIBT_CHIP} (set WIFIBT_DEB or drop .deb under overlays/wifibt/packages/)"
                [ "${WIFIBT_REQUIRED}" = "yes" ] && die "${msg}"
                log_warn "${msg}"
                WIFIBT_RESOLVED_SOURCE="missing"
                return 0
            }
            wifibt_install_from_deb "${root_dir}" "${deb}" || {
                msg="Failed to install firmware from package ${deb}"
                [ "${WIFIBT_REQUIRED}" = "yes" ] && die "${msg}"
                log_warn "${msg}"
                WIFIBT_RESOLVED_SOURCE="empty"
                return 0
            }
            ;;
        firmware)
            wifibt_install_from_static "${root_dir}" || {
                msg="No static firmware blobs for WIFIBT_CHIP=${WIFIBT_CHIP} under overlays/wifibt/firmware/"
                [ "${WIFIBT_REQUIRED}" = "yes" ] && die "${msg}"
                log_warn "${msg}"
                WIFIBT_RESOLVED_SOURCE="missing"
                return 0
            }
            ;;
        sdk)
            wifibt_install_from_sdk "${root_dir}" || {
                msg="No SDK rkwifibt firmware for WIFIBT_CHIP=${WIFIBT_CHIP}"
                [ "${WIFIBT_REQUIRED}" = "yes" ] && die "${msg}"
                log_warn "${msg}"
                WIFIBT_RESOLVED_SOURCE="missing"
                return 0
            }
            ;;
        auto)
            if deb="$(wifibt_resolve_deb 2>/dev/null)"; then
                wifibt_install_from_deb "${root_dir}" "${deb}" || true
            fi
            if [ -z "${WIFIBT_RESOLVED_SOURCE}" ] || [ "${WIFIBT_RESOLVED_SOURCE}" = "" ]; then
                wifibt_install_from_static "${root_dir}" || true
            fi
            if [ -z "${WIFIBT_RESOLVED_SOURCE}" ] || [ "${WIFIBT_RESOLVED_SOURCE}" = "" ]; then
                wifibt_install_from_sdk "${root_dir}" || true
            fi
            if [ -z "${WIFIBT_RESOLVED_SOURCE}" ] || [ "${WIFIBT_RESOLVED_SOURCE}" = "" ]; then
                msg="WiFi/BT firmware not found for WIFIBT_CHIP=${WIFIBT_CHIP}"
                if [ "${WIFIBT_REQUIRED}" = "yes" ]; then
                    die "${msg}. Provide WIFIBT_DEB, packages/*.deb, or files under overlays/wifibt/firmware/${WIFIBT_CHIP}/"
                fi
                log_warn "${msg}"
                log_warn "Place a .deb in overlays/wifibt/packages/ or blobs under overlays/wifibt/firmware/${WIFIBT_CHIP}/"
                WIFIBT_RESOLVED_SOURCE="missing"
                return 0
            fi
            ;;
    esac

    if [ "${WIFIBT_FILE_COUNT:-0}" -eq 0 ]; then
        msg="WiFi/BT firmware install produced zero files for WIFIBT_CHIP=${WIFIBT_CHIP}"
        if [ "${WIFIBT_REQUIRED}" = "yes" ]; then
            die "${msg}"
        fi
        log_warn "${msg}"
        WIFIBT_RESOLVED_SOURCE="empty"
        return 0
    fi

    wifibt_apply_vendor_symlinks "${root_dir}"
    log_info "WiFi/BT firmware installed: chip=${WIFIBT_CHIP} source=${WIFIBT_RESOLVED_SOURCE} files=${WIFIBT_FILE_COUNT}"
}
