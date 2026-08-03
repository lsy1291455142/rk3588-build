#!/usr/bin/env bash
# Board plugin for rk3588-muse.
# Applied automatically when BOARD matches (same dispatch as optional overlays).
#
# Note: docker mounts ./rootfs as :ro. Never write into the board tree here;
# install firmware into root_dir (and use packages/*.deb as read-only input).

board_plugin_apply() {
    local root_dir="$1"
    local self_dir
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # shellcheck source=lib-fcu761k.sh
    source "${self_dir}/lib-fcu761k.sh"
    # shellcheck source=lib-rm500q.sh
    source "${self_dir}/lib-rm500q.sh"

    # Static board tree (SOURCE.txt, vendor links, any host-pre-staged blobs,
    # RM500Q-GL runtime scripts + systemd service).
    if [ -d "${self_dir}/overlay" ]; then
        apply_rootfs_overlay_tree "${root_dir}" "${self_dir}/overlay"
    fi

    # AIC8800DC WiFi/BT firmware (public download from GitHub).
    install_fcu761k_firmware_into_rootfs "${root_dir}" "${self_dir}"

    # RM500Q-GL 5G modem firmware (NOT public — from Quectel FAE).
    # Skips with warning if not found; does not fail the build.
    install_rm500q_firmware_into_rootfs "${root_dir}" "${self_dir}"
}
