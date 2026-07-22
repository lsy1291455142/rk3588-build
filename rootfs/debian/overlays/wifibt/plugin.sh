#!/usr/bin/env bash
# WiFi/BT firmware overlay plugin. Driven by WIFIBT_CHIP / WIFIBT_SOURCE / WIFIBT_REQUIRED.

plugin_apply() {
    local root_dir="$1"
    log_info "Overlay wifibt: WIFIBT_CHIP=${WIFIBT_CHIP:-none}"
    install_wifibt_firmware "${root_dir}"
}
