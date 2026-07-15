#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
export PROJECT_DIR

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_cmd bash find grep sed

failures=0

run_check() {
    local description="$1"
    shift
    log_step "${description}"
    if "$@"; then
        return 0
    fi
    log_warn "Check failed: ${description}"
    failures=$((failures + 1))
}

check_bash_syntax() {
    local script
    while IFS= read -r -d '' script; do
        bash -n "${script}" || return 1
    done < <(find "${PROJECT_DIR}/scripts" "${PROJECT_DIR}/rootfs" \
        -type f -name '*.sh' -print0)
}

check_shellcheck() {
    local -a scripts=()
    mapfile -d '' scripts < <(
        find "${PROJECT_DIR}/scripts" "${PROJECT_DIR}/rootfs" \
            -type f -name '*.sh' -print0
    )
    shellcheck -x -P SCRIPTDIR "${scripts[@]}"
}

check_manifests() {
    local manifest parser=none
    if command -v xmllint >/dev/null 2>&1; then
        parser=xmllint
    elif command -v python3 >/dev/null 2>&1 &&
        python3 -c 'import xml.etree.ElementTree' >/dev/null 2>&1; then
        parser=python3
    else
        log_warn "xmllint and Python XML support unavailable; skipping XML syntax validation"
    fi

    while IFS= read -r -d '' manifest; do
        if [ "${parser}" = "xmllint" ]; then
            xmllint --noout "${manifest}" || return 1
        elif [ "${parser}" = "python3" ]; then
            python3 -c 'import sys, xml.etree.ElementTree as ET; ET.parse(sys.argv[1])' \
                "${manifest}" || return 1
        fi

        if [ "$(basename "${manifest}")" != "default.xml" ]; then
            grep -q 'remote name="buildroot"' "${manifest}" || return 1
            grep -q 'revision="refs/tags/2025.02.15"' "${manifest}" || return 1
        fi
    done < <(find "${PROJECT_DIR}/manifests" -maxdepth 1 -type f \
        -name '*.xml' -print0)
}

check_board_profiles() {
    local profile board
    while IFS= read -r -d '' profile; do
        board="$(basename "${profile}" .conf)"
        (
            BOARD="${board}"
            load_board_profile
            [ "${BOOTLOADER_LAYOUT}" = "rockchip-gpt-extlinux-v1" ]
        ) || return 1
    done < <(find "${CONFIG_DIR}/boards" -maxdepth 1 -type f \
        -name '*.conf' -print0)
}

check_buildroot_external() {
    local required=(
        "${ROOTFS_CONFIG_DIR}/buildroot/external.desc"
        "${ROOTFS_CONFIG_DIR}/buildroot/Config.in"
        "${ROOTFS_CONFIG_DIR}/buildroot/external.mk"
        "${ROOTFS_CONFIG_DIR}/buildroot/configs/rk3588_rootfs_defconfig"
        "${ROOTFS_CONFIG_DIR}/buildroot/board/rk3588/post-build.sh"
    )
    local path
    for path in "${required[@]}"; do
        [ -f "${path}" ] || return 1
    done
    grep -q '^BR2_TARGET_ROOTFS_EXT2_LABEL="rootfs"$' \
        "${ROOTFS_CONFIG_DIR}/buildroot/configs/rk3588_rootfs_defconfig" &&
        ! grep -Eq 'udhcpc[[:space:]].*-q([[:space:]]|$)' \
            "${ROOTFS_CONFIG_DIR}/buildroot/board/rk3588/overlay/etc/init.d/S40network"
}

check_uboot_boot_contract_guard() {
    local script="${PROJECT_DIR}/scripts/build_uboot.sh"
    local marker
    # These markers must match literal shell expressions.
    # shellcheck disable=SC2016
    local -a markers=(
        validate_extlinux_boot_contract
        CONFIG_DISTRO_DEFAULTS
        CONFIG_CMD_MMC
        CONFIG_CMD_FAT
        CONFIG_CMD_FS_GENERIC
        CONFIG_CMD_PXE
        CONFIG_CMD_BOOTI
        CONFIG_FIT_SIGNATURE
        CONFIG_AVB_VBMETA_PUBLIC_KEY_VALIDATE
        'run distro_bootcmd;'
        extlinux/extlinux.conf
        'bash ./make.sh "${UBOOT_BOARD}" "CROSS_COMPILE=${CROSS_COMPILE}"'
        boot_flow=rockchip-gpt-extlinux-v1
    )

    for marker in "${markers[@]}"; do
        grep -Fq "${marker}" "${script}" || return 1
    done
}

expect_failure() {
    "$@" >/dev/null 2>&1 && return 1
    return 0
}

self_tests() {
    expect_failure bash -c \
        "source '${SCRIPT_DIR}/lib/common.sh'; BOARD=missing-board; load_board_profile"
    expect_failure bash -c \
        "source '${SCRIPT_DIR}/lib/common.sh'; ROOTFS=invalid; validate_rootfs_choice"
    expect_failure bash -c \
        "source '${SCRIPT_DIR}/lib/common.sh'; safe_reset_dir /tmp /tmp"
}

check_compose() {
    docker compose -f "${PROJECT_DIR}/docker-compose.yml" config --quiet
}

run_check "Bash syntax" check_bash_syntax
if command -v shellcheck >/dev/null 2>&1; then
    run_check "ShellCheck" check_shellcheck
else
    log_warn "shellcheck not installed; skipping lint"
fi
run_check "Manifest XML and pinned Buildroot project" check_manifests
run_check "Board profiles" check_board_profiles
run_check "Buildroot external tree" check_buildroot_external
run_check "U-Boot GPT/extlinux contract guard" check_uboot_boot_contract_guard
run_check "Failure-path self-tests" self_tests
if command -v docker >/dev/null 2>&1; then
    run_check "Docker Compose configuration" check_compose
else
    log_warn "docker not installed; skipping Compose validation"
fi

[ "${failures}" -eq 0 ] || die "${failures} project check(s) failed"
log_info "All available project checks passed"
