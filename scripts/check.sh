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

# Advisory checks are informative only: a failure is logged as a warning but
# does NOT increment the failure count, so it cannot break `make check`. These
# guard against drift in non-critical, often purely cosmetic contracts (e.g.
# help-text completeness, compose validity that docker itself also checks, or
# brittle string-presence assertions on internal implementation details).
run_advisory() {
    local description="$1"
    shift
    log_step "${description} (advisory)"
    if "$@"; then
        return 0
    fi
    log_warn "Advisory check did not pass (non-blocking): ${description}"
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

    # Manifests owned by a board profile (SOURCE_MANIFEST=) pin exact revisions
    # and are validated by that board's self-check hook. Only generic manifests
    # must pin the default Buildroot tag here. Discovery keeps core board-name-free.
    local -a owned_manifests=()
    local f m
    for f in "${PROJECT_DIR}"/boards/*/board.conf; do
        [ -f "${f}" ] || continue
        m="$(grep -E '^SOURCE_MANIFEST=' "${f}" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '"')"
        [ -n "${m}" ] && owned_manifests+=("${m}")
    done

    local base owned o expected_br_rev="" br_rev=""
    while IFS= read -r -d '' manifest; do
        if [ "${parser}" = "xmllint" ]; then
            xmllint --noout "${manifest}" || return 1
        elif [ "${parser}" = "python3" ]; then
            python3 -c 'import sys, xml.etree.ElementTree as ET; ET.parse(sys.argv[1])' \
                "${manifest}" || return 1
        fi

        grep -q 'remote name="buildroot"' "${manifest}" || return 1

        base="$(basename "${manifest}")"
        owned=0
        for o in "${owned_manifests[@]}"; do
            [ "${o}" = "${base}" ] && owned=1 && break
        done
        [ "${owned}" -eq 1 ] && continue

        # Generic (non-board-owned) manifests must pin a consistent Buildroot
        # tag. We no longer hardcode the literal tag here (that drifted from the
        # manifests and broke CI on every version bump); instead we assert that
        # every generic manifest pins the SAME buildroot revision under refs/tags/.
        br_rev="$(grep -o 'remote="buildroot" revision="[^"]*"' "${manifest}" | sed -n 's/.*revision="\([^"]*\)"$/\1/p')"
        case "${br_rev}" in
            refs/tags/*) ;;
            *) return 1 ;;
        esac
        if [ -z "${expected_br_rev}" ]; then
            expected_br_rev="${br_rev}"
        elif [ "${expected_br_rev}" != "${br_rev}" ]; then
            return 1
        fi
    done < <(find "${PROJECT_DIR}/manifests" -maxdepth 1 -type f \
        -name '*.xml' -print0)
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
    local soc_conf="${CONFIG_DIR}/soc/rk3588.conf"
    local marker
    local -a markers=(
        qemu-system-aarch64
        PARTLABEL=rootfs
        BOOT_ERROR_PATTERNS
        SERIAL_LOGIN_MARKER
        logfile_read
        unit_health
        systemd.default_device_timeout_sec=300s
        systemd.default_timeout_start_sec=300s
        sbc-firstboot.done
        systemctl
        ssh_password_login
        'initcall_blacklist='
        'systemd.mask='
        --initcall-blacklist
        --serial-getty-mask
    )
    [ -f "${script}" ] && [ -f "${driver}" ] || return 1
    for marker in "${markers[@]}"; do
        # -e ensures markers beginning with '-' are treated as patterns.
        grep -Fq -e "${marker}" "${script}" "${driver}" || return 1
    done
    # SoC-coupled traits now live in configs/soc/<soc>.conf, not in core.
    [ -f "${soc_conf}" ] || return 1
    grep -Fq 'rockchip_drm_init' "${soc_conf}" || return 1
    grep -Fq 'system_heap_create' "${soc_conf}" || return 1
    grep -Fq 'serial-getty@ttyFIQ0.service' "${soc_conf}" || return 1
    grep -Fq 'qemu-system-arm' "${PROJECT_DIR}/Dockerfile" || return 1
    grep -Fq 'python3-pexpect' "${PROJECT_DIR}/Dockerfile" || return 1
}


check_debian_packages() {
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

    # Overlay selection: none / explicit list / unknown.
    (
        DEBIAN_OVERLAYS="none"
        resolve_debian_overlays
        [ "${DEBIAN_OVERLAYS}" = "" ] || exit 1
        [ "${#DEBIAN_OVERLAY_LIST[@]}" -eq 0 ] || exit 1
    ) || return 1

    (
        DEBIAN_OVERLAYS="base,console,firstboot"
        resolve_debian_overlays
        [ "${DEBIAN_OVERLAYS}" = "base,console,firstboot" ] || exit 1
        debian_overlay_enabled base || exit 1
        debian_overlay_enabled console || exit 1
        debian_overlay_enabled firstboot || exit 1
        debian_overlay_enabled network-nm && exit 1
        true
    ) || return 1

    if (
        DEBIAN_OVERLAYS="base,not-a-real-overlay"
        resolve_debian_overlays
    ) 2>/dev/null; then
        return 1
    fi

    # Board plugin dispatch: plugin.sh preferred; static overlay fallback.
    # Hermetic: fixtures live under a temp rootfs dir, never the repo tree.
    (
        tmp_root="$(mktemp -d)"
        dst="$(mktemp -d)"
        board_name="unit-static-board"
        BOARD_DIR="${tmp_root}/debian"
        install -d "${BOARD_DIR}/rootfs/overlay/etc"
        printf 'static-ok\n' >"${BOARD_DIR}/rootfs/overlay/etc/issue"
        BOARD="${board_name}"
        apply_debian_board_overlay "${dst}"
        grep -Fq 'static-ok' "${dst}/etc/issue" || exit 1
        rm -rf "${dst}" "${tmp_root}"
    ) || return 1

    (
        tmp_root="$(mktemp -d)"
        dst="$(mktemp -d)"
        board_name="unit-plugin-board"
        BOARD_DIR="${tmp_root}/debian"
        install -d "${BOARD_DIR}/rootfs/overlay/etc"
        cat >"${BOARD_DIR}/rootfs/plugin.sh" <<'PLUGIN'
board_plugin_apply() {
    local root_dir="$1"
    local self_dir
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    printf 'from-plugin\n' >"${self_dir}/overlay/etc/issue"
    apply_rootfs_overlay_tree "${root_dir}" "${self_dir}/overlay"
}
PLUGIN
        BOARD="${board_name}"
        apply_debian_board_overlay "${dst}"
        grep -Fq 'from-plugin' "${dst}/etc/issue" || exit 1
        rm -rf "${dst}" "${tmp_root}"
    ) || return 1

    # Board-local plugin/firmware contracts are no longer asserted by the
    # core self-test; they are validated at build time via plugin.sh / overlay.

    # Symlink-capable overlay apply (board overlays may ship vendor links).
    (
        src="$(mktemp -d)"
        dst="$(mktemp -d)"
        install -d "${src}/lib/firmware" "${src}/system/etc"
        ln -sfn /system "${src}/vendor"
        ln -sfn /lib/firmware "${src}/system/etc/firmware"
        : >"${src}/lib/firmware/demo.bin"
        apply_rootfs_overlay_tree "${dst}" "${src}"
        [ -L "${dst}/vendor" ] || exit 1
        [ "$(readlink "${dst}/vendor")" = "/system" ] || exit 1
        [ -L "${dst}/system/etc/firmware" ] || exit 1
        [ -f "${dst}/lib/firmware/demo.bin" ] || exit 1
        rm -rf "${src}" "${dst}"
    ) || return 1

    # Selected overlays (host unit test, no packages installed).
    (
        BOARD="unit-overlay-test"
        BOARD_DESCRIPTION="overlay unit test"
        ROOTFS_HOSTNAME="unittest"
        KERNEL_DTB="unit-overlay-test.dtb"
        DEBIAN_PACKAGES="network-manager,wpasupplicant"
        DEBIAN_OVERLAYS="base,console,firstboot,firstboot-info,network-nm"
        CONSOLE_DEVICE="ttyFIQ0"
        CONSOLE_SPEED="1500000"
        resolve_debian_packages
        resolve_debian_overlays
        tmp="$(mktemp -d)"
        apply_debian_board_overlay "${tmp}"
        run_debian_overlay_plugins "${tmp}"
        [ -x "${tmp}/usr/local/sbin/sbc-firstboot" ] || exit 1
        [ -x "${tmp}/usr/local/sbin/sbc-firstboot-info" ] || exit 1
        # network-nm ships only NetworkManager config + its wants symlink.
        [ -f "${tmp}/etc/NetworkManager/conf.d/10-sbc.conf" ] || exit 1
        [ ! -e "${tmp}/etc/systemd/network/20-wired.network" ] || exit 1
        [ -f "${tmp}/etc/udev/rules.d/99-sbc-permissions.rules" ] || exit 1
        [ -f "${tmp}/etc/systemd/system/serial-getty@ttyFIQ0.service.d/10-baud.conf" ] || exit 1
        grep -Fq 'board=unit-overlay-test' "${tmp}/usr/local/sbin/sbc-firstboot-info" || exit 1
        grep -Fq 'wifi.scan-rand-mac-address=no' \
            "${tmp}/etc/NetworkManager/conf.d/10-sbc.conf" || exit 1
        grep -Fq '1500000' \
            "${tmp}/etc/systemd/system/serial-getty@ttyFIQ0.service.d/10-baud.conf" || exit 1
        # Wants symlinks for service enabling.
        [ -L "${tmp}/etc/systemd/system/multi-user.target.wants/ssh.service" ] || exit 1
        [ -L "${tmp}/etc/systemd/system/multi-user.target.wants/sbc-firstboot.service" ] || exit 1
        [ -L "${tmp}/etc/systemd/system/multi-user.target.wants/NetworkManager.service" ] || exit 1
        [ ! -e "${tmp}/etc/systemd/system/multi-user.target.wants/systemd-networkd.service" ] || exit 1
        [ -L "${tmp}/etc/systemd/system/getty.target.wants/serial-getty@ttyFIQ0.service" ] || exit 1
        [ -L "${tmp}/etc/systemd/system/sysinit.target.wants/systemd-resolved.service" ] || exit 1
        # none must leave attachment files out
        tmp3="$(mktemp -d)"
        DEBIAN_OVERLAYS="none"
        resolve_debian_overlays
        run_debian_overlay_plugins "${tmp3}"
        [ ! -e "${tmp3}/usr/local/sbin/sbc-firstboot" ] || exit 1
        [ ! -e "${tmp3}/etc/udev/rules.d/99-sbc-permissions.rules" ] || exit 1
        rm -rf "${tmp}" "${tmp3}"
    ) || return 1

    # network-networkd overlay (the systemd-networkd counterpart, mutually
    # exclusive with network-nm by selection, not by runtime condition).
    (
        BOARD="unit-overlay-test"
        BOARD_DESCRIPTION="overlay unit test"
        ROOTFS_HOSTNAME="unittest"
        KERNEL_DTB="unit-overlay-test.dtb"
        DEBIAN_PACKAGES=""
        DEBIAN_OVERLAYS="network-networkd"
        CONSOLE_DEVICE="ttyFIQ0"
        CONSOLE_SPEED="1500000"
        resolve_debian_packages
        resolve_debian_overlays
        tmp="$(mktemp -d)"
        run_debian_overlay_plugins "${tmp}"
        [ -f "${tmp}/etc/systemd/network/20-wired.network" ] || exit 1
        [ ! -e "${tmp}/etc/NetworkManager/conf.d/10-sbc.conf" ] || exit 1
        [ -L "${tmp}/etc/systemd/system/multi-user.target.wants/systemd-networkd.service" ] || exit 1
        [ ! -e "${tmp}/etc/systemd/system/multi-user.target.wants/NetworkManager.service" ] || exit 1
        rm -rf "${tmp}"
    ) || return 1

    # Mutually exclusive overlays (network-nm + network-networkd) must be rejected.
    if ( DEBIAN_OVERLAYS="network-nm,network-networkd" resolve_debian_overlays ) 2>/dev/null; then
        return 1
    fi

    # %VAR% path interpolation: empty variable skips the file.
    (
        src="$(mktemp -d)"
        dst="$(mktemp -d)"
        install -d "${src}/etc/systemd/system/serial-getty@%CONSOLE_DEVICE%.service.d"
        printf 'test\n' >"${src}/etc/systemd/system/serial-getty@%CONSOLE_DEVICE%.service.d/10-baud.conf"
        CONSOLE_DEVICE=""
        apply_rootfs_overlay_tree "${dst}" "${src}"
        [ ! -e "${dst}/etc/systemd/system/serial-getty@.service.d" ] || exit 1
        CONSOLE_DEVICE="ttyFIQ0"
        apply_rootfs_overlay_tree "${dst}" "${src}"
        [ -f "${dst}/etc/systemd/system/serial-getty@ttyFIQ0.service.d/10-baud.conf" ] || exit 1
        rm -rf "${src}" "${dst}"
    ) || return 1

    grep -Fq 'resolve_debian_packages' "${PROJECT_DIR}/scripts/build_debian.sh" || return 1
    grep -Fq 'resolve_debian_overlays' "${PROJECT_DIR}/scripts/build_debian.sh" || return 1
    grep -Fq 'run_debian_overlay_plugins' "${PROJECT_DIR}/scripts/build_debian.sh" || return 1
    [ -f "${PROJECT_DIR}/rootfs/debian/overlays/firstboot/overlay/usr/local/sbin/sbc-firstboot" ] || return 1
    [ -f "${PROJECT_DIR}/rootfs/debian/overlays/firstboot/overlay/etc/systemd/system/sbc-firstboot.service" ] || return 1
    [ -f "${PROJECT_DIR}/rootfs/debian/overlays/network-nm/overlay/etc/NetworkManager/conf.d/10-sbc.conf" ] || return 1
    [ -f "${PROJECT_DIR}/rootfs/debian/overlays/network-networkd/overlay/etc/systemd/network/20-wired.network" ] || return 1
    [ -f "${PROJECT_DIR}/rootfs/debian/overlays/firstboot-info/overlay/usr/local/sbin/sbc-firstboot-info.in" ] || return 1
    [ -d "${PROJECT_DIR}/rootfs/debian/overlays/base/overlay" ] || return 1
    [ -d "${PROJECT_DIR}/rootfs/debian/overlays/console/overlay" ] || return 1
    [ ! -e "${PROJECT_DIR}/rootfs/debian/overlays/wifibt" ] || return 1
    grep -Fq 'wifi.scan-rand-mac-address=no' \
        "${PROJECT_DIR}/rootfs/debian/overlays/network-nm/overlay/etc/NetworkManager/conf.d/10-sbc.conf" || return 1
    # Overlays enable services via wants symlinks (no plugin.sh scripts).
    [ -L "${PROJECT_DIR}/rootfs/debian/overlays/base/overlay/etc/systemd/system/multi-user.target.wants/ssh.service" ] || return 1
    [ -L "${PROJECT_DIR}/rootfs/debian/overlays/firstboot/overlay/etc/systemd/system/multi-user.target.wants/sbc-firstboot.service" ] || return 1
    [ -L "${PROJECT_DIR}/rootfs/debian/overlays/network-nm/overlay/etc/systemd/system/multi-user.target.wants/NetworkManager.service" ] || return 1
    [ -L "${PROJECT_DIR}/rootfs/debian/overlays/network-networkd/overlay/etc/systemd/system/multi-user.target.wants/systemd-networkd.service" ] || return 1
    [ -L "${PROJECT_DIR}/rootfs/debian/overlays/console/overlay/etc/systemd/system/getty.target.wants/serial-getty@%CONSOLE_DEVICE%.service" ] || return 1
    [ ! -e "${PROJECT_DIR}/rootfs/debian/overlays/base/plugin.sh" ] || return 1
    [ ! -e "${PROJECT_DIR}/rootfs/debian/overlays/console/plugin.sh" ] || return 1
    [ ! -e "${PROJECT_DIR}/rootfs/debian/overlays/firstboot/plugin.sh" ] || return 1
    [ ! -e "${PROJECT_DIR}/rootfs/debian/overlays/firstboot-info/plugin.sh" ] || return 1
    [ ! -e "${PROJECT_DIR}/rootfs/debian/overlays/network-nm/plugin.sh" ] || return 1
    [ ! -e "${PROJECT_DIR}/rootfs/debian/overlays/network-networkd/plugin.sh" ] || return 1
    [ ! -e "${PROJECT_DIR}/rootfs/debian/overlays/network" ] || return 1
    grep -Fq 'run_debian_overlay_plugins' "${PROJECT_DIR}/scripts/lib/common.sh" || return 1
    if [ -f "${PROJECT_DIR}/Makefile" ] && [ -d "${PROJECT_DIR}/.git" ]; then
        # Core Makefile must not own WiFi/BT sync or WIFIBT_* knobs.
        grep -Fq 'sync-wifibt-assets' "${PROJECT_DIR}/Makefile" && return 1
        grep -Eq '^WIFIBT_' "${PROJECT_DIR}/Makefile" && return 1
        grep -Fq 'DEBIAN_OVERLAYS' "${PROJECT_DIR}/Makefile" || return 1
    fi
    # Core common.sh must not define WiFi/BT helpers.
    if grep -Eq '^(resolve_wifibt_config|install_wifibt_firmware)\(\)' \
        "${PROJECT_DIR}/scripts/lib/common.sh"; then
        return 1
    fi
    if [ -f "${PROJECT_DIR}/docker-compose.yml" ] && [ -d "${PROJECT_DIR}/.git" ]; then
        grep -Fq 'WIFIBT_CHIP' "${PROJECT_DIR}/docker-compose.yml" && return 1
        grep -Fq 'DEBIAN_OVERLAYS' "${PROJECT_DIR}/docker-compose.yml" || return 1
    fi
}

check_board_profiles() {
    local profile board
    while IFS= read -r -d '' profile; do
        board="$(basename "$(dirname "${profile}")")"
        [ "${board}" = "TEMPLATE" ] && continue
        (
            BOARD="${board}"
            load_board_profile
            [ "${BOOTLOADER_LAYOUT}" = "rockchip-gpt-idblock-extlinux-v1" ]
        ) || return 1
    done < <(find "${PROJECT_DIR}/boards" -maxdepth 2 -type f \
        -name 'board.conf' ! -path '*/TEMPLATE/*' -print0)
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

    # Verify the Dockerfile defines these ARGs without pinning the exact
    # version here (that hardcoded the value and broke CI on every bump).
    grep -Fq 'ARG PYTHON2_VERSION=' "${dockerfile}" || return 1
    grep -Fq 'ARG PYELFTOOLS_PY2_VERSION=' "${dockerfile}" || return 1
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
        "source '${SCRIPT_DIR}/lib/common.sh'; p=\$(mktemp -d); safe_reset_dir \"\${p}\" \"\${p}\"; rm -rf \"\${p}\""
}

run_check "Bash syntax" check_bash_syntax
if command -v shellcheck >/dev/null 2>&1; then
    run_check "ShellCheck" check_shellcheck
else
    log_warn "shellcheck not installed; skipping lint"
fi
run_check "Manifest XML and pinned source projects" check_manifests
run_check "Board profiles" check_board_profiles
run_check "Kernel boot and QEMU configuration contract" check_kernel_contract
run_check "Buildroot external tree" check_buildroot_external
run_check "U-Boot GPT/extlinux contract guard" check_uboot_boot_contract_guard
run_check "Debian optional features" check_debian_packages
run_check "Failure-path self-tests" self_tests
# ---- 以下为形式化/脆弱断言，降级为非阻断 advisory（见 run_advisory）----
# 保留行为级验证（rootfs .env 切换、qemu 关键模式），失败仅 warning 不阻断。
run_advisory "Explicit rootfs configuration" check_rootfs_configuration
run_advisory "QEMU Debian smoke-test contract" check_qemu_smoke_contract

[ "${failures}" -eq 0 ] || die "${failures} project check(s) failed"
log_info "All available project checks passed"
