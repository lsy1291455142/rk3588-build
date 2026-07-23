#!/bin/sh
# Per-board self-check hook for RK3588 Muse (sourced by scripts/check.sh).
# The core check.sh must not hardcode any board name; board contracts live here.
board_check() {
    local profile="${BOARD_DIR}/board.conf"
    grep -Fq 'DEBIAN_PACKAGES_DEFAULT' "${profile}" || return 1
    grep -Fq 'DEBIAN_OVERLAYS_DEFAULT' "${profile}" || return 1
}
