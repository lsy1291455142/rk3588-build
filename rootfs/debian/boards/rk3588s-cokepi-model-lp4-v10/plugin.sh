#!/usr/bin/env bash
# Board plugin for rk3588s-cokepi-model-lp4-v10.
# Applied automatically when BOARD matches (same dispatch as optional overlays).

board_plugin_apply() {
    local root_dir="$1"
    local self_dir
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # shellcheck source=lib-aic8800.sh
    source "${self_dir}/lib-aic8800.sh"

    # Stage firmware blobs into this board overlay (host-side extract/remap).
    # Prefer packages/*.deb cache; otherwise download the pinned 3.0 deb.
    # Skip network fetch when offline only if blobs already staged, else fail.
    if [ -n "$(find "${self_dir}/overlay/lib/firmware/aic8800D80" -type f ! -name 'SOURCE.txt' 2>/dev/null | head -n 1)" ]; then
        log_info "Board ${BOARD}: AIC8800 firmware already staged"
    else
        stage_aic8800_firmware "${self_dir}"
    fi

    # Static board tree (firmware + vendor links).
    if [ -d "${self_dir}/overlay" ]; then
        apply_rootfs_overlay_tree "${root_dir}" "${self_dir}/overlay"
    fi
}
