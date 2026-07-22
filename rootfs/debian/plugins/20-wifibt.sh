#!/usr/bin/env bash
# WiFi/BT firmware plugin. Driven by WIFIBT_CHIP / WIFIBT_SOURCE / WIFIBT_REQUIRED.
# Not an apt package token; install_wifibt_firmware lives in scripts/lib/common.sh.

plugin_apply() {
    local root_dir="$1"
    log_info "Plugin wifibt: installing firmware (WIFIBT_CHIP=${WIFIBT_CHIP:-none})"
    install_wifibt_firmware "${root_dir}"
}
