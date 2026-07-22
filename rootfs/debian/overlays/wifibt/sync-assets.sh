#!/usr/bin/env bash
# Host-side helper owned by the wifibt overlay.
# Copy WiFi/BT firmware from a full BSP tree into this overlay's firmware/ tree.
#
# Usage:
#   rootfs/debian/overlays/wifibt/sync-assets.sh /path/to/full-bsp [CHIP]
#   SDK_PATH=/path/to/full-bsp WIFIBT_CHIP=AP6275S rootfs/debian/overlays/wifibt/sync-assets.sh
#
# CHIP defaults to ALL_AP. Supported: ALL, ALL_AP, ALL_CY, AP*, BCM*, RTL*, CYW*, RK*, AIC*
# Does not modify the SDK tree. Does not require Docker.

set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${SELF_DIR}/firmware"
SDK_PATH="${SDK_PATH:-${1:-}}"
CHIP="${WIFIBT_CHIP:-${2:-ALL_AP}}"

if [ -z "${SDK_PATH}" ]; then
    echo "ERROR: SDK_PATH required (full BSP with external/rkwifibt)." >&2
    echo "Usage: $0 /path/to/full-bsp [CHIP]" >&2
    exit 1
fi

src="${SDK_PATH}/external/rkwifibt/firmware"
if [ ! -d "${src}" ]; then
    echo "ERROR: missing ${src}" >&2
    exit 1
fi

mkdir -p "${DEST}"
chip="${CHIP}"

case "${chip}" in
    ALL|all)
        echo "Syncing all vendors from ${src} -> ${DEST}"
        cp -a "${src}"/. "${DEST}"/
        ;;
    ALL_AP|all_ap)
        echo "Syncing broadcom (ALL_AP) from ${src}/broadcom -> ${DEST}/broadcom"
        mkdir -p "${DEST}/broadcom"
        cp -a "${src}/broadcom"/. "${DEST}/broadcom"/
        ;;
    ALL_CY|all_cy)
        echo "Syncing infineon (ALL_CY) from ${src}/infineon -> ${DEST}/infineon"
        mkdir -p "${DEST}/infineon"
        cp -a "${src}/infineon"/. "${DEST}/infineon"/
        ;;
    AP*|BCM*)
        echo "Syncing broadcom/${chip}"
        mkdir -p "${DEST}/broadcom"
        cp -a "${src}/broadcom/${chip}" "${DEST}/broadcom/"
        ;;
    RTL*)
        echo "Syncing realtek/${chip}"
        mkdir -p "${DEST}/realtek"
        cp -a "${src}/realtek/${chip}" "${DEST}/realtek/"
        ;;
    CYW*)
        echo "Syncing infineon/${chip}"
        mkdir -p "${DEST}/infineon"
        cp -a "${src}/infineon/${chip}" "${DEST}/infineon/"
        ;;
    RK*)
        echo "Syncing rockchip/${chip}"
        mkdir -p "${DEST}/rockchip"
        cp -a "${src}/rockchip/${chip}" "${DEST}/rockchip/"
        ;;
    AIC*)
        # BSP may store as aicsemi/AIC8800D80 or flat aic8800D80 paths.
        echo "Syncing aicsemi/${chip} (best-effort)"
        mkdir -p "${DEST}/aicsemi"
        if [ -d "${src}/aicsemi/${chip}" ]; then
            cp -a "${src}/aicsemi/${chip}" "${DEST}/aicsemi/"
        elif [ -d "${src}/aicsemi" ]; then
            # copy matching subdirs
            found=0
            for d in "${src}/aicsemi"/*; do
                [ -d "${d}" ] || continue
                base="$(basename "${d}")"
                case "${base}" in
                    "${chip}"|aic8800*|AIC8800*)
                        cp -a "${d}" "${DEST}/aicsemi/"
                        found=1
                        ;;
                esac
            done
            if [ "${found}" = "0" ]; then
                echo "ERROR: no AIC firmware under ${src}/aicsemi for ${chip}" >&2
                exit 1
            fi
        else
            echo "ERROR: missing ${src}/aicsemi/${chip}" >&2
            echo "AIC is often not in rkwifibt; place blobs under ${DEST}/aicsemi/${chip}/" >&2
            exit 1
        fi
        ;;
    *)
        echo "ERROR: unsupported WIFIBT_CHIP=${chip}" >&2
        exit 1
        ;;
esac

count="$(find "${DEST}" -type f ! -name 'SOURCE.txt' ! -name 'README*' ! -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
echo "Synced firmware files: ${count} under ${DEST}"
