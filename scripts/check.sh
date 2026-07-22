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

        grep -q 'remote name="buildroot"' "${manifest}" || return 1
        if [ "$(basename "${manifest}")" = "rk3588-rock5c.xml" ]; then
            grep -q 'revision="567401fe17185f0f4a65866158b775a364feb2d3"' \
                "${manifest}" || return 1
            grep -q 'revision="4218b05a597f458947f0f4706063b3bb8196e07c"' \
                "${manifest}" || return 1
            grep -q 'revision="ecb4fcbe954edf38b3ae037d5de6d9f5bccf81f4"' \
                "${manifest}" || return 1
            grep -q 'revision="c49ae7216786d3cb62a8e8de5556007b4b539233"' \
                "${manifest}" || return 1
        else
            grep -q 'revision="refs/tags/2025.02.15"' "${manifest}" || return 1
        fi
    done < <(find "${PROJECT_DIR}/manifests" -maxdepth 1 -type f \
        -name '*.xml' -print0)
}

check_rock5c_source_contract() {
    local profile="${CONFIG_DIR}/boards/rk3588s-rock-5c.conf"
    local expected
    local -a markers=(
        'SOURCE_MANIFEST="rk3588-rock5c.xml"'
        'EXPECTED_KERNEL_REVISION="567401fe17185f0f4a65866158b775a364feb2d3"'
        'EXPECTED_UBOOT_REVISION="4218b05a597f458947f0f4706063b3bb8196e07c"'
        'EXPECTED_RKBIN_REVISION="ecb4fcbe954edf38b3ae037d5de6d9f5bccf81f4"'
        'EXPECTED_BUILDROOT_REVISION="c49ae7216786d3cb62a8e8de5556007b4b539233"'
        'UBOOT_PYTHON="python3"'
    )
    for expected in "${markers[@]}"; do
        grep -Fqx "${expected}" "${profile}" || return 1
    done

    awk '
        /^  debian-rootfs:/ { in_service = 1; next }
        in_service && /^  [a-zA-Z0-9_-]+:/ { exit }
        in_service && /\.\/manifests:\/home\/builder\/manifests:ro/ { found = 1 }
        END { exit(found ? 0 : 1) }
    ' "${PROJECT_DIR}/docker-compose.yml" || return 1
    grep -Fq 'COPY manifests/ /home/builder/manifests/' \
        "${PROJECT_DIR}/Dockerfile" || return 1
    grep -Eq '^[[:space:]]+git[[:space:]]' \
        "${PROJECT_DIR}/Dockerfile" || return 1
    grep -Fq "git -c safe.directory=\"\${repo}\"" \
        "${PROJECT_DIR}/scripts/lib/common.sh"
}

check_cokepi_board_contract() {
    local plus_profile="${CONFIG_DIR}/boards/rk3588-cokepi-plus-lp4-v10.conf"
    local model_profile="${CONFIG_DIR}/boards/rk3588s-cokepi-model-lp4-v10.conf"
    local profile marker
    local -a shared_markers=(
        'KERNEL_DEFCONFIG="cokepi_main_defconfig"'
        'UBOOT_DEFCONFIG="rk3588_defconfig"'
        'UBOOT_BOARD="rk3588"'
        'UBOOT_BUILD_SYSTEM="rockchip-make-sh"'
        'UBOOT_PYTHON="python2"'
        'EXTRA_KERNEL_ARGS="earlycon=uart8250,mmio32,0xfeb50000 consoleblank=0 irqchip.gicv3_pseudo_nmi=0 rcupdate.rcu_expedited=1 rcu_nocbs=all"'
    )

    grep -Fqx 'KERNEL_DTB="rk3588-cpp-hdmi.dtb"' "${plus_profile}" || return 1
    grep -Fqx 'KERNEL_DTB="rk3588s-cpm-hdmi1.dtb"' "${model_profile}" || return 1
    for profile in "${plus_profile}" "${model_profile}"; do
        for marker in "${shared_markers[@]}"; do
            grep -Fqx "${marker}" "${profile}" || return 1
        done
    done

    # Board profiles should exist and parse correctly.
    # Local-SDK boards (CokePi) intentionally omit SOURCE_MANIFEST.
    grep -Fqx 'UBOOT_PYTHON="python2"' "${plus_profile}" || return 1
    grep -Fqx 'UBOOT_PYTHON="python2"' "${model_profile}" || return 1
}

check_kernel_contract() {
    local config="${CONFIG_DIR}/kernel/rootfs-base.config"
    local option
    local -a required=(
        CONFIG_FHANDLE=y
        CONFIG_SERIAL_AMBA_PL011=y
        CONFIG_SERIAL_AMBA_PL011_CONSOLE=y
        CONFIG_VIRTIO=y
        CONFIG_VIRTIO_MMIO=y
        CONFIG_VIRTIO_BLK=y
        CONFIG_VIRTIO_NET=y
        CONFIG_HW_RANDOM_VIRTIO=y
        CONFIG_RTC_DRV_PL031=y
    )
    for option in "${required[@]}"; do
        grep -Fqx "${option}" "${config}" || return 1
    done
    grep -Fq 'required_configs=(' "${PROJECT_DIR}/scripts/build_kernel.sh"
    grep -Fq "CONFIG_MALI_CSF_INCLUDE_FW=y" \
        "${PROJECT_DIR}/scripts/build_kernel.sh"
    grep -Fq 'drivers/gpu/arm/bifrost/mali_csffw.bin' \
        "${PROJECT_DIR}/scripts/build_kernel.sh"
    grep -Fq 'KERNEL_SCMVERSION_FILE' \
        "${PROJECT_DIR}/scripts/build_kernel.sh"
    grep -Fq 'prepare_kernel_source_view' \
        "${PROJECT_DIR}/scripts/build_kernel.sh"
    grep -Fq 'kernel_source_view=symlink-clean-v1' \
        "${PROJECT_DIR}/scripts/build_kernel.sh"
    if grep -Eq 'make[^[:cntrl:]]*mrproper' \
        "${PROJECT_DIR}/scripts/build_kernel.sh"; then
        return 1
    fi
    grep -Fq 'GIT_CEILING_DIRECTORIES' \
        "${PROJECT_DIR}/scripts/build_kernel.sh"
    grep -Fq '"LOCALVERSION="' \
        "${PROJECT_DIR}/scripts/build_kernel.sh"
    grep -Fq 'GIT_WORK_TREE' \
        "${PROJECT_DIR}/scripts/build_kernel.sh"
    # These checks intentionally match literal shell expressions.
    # shellcheck disable=SC2016
    grep -Fq 'fdtput -d "${KERNEL_DTB_PATH}" /chosen bootargs' \
        "${PROJECT_DIR}/scripts/build_kernel.sh"
    grep -Fq 'dtb_bootargs=extlinux-only-v1' \
        "${PROJECT_DIR}/scripts/build_kernel.sh"
    # shellcheck disable=SC2016
    grep -Fq 'verify_extlinux_dtb "${DTB_IMAGE}"' \
        "${PROJECT_DIR}/scripts/verify_image.sh"
    # shellcheck disable=SC2016
    grep -Fq 'verify_extlinux_dtb "${WORK_DIR}/${KERNEL_DTB}"' \
        "${PROJECT_DIR}/scripts/verify_image.sh"
}

check_help_contract() {
    local help_output marker
    help_output="$(make -s -C "${PROJECT_DIR}" help)"
    local -a markers=(
        'make build'
        'make build-debian-builder'
        'make use-rootfs'
        'list-boards'
        'new-board'
        'validate-board'
        'info'
    )
    for marker in "${markers[@]}"; do
        grep -Fq "${marker}" <<<"${help_output}" || return 1
    done
    grep -Eq '^test-debian-qemu:' "${PROJECT_DIR}/Makefile" || return 1
    grep -Eq '^register-arm64-binfmt:' "${PROJECT_DIR}/Makefile" || return 1
}

check_debian_builder_contract() {
    local makefile="${PROJECT_DIR}/Makefile"
    local marker
    local -a markers=(
        "docker info --format '{{.Architecture}}'"
        'amd64|x86_64)'
        'arm64|aarch64)'
        'debian-preflight: build-debian-builder'
        '--pull never'
    )

    for marker in "${markers[@]}"; do
        grep -Fq -- "${marker}" "${makefile}" || return 1
    done

    grep -Fq 'rootfs_arch=arm64' \
        "${PROJECT_DIR}/scripts/build_debian.sh" || return 1

    if grep -Fq 'dpkg --print-architecture 2>/dev/null' "${makefile}"; then
        return 1
    fi
}

check_rootfs_configuration() (
    local work_dir
    work_dir="$(mktemp -d)"
    trap 'rm -rf -- "${work_dir}"' EXIT

    grep -Eq '^ROOTFS \?=$' "${PROJECT_DIR}/Makefile" || exit 1
    grep -Eq '^require-rootfs:' "${PROJECT_DIR}/Makefile" || exit 1
    grep -Eq '^use-rootfs:' "${PROJECT_DIR}/Makefile" || exit 1
    grep -Eq '^use-rootfs-buildroot:' "${PROJECT_DIR}/Makefile" || exit 1
    grep -Eq '^use-rootfs-debian:' "${PROJECT_DIR}/Makefile" || exit 1
    grep -Eq '^use-rootfs-all:' "${PROJECT_DIR}/Makefile" || exit 1
    grep -Fq "ROOTFS: \${ROOTFS:-}" "${PROJECT_DIR}/docker-compose.yml" || exit 1

    if grep -Eq 'ROOTFS:-buildroot|ROOTFS \?= buildroot' \
        "${PROJECT_DIR}/Makefile" \
        "${PROJECT_DIR}/docker-compose.yml" \
        "${PROJECT_DIR}/scripts/lib/common.sh"; then
        exit 1
    fi
    [ ! -e "${PROJECT_DIR}/scripts/select_image_rootfs.sh" ] || exit 1

    expect_failure make -s -C "${PROJECT_DIR}" require-rootfs ROOTFS= || exit 1
    expect_failure bash -c \
        "source '${SCRIPT_DIR}/lib/common.sh'; unset ROOTFS; validate_rootfs_choice" || exit 1

    cp "${PROJECT_DIR}/Makefile" "${work_dir}/Makefile"

    make -s -C "${work_dir}" use-rootfs-debian >/dev/null || exit 1
    grep -Fqx 'ROOTFS=debian' "${work_dir}/.env" || exit 1

    make -s -C "${work_dir}" use-rootfs-buildroot >/dev/null || exit 1
    grep -Fqx 'ROOTFS=buildroot' "${work_dir}/.env" || exit 1

    make -s -C "${work_dir}" use-rootfs-all >/dev/null || exit 1
    grep -Fqx 'ROOTFS=all' "${work_dir}/.env" || exit 1

    printf '2\n' | make -s -C "${work_dir}" use-rootfs >/dev/null || exit 1
    grep -Fqx 'ROOTFS=debian' "${work_dir}/.env"
)

check_qemu_smoke_contract() {
    local script="${PROJECT_DIR}/scripts/test_debian_qemu.sh"
    local driver="${PROJECT_DIR}/scripts/lib/qemu_smoke.py"
    local marker
    local -a markers=(
        qemu-system-aarch64
        PARTLABEL=rootfs
        QEMU_INITCALL_BLACKLIST
        rockchip_drm_init
        rockchip_cpufreq_driver_init
        rga_init
        regulatory_init_db
        BOOT_ERROR_PATTERNS
        SERIAL_LOGIN_MARKER
        logfile_read
        unit_health
        systemd.default_device_timeout_sec=300s
        systemd.default_timeout_start_sec=300s
        serial-getty@ttyFIQ0.service
        sbc-firstboot.done
        systemctl
        ssh_password_login
    )
    [ -f "${script}" ] && [ -f "${driver}" ] || return 1
    for marker in "${markers[@]}"; do
        grep -Fq "${marker}" "${script}" "${driver}" || return 1
    done
    grep -Fq 'qemu-system-arm' "${PROJECT_DIR}/Dockerfile" || return 1
    grep -Fq 'python3-pexpect' "${PROJECT_DIR}/Dockerfile" || return 1
}


check_debian_features() {
    # shellcheck source=lib/common.sh
    source "${SCRIPT_DIR}/lib/common.sh"

    (
        DEBIAN_PACKAGES=""
        resolve_debian_packages
        [ "${DEBIAN_PACKAGES}" = "" ] || exit 1
        mapfile -t pkgs < <(debian_package_list)
        [ "${#pkgs[@]}" -eq 0 ] || exit 1
    ) || return 1

    (
        DEBIAN_PACKAGES="none"
        resolve_debian_packages
        [ "${DEBIAN_PACKAGES}" = "" ] || exit 1
    ) || return 1

    (
        DEBIAN_PACKAGES="network-manager,i2c-tools,htop"
        resolve_debian_packages
        mapfile -t pkgs < <(debian_package_list)
        printf '%s\n' "${pkgs[@]}" | grep -Fxq network-manager || exit 1
        printf '%s\n' "${pkgs[@]}" | grep -Fxq i2c-tools || exit 1
        printf '%s\n' "${pkgs[@]}" | grep -Fxq htop || exit 1
        [ "${DEBIAN_PACKAGES}" = "network-manager,i2c-tools,htop" ] || exit 1
    ) || return 1

    # Feature aliases must be rejected (packages are exact apt names only).
    if (
        DEBIAN_PACKAGES="nm,hwdebug"
        resolve_debian_packages
    ) 2>/dev/null; then
        return 1
    fi
    if (
        DEBIAN_PACKAGES="all"
        resolve_debian_packages
    ) 2>/dev/null; then
        return 1
    fi

    (
        WIFIBT_CHIP="AP6275S"
        WIFIBT_SOURCE="assets"
        WIFIBT_REQUIRED="no"
        resolve_wifibt_config
        [ "${WIFIBT_CHIP}" = "AP6275S" ] || exit 1
        [ "${WIFIBT_SOURCE}" = "assets" ] || exit 1
    ) || return 1

    # Optional install path when assets already contain a chip tree (host unit test).
    if [ -d "${PROJECT_DIR}/assets/wifibt/broadcom/AP6275S" ] &&
        [ -n "$(find "${PROJECT_DIR}/assets/wifibt/broadcom/AP6275S" -type f ! -name 'SOURCE.txt' ! -name 'README*' ! -name '*.md' 2>/dev/null | head -n 1)" ]; then
        (
            WIFIBT_CHIP="AP6275S"
            WIFIBT_SOURCE="assets"
            WIFIBT_REQUIRED="yes"
            tmp="$(mktemp -d)"
            install_wifibt_firmware "${tmp}"
            [ "${WIFIBT_RESOLVED_SOURCE}" = "assets" ] || exit 1
            [ "${WIFIBT_FILE_COUNT}" -gt 0 ] || exit 1
            [ -e "${tmp}/lib/firmware/fw_bcmdhd.bin" ] || [ -e "${tmp}/lib/firmware" ] || exit 1
            [ -L "${tmp}/vendor" ] || exit 1
            [ -L "${tmp}/system/etc/firmware" ] || exit 1
            rm -rf "${tmp}"
        ) || return 1
    fi

    if [ -d "${PROJECT_DIR}/assets/wifibt/aicsemi/AIC8800D80" ] &&
        [ -n "$(find "${PROJECT_DIR}/assets/wifibt/aicsemi/AIC8800D80" -type f ! -name 'SOURCE.txt' ! -name 'README*' ! -name '*.md' 2>/dev/null | head -n 1)" ]; then
        (
            WIFIBT_CHIP="AIC8800D80"
            WIFIBT_SOURCE="assets"
            WIFIBT_REQUIRED="yes"
            tmp="$(mktemp -d)"
            install_wifibt_firmware "${tmp}"
            [ "${WIFIBT_RESOLVED_SOURCE}" = "assets" ] || exit 1
            [ "${WIFIBT_FILE_COUNT}" -gt 0 ] || exit 1
            [ -f "${tmp}/lib/firmware/aic8800D80/fw_patch_table_8800d80_u02.bin" ] || exit 1
            [ -L "${tmp}/vendor" ] || exit 1
            [ -L "${tmp}/system/etc/firmware" ] || exit 1
            [ "$(readlink "${tmp}/vendor")" = "/system" ] || exit 1
            [ "$(readlink "${tmp}/system/etc/firmware")" = "/lib/firmware" ] || exit 1
            rm -rf "${tmp}"
        ) || return 1
    fi

    # Core overlay + plugin overlays (host unit test, no packages).
    (
        BOARD="rk3588-muse"
        BOARD_DESCRIPTION="overlay unit test"
        ROOTFS_HOSTNAME="muse"
        KERNEL_DTB="rk3588-muse.dtb"
        DEBIAN_PACKAGES="network-manager,wpasupplicant"
        CONSOLE_DEVICE="ttyFIQ0"
        CONSOLE_SPEED="1500000"
        resolve_debian_packages
        tmp="$(mktemp -d)"
        apply_debian_rootfs_overlays "${tmp}"
        install_serial_getty_baud_conf "${tmp}"
        # Simulate installed NetworkManager binary for the network plugin path.
        install -d "${tmp}/usr/sbin"
        : >"${tmp}/usr/sbin/NetworkManager"
        # shellcheck disable=SC1091
        source "${PROJECT_DIR}/rootfs/debian/plugins/10-firstboot-info.sh"
        plugin_apply "${tmp}"
        unset -f plugin_apply
        # shellcheck disable=SC1091
        source "${PROJECT_DIR}/rootfs/debian/plugins/network.sh"
        # enable_unit is defined by build_debian; stub for host test.
        enable_unit() { :; }
        plugin_apply "${tmp}"
        unset -f plugin_apply
        [ -x "${tmp}/usr/local/sbin/sbc-firstboot" ] || exit 1
        [ -x "${tmp}/usr/local/sbin/sbc-firstboot-info" ] || exit 1
        [ -f "${tmp}/etc/NetworkManager/conf.d/10-sbc.conf" ] || exit 1
        [ -f "${tmp}/etc/udev/rules.d/99-sbc-permissions.rules" ] || exit 1
        [ -f "${tmp}/etc/systemd/system/serial-getty@ttyFIQ0.service.d/10-baud.conf" ] || exit 1
        grep -Fq 'board=rk3588-muse' "${tmp}/usr/local/sbin/sbc-firstboot-info" || exit 1
        grep -Fq 'wifi.scan-rand-mac-address=no' \
            "${tmp}/etc/NetworkManager/conf.d/10-sbc.conf" || exit 1
        grep -Fq '1500000' \
            "${tmp}/etc/systemd/system/serial-getty@ttyFIQ0.service.d/10-baud.conf" || exit 1
        # networkd path when NetworkManager binary is absent
        tmp2="$(mktemp -d)"
        apply_debian_rootfs_overlays "${tmp2}"
        enable_unit() { :; }
        # shellcheck disable=SC1091
        source "${PROJECT_DIR}/rootfs/debian/plugins/network.sh"
        plugin_apply "${tmp2}"
        unset -f plugin_apply
        [ -f "${tmp2}/etc/systemd/network/20-wired.network" ] || exit 1
        [ ! -e "${tmp2}/etc/NetworkManager/conf.d/10-sbc.conf" ] || exit 1
    ) || return 1

    grep -Fq 'resolve_debian_packages' "${PROJECT_DIR}/scripts/build_debian.sh" || return 1
    grep -Fq 'install_firmware' "${PROJECT_DIR}/scripts/build_debian.sh" || return 1
    grep -Fq 'NetworkManager.service' "${PROJECT_DIR}/rootfs/debian/plugins/network.sh" || return 1
    grep -Fq 'DEBIAN_PACKAGES_DEFAULT' \
        "${PROJECT_DIR}/configs/boards/rk3588-muse.conf" || return 1
    grep -Fq 'WIFIBT_CHIP' "${PROJECT_DIR}/configs/boards/rk3588s-cokepi-model-lp4-v10.conf" || return 1
    [ -f "${PROJECT_DIR}/rootfs/debian/overlay/usr/local/sbin/sbc-firstboot" ] || return 1
    [ -f "${PROJECT_DIR}/rootfs/debian/overlay/etc/systemd/system/sbc-firstboot.service" ] || return 1
    [ -f "${PROJECT_DIR}/rootfs/debian/plugins/network/overlay-nm/etc/NetworkManager/conf.d/10-sbc.conf" ] || return 1
    [ -f "${PROJECT_DIR}/rootfs/debian/plugins/firstboot-info/overlay/usr/local/sbin/sbc-firstboot-info.in" ] || return 1
    grep -Fq 'wifi.scan-rand-mac-address=no' \
        "${PROJECT_DIR}/rootfs/debian/plugins/network/overlay-nm/etc/NetworkManager/conf.d/10-sbc.conf" || return 1
    grep -Fq 'apply_debian_rootfs_overlays' "${PROJECT_DIR}/scripts/lib/common.sh" || return 1
    if [ -f "${PROJECT_DIR}/Makefile" ] && [ -d "${PROJECT_DIR}/.git" ]; then
        grep -Fq 'sync-wifibt-assets' "${PROJECT_DIR}/Makefile" || return 1
    fi
    if [ -f "${PROJECT_DIR}/docker-compose.yml" ] && [ -d "${PROJECT_DIR}/.git" ]; then
        grep -Fq 'WIFIBT_CHIP' "${PROJECT_DIR}/docker-compose.yml" || return 1
    fi
}

check_board_profiles() {
    local profile board
    while IFS= read -r -d '' profile; do
        board="$(basename "${profile}" .conf)"
        (
            BOARD="${board}"
            load_board_profile
            [ "${BOOTLOADER_LAYOUT}" = "rockchip-gpt-idblock-extlinux-v1" ]
        ) || return 1
    done < <(find "${CONFIG_DIR}/boards" -maxdepth 1 -type f \
        -name '*.conf' ! -name 'TEMPLATE.conf' -print0)
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
    local dockerfile="${PROJECT_DIR}/Dockerfile"
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
        'export PYTHON="${UBOOT_PYTHON}"'
        'export PATH="${UBOOT_PYTHON_SHIM_DIR}:${PATH}"'
        'uboot_python=${UBOOT_PYTHON}'
        'bash ./make.sh --idblock "CROSS_COMPILE=${CROSS_COMPILE}"'
        'download_loader_format=LDR'
        'idblock_format=RKNS'
        boot_flow=rockchip-gpt-idblock-extlinux-v1
    )

    for marker in "${markers[@]}"; do
        grep -Fq "${marker}" "${script}" || return 1
    done

    grep -Fq 'ARG PYTHON2_VERSION=2.7.18' "${dockerfile}" || return 1
    grep -Fq 'ARG PYELFTOOLS_PY2_VERSION=0.27' "${dockerfile}" || return 1
    grep -Fq "python2 -c 'from elftools.elf.elffile import ELFFile'" \
        "${dockerfile}" || return 1
    grep -Fq 'python-is-python3' "${dockerfile}" || return 1
    grep -Fq "\"\${UBOOT_PYTHON}\" -c 'from elftools.elf.elffile import ELFFile'" \
        "${script}" || return 1
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
    # docker compose config fails on dynamic volume names (SDK_VOLUME is
    # created at runtime). Validate that the only issue is undefined volume,
    # not a real syntax or config error.
    local output errors
    output=$(SDK_VOLUME=rk3588-sdk-check docker compose -f "${PROJECT_DIR}/docker-compose.yml" config 2>&1 || true)
    errors=$(echo "${output}" | grep -v 'refers to undefined volume' | grep -iE 'error|invalid|syntax' || true)
    [ -z "${errors}" ]
}

run_check "Bash syntax" check_bash_syntax
if command -v shellcheck >/dev/null 2>&1; then
    run_check "ShellCheck" check_shellcheck
else
    log_warn "shellcheck not installed; skipping lint"
fi
run_check "Manifest XML and pinned source projects" check_manifests
run_check "Board profiles" check_board_profiles
run_check "Rock 5C pinned source contract" check_rock5c_source_contract
run_check "CokePi board profiles and SDK contract" check_cokepi_board_contract
run_check "Kernel boot and QEMU configuration contract" check_kernel_contract
run_check "Buildroot external tree" check_buildroot_external
run_check "U-Boot GPT/extlinux contract guard" check_uboot_boot_contract_guard
run_check "make help complete Rock 5C workflow" check_help_contract
run_check "Cross-host Debian builder contract" check_debian_builder_contract
run_check "Debian optional features" check_debian_features
run_check "Explicit rootfs configuration" check_rootfs_configuration
run_check "QEMU Debian smoke-test contract" check_qemu_smoke_contract
run_check "Failure-path self-tests" self_tests
if command -v docker >/dev/null 2>&1; then
    run_check "Docker Compose configuration" check_compose
else
    log_warn "docker not installed; skipping Compose validation"
fi

[ "${failures}" -eq 0 ] || die "${failures} project check(s) failed"
log_info "All available project checks passed"
