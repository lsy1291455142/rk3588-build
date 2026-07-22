#!/usr/bin/env bash
# Host-side helper: extract Radxa aic8800-firmware .deb into this board overlay.
# Not a core build step. Run once (or when the deb updates), then make build-rootfs.
#
# Usage:
#   ./rootfs/debian/boards/rk3588s-cokepi-model-lp4-v10/stage-aic8800-firmware.sh
#   ./rootfs/debian/boards/rk3588s-cokepi-model-lp4-v10/stage-aic8800-firmware.sh /path/or/url.deb
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${SELF_DIR}/packages"
DEST_DIR="${SELF_DIR}/overlay/lib/firmware/aic8800D80"
# CokePi BSP aic8800 driver expects patch-table AICBT_PINF_T len <= 4.
# Radxa 4.0/5.0 firmware uses info_len=6 and can overflow/panic with that driver.
# Default pin: 3.0 line (info_len=4). Override with AIC8800_FIRMWARE_URL or path arg.
DEFAULT_URL="${AIC8800_FIRMWARE_URL:-https://github.com/radxa-pkg/aic8800/releases/download/3.0%2Bgit20240327.3561b08f-7/aic8800-firmware_3.0+git20240327.3561b08f-7_all.deb}"

download_to() {
    local url="$1" dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "${dest}.partial" "${url}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "${dest}.partial" "${url}"
    else
        echo "ERROR: need curl or wget" >&2
        exit 1
    fi
    mv "${dest}.partial" "${dest}"
}

resolve_deb() {
    local src="${1:-}"
    local name dest
    install -d "${PKG_DIR}"
    if [ -z "${src}" ]; then
        # Prefer already staged package
        dest="$(find "${PKG_DIR}" -maxdepth 1 -type f -name 'aic8800-firmware*.deb' 2>/dev/null | sort | tail -n 1 || true)"
        if [ -n "${dest}" ]; then
            printf '%s\n' "${dest}"
            return 0
        fi
        src="${DEFAULT_URL}"
    fi
    if [[ "${src}" =~ ^https?:// ]]; then
        name="$(basename "${src%%\?*}")"
        dest="${PKG_DIR}/${name}"
        if [ ! -f "${dest}" ]; then
            echo "Downloading ${src} -> ${dest}"
            download_to "${src}" "${dest}"
        else
            echo "Using cached package: ${dest}"
        fi
        printf '%s\n' "${dest}"
        return 0
    fi
    [ -f "${src}" ] || { echo "ERROR: not a file: ${src}" >&2; exit 1; }
    name="$(basename "${src}")"
    dest="${PKG_DIR}/${name}"
    if [ "$(realpath "${src}")" != "$(realpath "${dest}" 2>/dev/null || true)" ]; then
        cp -a "${src}" "${dest}"
    fi
    printf '%s\n' "${dest}"
}

extract_sdio_aic8800d80() {
    local deb="$1"
    local work extract src_dir f count
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
        )
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
        exit 1
    fi

    install -d "${DEST_DIR}"
    # Keep SOURCE.txt; replace blobs.
    find "${DEST_DIR}" -mindepth 1 -maxdepth 1 ! -name 'SOURCE.txt' -exec rm -rf {} +
    count=0
    while IFS= read -r -d '' f; do
        cp -a "${f}" "${DEST_DIR}/"
        count=$((count + 1))
    done < <(find "${src_dir}" -maxdepth 1 -type f -print0 | sort -z)

    # Ensure Rockchip vendor links exist in the board overlay.
    install -d "${SELF_DIR}/overlay/system/etc"
    ln -sfn /system "${SELF_DIR}/overlay/vendor"
    ln -sfn /lib/firmware "${SELF_DIR}/overlay/system/etc/firmware"

    rm -rf "${work}"
    echo "Staged ${count} files into ${DEST_DIR}"
    echo "Vendor links: overlay/vendor -> /system, overlay/system/etc/firmware -> /lib/firmware"
    if [ "${count}" -eq 0 ]; then
        echo "ERROR: zero firmware files staged" >&2
        exit 1
    fi
}

main() {
    local deb
    deb="$(resolve_deb "${1:-}")"
    echo "Package: ${deb}"
    extract_sdio_aic8800d80 "${deb}"
}

main "$@"
