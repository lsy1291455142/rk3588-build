#!/usr/bin/env bash
# CokePi Model board-local AIC8800 firmware staging.
# Called from board plugin_apply during rootfs build (and optional manual CLI).
# Not part of the pure build core.

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

cokepi_aic8800_resolve_deb() {
    local board_dir="$1"
    local src="${2:-}"
    local pkg_dir name dest
    pkg_dir="${board_dir}/packages"
    install -d "${pkg_dir}"
    if [ -z "${src}" ]; then
        dest="$(find "${pkg_dir}" -maxdepth 1 -type f -name 'aic8800-firmware*.deb' 2>/dev/null | sort | tail -n 1 || true)"
        if [ -n "${dest}" ]; then
            printf '%s\n' "${dest}"
            return 0
        fi
        src="$(cokepi_aic8800_default_url)"
    fi
    if [[ "${src}" =~ ^https?:// ]]; then
        name="$(basename "${src%%\?*}")"
        dest="${pkg_dir}/${name}"
        if [ ! -f "${dest}" ]; then
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
    name="$(basename "${src}")"
    dest="${pkg_dir}/${name}"
    if [ "$(realpath "${src}")" != "$(realpath "${dest}" 2>/dev/null || true)" ]; then
        cp -a "${src}" "${dest}"
    fi
    printf '%s\n' "${dest}"
}

# Extract Radxa aic8800-firmware deb SDIO aic8800D80 blobs into board overlay.
# Args: board_dir [deb_path_or_url]
# Writes into board_dir/overlay/lib/firmware/aic8800D80/ and vendor links.
stage_aic8800_firmware() {
    local board_dir="$1"
    local src="${2:-}"
    local deb dest_dir work extract src_dir f count cand

    [ -n "${board_dir}" ] || { echo "ERROR: stage_aic8800_firmware: board_dir required" >&2; return 1; }
    dest_dir="${board_dir}/overlay/lib/firmware/aic8800D80"
    deb="$(cokepi_aic8800_resolve_deb "${board_dir}" "${src}")" || return 1

    if declare -F log_info >/dev/null 2>&1; then
        log_info "Staging AIC8800 firmware from ${deb}"
    else
        echo "Package: ${deb}"
    fi

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
    # Keep SOURCE.txt; replace blobs.
    find "${dest_dir}" -mindepth 1 -maxdepth 1 ! -name 'SOURCE.txt' -exec rm -rf {} +
    count=0
    while IFS= read -r -d '' f; do
        cp -a "${f}" "${dest_dir}/"
        count=$((count + 1))
    done < <(find "${src_dir}" -maxdepth 1 -type f -print0 | sort -z)

    # Rockchip vendor path compatibility for BSP aic8800 driver.
    install -d "${board_dir}/overlay/system/etc"
    ln -sfn /system "${board_dir}/overlay/vendor"
    ln -sfn /lib/firmware "${board_dir}/overlay/system/etc/firmware"

    rm -rf "${work}"
    if declare -F log_info >/dev/null 2>&1; then
        log_info "Staged ${count} AIC8800 firmware files into ${dest_dir}"
    else
        echo "Staged ${count} files into ${dest_dir}"
        echo "Vendor links: overlay/vendor -> /system, overlay/system/etc/firmware -> /lib/firmware"
    fi
    if [ "${count}" -eq 0 ]; then
        echo "ERROR: zero firmware files staged" >&2
        return 1
    fi
}
