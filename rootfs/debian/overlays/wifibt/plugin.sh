#!/usr/bin/env bash
# Optional WiFi/BT firmware overlay: install a firmware package/blobs + path remap.
# Env: WIFIBT_CHIP, WIFIBT_DEB, WIFIBT_SOURCE, WIFIBT_REQUIRED, WIFIBT_FIRMWARE_SYMLINKS

plugin_apply() {
    local root_dir="$1"
    local self_dir
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # shellcheck source=lib.sh
    source "${self_dir}/lib.sh"

    log_info "Overlay wifibt: chip=${WIFIBT_CHIP:-none} source=${WIFIBT_SOURCE:-auto}"
    install_wifibt_firmware "${root_dir}"
}
