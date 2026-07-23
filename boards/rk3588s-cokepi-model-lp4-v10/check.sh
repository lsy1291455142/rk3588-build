#!/bin/sh
# Per-board self-check hook for CokePi Model LP4 V1.0 (sourced by scripts/check.sh).
# The core check.sh must not hardcode any board name; board contracts live here.
board_check() {
    local profile="${BOARD_DIR}/board.conf"
    local expected
    local -a shared_markers=(
        'KERNEL_DEFCONFIG="cokepi_main_defconfig"'
        'UBOOT_DEFCONFIG="rk3588_defconfig"'
        'UBOOT_BOARD="rk3588"'
        'UBOOT_BUILD_SYSTEM="rockchip-make-sh"'
        'UBOOT_PYTHON="python2"'
        'EXTRA_KERNEL_ARGS="earlycon=uart8250,mmio32,0xfeb50000 consoleblank=0 irqchip.gicv3_pseudo_nmi=0 rcupdate.rcu_expedited=1 rcu_nocbs=all"'
    )
    for expected in "${shared_markers[@]}"; do
        grep -Fqx "${expected}" "${profile}" || return 1
    done
    grep -Fqx 'KERNEL_DTB="rk3588s-cpm-hdmi1.dtb"' "${profile}" || return 1

    # Board-local plugin + firmware stage files must exist.
    [ -d "${BOARD_DIR}/rootfs/overlay" ] || return 1
    [ -f "${BOARD_DIR}/rootfs/plugin.sh" ] || return 1
    [ -f "${BOARD_DIR}/rootfs/lib-aic8800.sh" ] || return 1
    [ -x "${BOARD_DIR}/rootfs/stage-aic8800-firmware.sh" ] || return 1
    grep -Fq 'DEBIAN_OVERLAYS_DEFAULT' "${profile}" || return 1
    grep -Fq 'wifibt' "${profile}" && return 1

    # Functional: applying the board plugin must wire the vendor/firmware links.
    (
        BOARD=rk3588s-cokepi-model-lp4-v10
        tmp="$(mktemp -d)"
        apply_debian_board_overlay "${tmp}"
        [ -L "${tmp}/vendor" ] || exit 1
        [ "$(readlink "${tmp}/vendor")" = "/system" ] || exit 1
        [ -L "${tmp}/system/etc/firmware" ] || exit 1
        [ "$(readlink "${tmp}/system/etc/firmware")" = "/lib/firmware" ] || exit 1
        [ -f "${tmp}/lib/firmware/aic8800D80/SOURCE.txt" ] || exit 1
        [ -n "$(find "${tmp}/lib/firmware/aic8800D80" -type f ! -name 'SOURCE.txt' 2>/dev/null | head -n 1)" ] || exit 1
        rm -rf "${tmp}"
    ) || return 1
}
