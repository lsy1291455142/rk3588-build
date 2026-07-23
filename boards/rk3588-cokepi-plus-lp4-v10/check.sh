#!/bin/sh
# Per-board self-check hook for CokePi Plus LP4 V1.0 (sourced by scripts/check.sh).
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
    grep -Fqx 'KERNEL_DTB="rk3588-cpp-hdmi.dtb"' "${profile}" || return 1
    grep -Fqx 'UBOOT_PYTHON="python2"' "${profile}" || return 1
}
