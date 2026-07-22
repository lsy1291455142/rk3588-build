#!/usr/bin/env bash
# CokePi Model board-local AIC8800 firmware install.
# Used by boards/.../plugin.sh during rootfs build (container has rootfs/:ro).
# Manual CLI may still stage into the board overlay on a writable host tree.

# CokePi BSP aic8800 driver expects patch-table AICBT_PINF_T len <= 4.
# Radxa 4.0/5.0 firmware uses info_len=6 and can overflow/panic with that driver.
# Default pin: 3.0 line (info_len=4). Override with AIC8800_FIRMWARE_URL or path arg.
cokepi_aic8800_default_url() {
    printf '%s\n' "${AIC8800_FIRMWARE_URL:-https://github.com/radxa-pkg/aic8800/releases/download/3.0%2Bgit20240327.3561b08f-7/aic8800-firmware_3.0+git20240327.3561b08f-7_all.deb}"
}

cokepi_aic8800_download_to() {
    local url="$1" dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "${dest}.partial" "${url}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "${dest}.partial" "${url}"
    else
        echo "ERROR: need curl or wget" >&2
        return 1
    fi
    mv "${dest}.partial" "${dest}"
}

# Resolve a local aic8800-firmware*.deb path.
# Prefer board packages/ cache (read-only OK). Never require writing packages/
# during build: downloads go to a caller-provided cache dir or mktemp.
# Args: board_dir [src_path_or_url] [writable_cache_dir]
cokepi_aic8800_resolve_deb() {
    local board_dir="$1"
    local src="${2:-}"
    local cache_dir="${3:-}"
    local pkg_dir name dest

    pkg_dir="${board_dir}/packages"
    if [ -z "${cache_dir}" ]; then
        if [ -d "${pkg_dir}" ] && [ -w "${pkg_dir}" ]; then
            cache_dir="${pkg_dir}"
        else
            cache_dir="$(mktemp -d)"
        fi
    fi
    install -d "${cache_dir}" 2>/dev/null || true

    if [ -z "${src}" ]; then
        if [ -d "${pkg_dir}" ]; then
            dest="$(find "${pkg_dir}" -maxdepth 1 -type f -name 'aic8800-firmware*.deb' 2>/dev/null | sort | tail -n 1 || true)"
            if [ -n "${dest}" ]; then
                printf '%s\n' "${dest}"
                return 0
            fi
        fi
        # Also accept deb already placed in writable cache
        dest="$(find "${cache_dir}" -maxdepth 1 -type f -name 'aic8800-firmware*.deb' 2>/dev/null | sort | tail -n 1 || true)"
        if [ -n "${dest}" ]; then
            printf '%s\n' "${dest}"
            return 0
        fi
        src="$(cokepi_aic8800_default_url)"
    fi

    if [[ "${src}" =~ ^https?:// ]]; then
        name="$(basename "${src%%\?*}")"
        # Prefer existing packages/ copy even if cache is temp
        if [ -f "${pkg_dir}/${name}" ]; then
            printf '%s\n' "${pkg_dir}/${name}"
            return 0
        fi
        dest="${cache_dir}/${name}"
        if [ ! -f "${dest}" ]; then
            if [ ! -w "${cache_dir}" ]; then
                echo "ERROR: cannot download firmware: ${cache_dir} is not writable" >&2
                echo "Place aic8800-firmware_*.deb under ${pkg_dir}/ and rebuild." >&2
                return 1
            fi
            if declare -F log_info >/dev/null 2>&1; then
                log_info "Downloading ${src} -> ${dest}"
            else
                echo "Downloading ${src} -> ${dest}"
            fi
            cokepi_aic8800_download_to "${src}" "${dest}" || return 1
        else
            if declare -F log_info >/dev/null 2>&1; then
                log_info "Using cached package: ${dest}"
            else
                echo "Using cached package: ${dest}"
            fi
        fi
        printf '%s\n' "${dest}"
        return 0
    fi

    [ -f "${src}" ] || { echo "ERROR: not a file: ${src}" >&2; return 1; }
    # Use the given file in place (no copy into packages/ — may be read-only).
    printf '%s\n' "${src}"
}

# Extract SDIO aic8800D80 blobs from deb into dest_dir (must be writable).
# Does not touch the board git tree.
cokepi_aic8800_extract_to() {
    local deb="$1"
    local dest_dir="$2"
    local work extract src_dir f count cand

    [ -f "${deb}" ] || { echo "ERROR: deb not found: ${deb}" >&2; return 1; }
    [ -n "${dest_dir}" ] || { echo "ERROR: dest_dir required" >&2; return 1; }

    work="$(mktemp -d)"
    extract="${work}/root"
    mkdir -p "${extract}"
    if command -v dpkg-deb >/dev/null 2>&1; then
        dpkg-deb -x "${deb}" "${extract}"
    else
        (
            cd "${work}"
            ar x "${deb}"
            if [ -f data.tar.xz ]; then tar -C "${extract}" -xJf data.tar.xz
            elif [ -f data.tar.gz ]; then tar -C "${extract}" -xzf data.tar.gz
            elif [ -f data.tar.zst ]; then tar -C "${extract}" --zstd -xf data.tar.zst
            else
                echo "ERROR: cannot extract ${deb}" >&2
                exit 1
            fi
        ) || { rm -rf "${work}"; return 1; }
    fi

    src_dir=""
    for cand in \
        "${extract}/lib/firmware/aic8800_fw/SDIO/aic8800D80" \
        "${extract}/lib/firmware/aic8800_fw/PCIE/aic8800D80" \
        "${extract}/lib/firmware/aic8800D80"
    do
        if [ -d "${cand}" ] && [ -n "$(find "${cand}" -type f 2>/dev/null | head -n 1)" ]; then
            src_dir="${cand}"
            break
        fi
    done
    if [ -z "${src_dir}" ]; then
        echo "ERROR: deb has no aic8800D80 firmware tree: ${deb}" >&2
        rm -rf "${work}"
        return 1
    fi

    install -d "${dest_dir}"
    count=0
    while IFS= read -r -d '' f; do
        cp -a "${f}" "${dest_dir}/"
        count=$((count + 1))
    done < <(find "${src_dir}" -maxdepth 1 -type f -print0 | sort -z)
    rm -rf "${work}"

    if [ "${count}" -eq 0 ]; then
        echo "ERROR: zero firmware files extracted from ${deb}" >&2
        return 1
    fi
    if declare -F log_info >/dev/null 2>&1; then
        log_info "Extracted ${count} AIC8800 firmware files into ${dest_dir}"
    else
        echo "Extracted ${count} files into ${dest_dir}"
    fi
}

cokepi_aic8800_has_blobs() {
    local dir="$1"
    [ -d "${dir}" ] || return 1
    [ -n "$(find "${dir}" -type f ! -name 'SOURCE.txt' 2>/dev/null | head -n 1)" ]
}

# Ensure Rockchip vendor firmware path links exist under root_dir.
cokepi_aic8800_ensure_vendor_links() {
    local root_dir="$1"
    install -d "${root_dir}/system/etc"
    ln -sfn /system "${root_dir}/vendor"
    ln -sfn /lib/firmware "${root_dir}/system/etc/firmware"
}

# Install firmware into a rootfs tree (build-time path; no writes to board dir).
# Args: root_dir board_dir [deb_path_or_url]
install_aic8800_firmware_into_rootfs() {
    local root_dir="$1"
    local board_dir="$2"
    local src="${3:-}"
    local fw_dest deb work_cache extract_dir

    [ -n "${root_dir}" ] || { echo "ERROR: root_dir required" >&2; return 1; }
    [ -n "${board_dir}" ] || { echo "ERROR: board_dir required" >&2; return 1; }

    fw_dest="${root_dir}/lib/firmware/aic8800D80"
    if cokepi_aic8800_has_blobs "${fw_dest}"; then
        if declare -F log_info >/dev/null 2>&1; then
            log_info "AIC8800 firmware already present in rootfs"
        fi
        cokepi_aic8800_ensure_vendor_links "${root_dir}"
        return 0
    fi

    # Prefer blobs already present in the board overlay (host pre-staged, read-only OK).
    if cokepi_aic8800_has_blobs "${board_dir}/overlay/lib/firmware/aic8800D80"; then
        if declare -F log_info >/dev/null 2>&1; then
            log_info "Using pre-staged board overlay AIC8800 firmware"
        fi
        install -d "${fw_dest}"
        find "${board_dir}/overlay/lib/firmware/aic8800D80" -maxdepth 1 -type f \
            ! -name 'SOURCE.txt' -exec cp -a {} "${fw_dest}/" \;
        cokepi_aic8800_ensure_vendor_links "${root_dir}"
        return 0
    fi

    work_cache="$(mktemp -d)"
    extract_dir="$(mktemp -d)"
    deb="$(cokepi_aic8800_resolve_deb "${board_dir}" "${src}" "${work_cache}")" || {
        rm -rf "${work_cache}" "${extract_dir}"
        return 1
    }
    if declare -F log_info >/dev/null 2>&1; then
        log_info "Installing AIC8800 firmware from ${deb}"
    else
        echo "Package: ${deb}"
    fi
    cokepi_aic8800_extract_to "${deb}" "${extract_dir}" || {
        rm -rf "${work_cache}" "${extract_dir}"
        return 1
    }
    install -d "${fw_dest}"
    find "${extract_dir}" -maxdepth 1 -type f -exec cp -a {} "${fw_dest}/" \;
    cokepi_aic8800_ensure_vendor_links "${root_dir}"
    rm -rf "${work_cache}" "${extract_dir}"
}

# Host-only helper: extract into the board overlay tree (writable checkout).
# Args: board_dir [deb_path_or_url]
stage_aic8800_firmware() {
    local board_dir="$1"
    local src="${2:-}"
    local deb dest_dir

    [ -n "${board_dir}" ] || { echo "ERROR: stage_aic8800_firmware: board_dir required" >&2; return 1; }
    dest_dir="${board_dir}/overlay/lib/firmware/aic8800D80"
    if [ ! -w "${board_dir}/overlay" ] && [ ! -w "$(dirname "${board_dir}/overlay")" ]; then
        echo "ERROR: board overlay is not writable: ${board_dir}/overlay" >&2
        echo "During docker build, firmware is installed into the rootfs directly;" >&2
        echo "manual stage is only for a writable host tree." >&2
        return 1
    fi

    deb="$(cokepi_aic8800_resolve_deb "${board_dir}" "${src}")" || return 1
    if declare -F log_info >/dev/null 2>&1; then
        log_info "Staging AIC8800 firmware from ${deb}"
    else
        echo "Package: ${deb}"
    fi
    install -d "${dest_dir}"
    # Keep SOURCE.txt; replace blobs.
    find "${dest_dir}" -mindepth 1 -maxdepth 1 ! -name 'SOURCE.txt' -exec rm -rf {} + 2>/dev/null || true
    cokepi_aic8800_extract_to "${deb}" "${dest_dir}" || return 1

    install -d "${board_dir}/overlay/system/etc"
    ln -sfn /system "${board_dir}/overlay/vendor"
    ln -sfn /lib/firmware "${board_dir}/overlay/system/etc/firmware"
    if declare -F log_info >/dev/null 2>&1; then
        log_info "Staged AIC8800 firmware into ${dest_dir}"
    else
        echo "Vendor links: overlay/vendor -> /system, overlay/system/etc/firmware -> /lib/firmware"
    fi
}
