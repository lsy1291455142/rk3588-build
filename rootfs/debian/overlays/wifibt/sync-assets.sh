#!/usr/bin/env bash
# Host-side helper for the wifibt overlay: fetch or stage firmware packages/blobs.
#
# Preferred (package):
#   ./rootfs/debian/overlays/wifibt/sync-assets.sh --deb URL_OR_PATH
#   ./rootfs/debian/overlays/wifibt/sync-assets.sh --deb-aic   # Radxa aic8800-firmware release
#
# Optional (static blobs from full BSP tree — last resort):
#   ./rootfs/debian/overlays/wifibt/sync-assets.sh --from-bsp /path/to/full-bsp [CHIP]
#
# Does not modify the SDK. Not a Makefile core target.

set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${SELF_DIR}/packages"
FW_DIR="${SELF_DIR}/firmware"

# Latest known Radxa aic8800-firmware release asset (override with AIC8800_FIRMWARE_URL).
DEFAULT_AIC_DEB_URL="${AIC8800_FIRMWARE_URL:-https://github.com/radxa-pkg/aic8800/releases/download/5.0%2Bgit20260123.5f7be68d-7/aic8800-firmware_5.0+git20260123.5f7be68d-7_all.deb}"

usage() {
    cat <<'USAGE'
Usage:
  sync-assets.sh --deb URL_OR_PATH
  sync-assets.sh --deb-aic
  sync-assets.sh --from-bsp /path/to/full-bsp [CHIP]
  sync-assets.sh --extract-deb PATH.deb [CHIP]

Stages files under this overlay only:
  packages/*.deb
  firmware/<CHIP>/   (after --extract-deb)
USAGE
}

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

stage_deb() {
    local src="$1"
    local name dest
    install -d "${PKG_DIR}"
    if [[ "${src}" =~ ^https?:// ]]; then
        name="$(basename "${src%%\?*}")"
        dest="${PKG_DIR}/${name}"
        echo "Downloading ${src} -> ${dest}"
        download_to "${src}" "${dest}"
    else
        [ -f "${src}" ] || { echo "ERROR: not a file: ${src}" >&2; exit 1; }
        name="$(basename "${src}")"
        dest="${PKG_DIR}/${name}"
        echo "Copying ${src} -> ${dest}"
        cp -a "${src}" "${dest}"
    fi
    echo "Staged package: ${dest}"
}

extract_deb_to_firmware() {
    local deb="$1"
    local chip="${2:-AIC8800D80}"
    local work extract sub dest
    chip="$(printf '%s' "${chip}" | tr '[:lower:]' '[:upper:]')"
    case "${chip}" in
        AIC8800D80) sub=aic8800D80 ;;
        AIC8800DC) sub=aic8800DC ;;
        AIC8800D80N) sub=aic8800D80N ;;
        AIC8800D80X2) sub=aic8800D80X2 ;;
        AIC8800) sub=aic8800 ;;
        *) sub="" ;;
    esac

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
            else echo "ERROR: cannot extract ${deb}" >&2; exit 1
            fi
        )
    fi

    dest="${FW_DIR}/${chip}"
    mkdir -p "${dest}"
    if [ -n "${sub}" ]; then
        for src in \
            "${extract}/lib/firmware/aic8800_fw/SDIO/${sub}" \
            "${extract}/lib/firmware/aic8800_fw/PCIE/${sub}" \
            "${extract}/lib/firmware/${sub}"
        do
            if [ -d "${src}" ]; then
                cp -a "${src}"/. "${dest}"/
                echo "Extracted ${src} -> ${dest}"
                find "${dest}" -type f | wc -l | xargs -I{} echo "Files: {}"
                rm -rf "${work}"
                return 0
            fi
        done
    fi
    if [ -d "${extract}/lib/firmware" ]; then
        cp -a "${extract}/lib/firmware"/. "${dest}"/
        echo "Extracted package firmware payload -> ${dest}"
        rm -rf "${work}"
        return 0
    fi
    rm -rf "${work}"
    echo "ERROR: no firmware payload found in ${deb}" >&2
    exit 1
}

from_bsp() {
    local sdk_path="$1"
    local chip="${2:-ALL_AP}"
    local src dest
    src="${sdk_path}/external/rkwifibt/firmware"
    [ -d "${src}" ] || { echo "ERROR: missing ${src}" >&2; exit 1; }
    dest="${FW_DIR}"
    mkdir -p "${dest}"
    case "${chip}" in
        ALL|all)
            cp -a "${src}"/. "${dest}"/
            ;;
        ALL_AP|all_ap)
            mkdir -p "${dest}/broadcom"
            cp -a "${src}/broadcom"/. "${dest}/broadcom"/
            ;;
        ALL_CY|all_cy)
            mkdir -p "${dest}/infineon"
            cp -a "${src}/infineon"/. "${dest}/infineon"/
            ;;
        AP*|BCM*)
            mkdir -p "${dest}/broadcom"
            cp -a "${src}/broadcom/${chip}" "${dest}/broadcom/"
            # also flat chip dir for thin installer
            mkdir -p "${dest}/${chip}"
            if [ -d "${src}/broadcom/${chip}/wifi" ] || [ -d "${src}/broadcom/${chip}/bt" ]; then
                [ -d "${src}/broadcom/${chip}/wifi" ] && cp -a "${src}/broadcom/${chip}/wifi"/. "${dest}/${chip}"/
                [ -d "${src}/broadcom/${chip}/bt" ] && cp -a "${src}/broadcom/${chip}/bt"/. "${dest}/${chip}"/
            else
                cp -a "${src}/broadcom/${chip}"/. "${dest}/${chip}"/
            fi
            ;;
        RTL*)
            mkdir -p "${dest}/realtek" "${dest}/${chip}"
            cp -a "${src}/realtek/${chip}" "${dest}/realtek/"
            cp -a "${src}/realtek/${chip}"/. "${dest}/${chip}"/
            ;;
        CYW*)
            mkdir -p "${dest}/infineon" "${dest}/${chip}"
            cp -a "${src}/infineon/${chip}" "${dest}/infineon/"
            cp -a "${src}/infineon/${chip}"/. "${dest}/${chip}"/
            ;;
        AIC*|aic*)
            chip="$(printf '%s' "${chip}" | tr '[:lower:]' '[:upper:]')"
            echo "AIC is usually not in rkwifibt; use --deb-aic instead." >&2
            mkdir -p "${dest}/${chip}"
            if [ -d "${src}/aicsemi/${chip}" ]; then
                cp -a "${src}/aicsemi/${chip}"/. "${dest}/${chip}"/
            else
                exit 1
            fi
            ;;
        *)
            echo "ERROR: unsupported CHIP=${chip}" >&2
            exit 1
            ;;
    esac
    find "${dest}" -type f | wc -l | xargs -I{} echo "Synced firmware files: {} under ${dest}"
}

if [ "$#" -lt 1 ]; then
    usage
    exit 1
fi

case "$1" in
    -h|--help) usage; exit 0 ;;
    --deb)
        [ "$#" -ge 2 ] || { usage; exit 1; }
        stage_deb "$2"
        ;;
    --deb-aic)
        stage_deb "${DEFAULT_AIC_DEB_URL}"
        ;;
    --extract-deb)
        [ "$#" -ge 2 ] || { usage; exit 1; }
        extract_deb_to_firmware "$2" "${3:-AIC8800D80}"
        ;;
    --from-bsp)
        [ "$#" -ge 2 ] || { usage; exit 1; }
        from_bsp "$2" "${3:-ALL_AP}"
        ;;
    # Back-compat: old "SDK_PATH [CHIP]" positional form
    *)
        if [ -d "$1/external/rkwifibt/firmware" ] || [ -d "$1" ]; then
            from_bsp "$1" "${2:-ALL_AP}"
        else
            usage
            exit 1
        fi
        ;;
esac
