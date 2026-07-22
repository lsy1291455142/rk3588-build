#!/usr/bin/env bash
# Board plugin for rk3588s-cokepi-model-lp4-v10.
# Applied automatically when BOARD matches (same dispatch as optional overlays).
#
# Note: docker mounts ./rootfs as :ro. Never write into the board tree here;
# install firmware into root_dir (and use packages/*.deb as read-only input).

board_plugin_apply() {
    local root_dir="$1"
    local self_dir
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # shellcheck source=lib-aic8800.sh
    source "${self_dir}/lib-aic8800.sh"

    # Static board tree (SOURCE.txt, vendor links, any host-pre-staged blobs).
    if [ -d "${self_dir}/overlay" ]; then
        apply_rootfs_overlay_tree "${root_dir}" "${self_dir}/overlay"
    fi

    # Ensure firmware blobs exist in the rootfs. Prefer packages/*.deb when
    # overlay has only SOURCE.txt (typical in clean CI / docker :ro).
    install_aic8800_firmware_into_rootfs "${root_dir}" "${self_dir}"
}
