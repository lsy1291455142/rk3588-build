#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_board_profile
validate_board_source_revisions
require_cmd make tar git install realpath ln fdtget fdtput

KERNEL_DIR="${SDK_DIR}/kernel"
KERNEL_FRAGMENT="${CONFIG_DIR}/kernel/rootfs-base.config"
COMMON_OUTPUT="$(board_common_output_dir)"
KERNEL_BUILD="$(board_build_dir kernel)"
KERNEL_SOURCE="$(board_build_dir kernel-source)"
MODULES_STAGE="${KERNEL_BUILD}/modules-stage"
JOBS_RESOLVED="$(resolve_jobs)"
CROSS_COMPILE="${CROSS_COMPILE-aarch64-linux-gnu-}"

require_dir "${KERNEL_DIR}" "kernel source"
require_file "${KERNEL_DIR}/arch/arm64/configs/${KERNEL_DEFCONFIG}" "kernel defconfig"
require_file "${KERNEL_FRAGMENT}" "kernel rootfs config fragment"
require_file "${KERNEL_DIR}/scripts/kconfig/merge_config.sh" "kernel merge_config.sh"

link_source_children() {
    local source="$1"
    local destination="$2"
    local path name excluded
    shift 2

    mkdir -p "${destination}"
    shopt -s dotglob nullglob
    for path in "${source}"/*; do
        name="${path##*/}"
        for excluded in "$@"; do
            if [ "${name}" = "${excluded}" ]; then
                continue 2
            fi
        done
        ln -s "${path}" "${destination}/${name}"
    done
    shopt -u dotglob nullglob
}

prepare_kernel_source_view() {
    safe_reset_dir "${KERNEL_SOURCE}" "${BUILD_BASE_DIR}/${BOARD}"

    # Some vendor kernels track generated ARM64 headers in Git. Kbuild rejects
    # any O= build when these paths exist, while mrproper would delete vendor
    # source files. Hide only Kbuild's three dirty-tree markers in a symlink
    # view and keep the imported SDK untouched.
    link_source_children "${KERNEL_DIR}" "${KERNEL_SOURCE}" \
        .config include arch
    link_source_children "${KERNEL_DIR}/include" "${KERNEL_SOURCE}/include" \
        config
    link_source_children "${KERNEL_DIR}/arch" "${KERNEL_SOURCE}/arch" \
        arm64
    link_source_children "${KERNEL_DIR}/arch/arm64" \
        "${KERNEL_SOURCE}/arch/arm64" include
    link_source_children "${KERNEL_DIR}/arch/arm64/include" \
        "${KERNEL_SOURCE}/arch/arm64/include" generated
}

prepare_kernel_source_view
mkdir -p "${KERNEL_BUILD}" "${COMMON_OUTPUT}"

# Kernel scripts/setlocalversion probes git for CONFIG_LOCALVERSION_AUTO.
# With O= builds the build directory is not a git worktree, so plain git
# discovery walks up to the Docker volume mount and prints:
#   fatal: not a git repository (or any parent up to mount point /home/builder)
# Pre-seed .scmversion in the source view so the kernel never needs to run git
# during the build, without creating files in the imported SDK source.
KERNEL_SCMVERSION_FILE="${KERNEL_SOURCE}/.scmversion"

if [ ! -e "${KERNEL_SCMVERSION_FILE}" ]; then
    kernel_rev="$(git_revision "${KERNEL_DIR}" | tr -d '\r\n')"
    if [[ "${kernel_rev}" =~ ^[0-9a-fA-F]{12,}$ ]]; then
        printf -- '-g%s\n' "${kernel_rev:0:12}" >"${KERNEL_SCMVERSION_FILE}"
    else
        : >"${KERNEL_SCMVERSION_FILE}"
    fi
fi

# Prevent accidental git discovery from crossing the SDK volume mount.
export GIT_CEILING_DIRECTORIES="${SDK_DIR}${GIT_CEILING_DIRECTORIES:+:${GIT_CEILING_DIRECTORIES}}"

# Several Rockchip driver Makefiles (for example drivers/video/rockchip/mpp)
# run bare "git log" while make is executing from the O= build directory.
# Point git at the kernel worktree so those probes work without noise.
kernel_git_dir="$(
    git -c safe.directory="${KERNEL_DIR}" -C "${KERNEL_DIR}" \
        rev-parse --absolute-git-dir 2>/dev/null || true
)"
if [ -n "${kernel_git_dir}" ]; then
    export GIT_DIR="${kernel_git_dir}"
    export GIT_WORK_TREE="${KERNEL_DIR}"
fi

make_args=(
    -C "${KERNEL_SOURCE}"
    "O=${KERNEL_BUILD}"
    "ARCH=arm64"
    "CROSS_COMPILE=${CROSS_COMPILE}"
    # Mark LOCALVERSION as set (empty) so setlocalversion will not fall back
    # to a short git probe when CONFIG_LOCALVERSION_AUTO is disabled.
    "LOCALVERSION="
)

log_step "Configuring kernel for ${BOARD}"
run_hook pre_build_kernel
make "${make_args[@]}" "${KERNEL_DEFCONFIG}"
(
    cd "${KERNEL_SOURCE}"
    ARCH=arm64 CROSS_COMPILE="${CROSS_COMPILE}" \
        scripts/kconfig/merge_config.sh -m -O "${KERNEL_BUILD}" \
        "${KERNEL_BUILD}/.config" "${KERNEL_FRAGMENT}"
)
make "${make_args[@]}" olddefconfig

# Rockchip's Bifrost driver embeds this firmware with an assembler .incbin
# path relative to the build directory, which needs mirroring for O= builds.
MALI_CSF_FIRMWARE="drivers/gpu/arm/bifrost/mali_csffw.bin"
if grep -qx 'CONFIG_MALI_CSF_INCLUDE_FW=y' "${KERNEL_BUILD}/.config"; then
    require_file "${KERNEL_DIR}/${MALI_CSF_FIRMWARE}" \
        "Mali CSF firmware required by CONFIG_MALI_CSF_INCLUDE_FW"
    install -D -m 0644 "${KERNEL_DIR}/${MALI_CSF_FIRMWARE}" \
        "${KERNEL_BUILD}/${MALI_CSF_FIRMWARE}"
fi

required_configs=(
    CONFIG_AUTOFS_FS=y
    CONFIG_CGROUPS=y
    CONFIG_DEVTMPFS=y
    CONFIG_DEVTMPFS_MOUNT=y
    CONFIG_EXT4_FS=y
    CONFIG_FHANDLE=y
    CONFIG_HW_RANDOM_VIRTIO=y
    CONFIG_MEMCG=y
    CONFIG_MMC_BLOCK=y
    CONFIG_NAMESPACES=y
    CONFIG_RTC_DRV_PL031=y
    CONFIG_SECCOMP=y
    CONFIG_SERIAL_AMBA_PL011=y
    CONFIG_SERIAL_AMBA_PL011_CONSOLE=y
    CONFIG_TMPFS=y
    CONFIG_TMPFS_POSIX_ACL=y
    CONFIG_TMPFS_XATTR=y
    CONFIG_UNIX=y
    CONFIG_VIRTIO=y
    CONFIG_VIRTIO_BLK=y
    CONFIG_VIRTIO_MMIO=y
    CONFIG_VIRTIO_NET=y
)
for required_config in "${required_configs[@]}"; do
    grep -qx "${required_config}" "${KERNEL_BUILD}/.config" ||
        die "Kernel configuration did not retain ${required_config}"
done

log_step "Building Image, ${KERNEL_DTB}, and modules"
make "${make_args[@]}" -j"${JOBS_RESOLVED}" \
    Image "rockchip/${KERNEL_DTB}" modules

safe_reset_dir "${MODULES_STAGE}" "${KERNEL_BUILD}"
make "${make_args[@]}" -j"${JOBS_RESOLVED}" \
    modules_install "INSTALL_MOD_PATH=${MODULES_STAGE}"

KERNEL_RELEASE="$(make "${make_args[@]}" -s kernelrelease)"
require_dir "${MODULES_STAGE}/lib/modules/${KERNEL_RELEASE}" "installed kernel modules"

find "${MODULES_STAGE}/lib/modules/${KERNEL_RELEASE}" -maxdepth 1 -type l \
    \( -name build -o -name source \) -delete

KERNEL_IMAGE="${KERNEL_BUILD}/arch/arm64/boot/Image"
KERNEL_DTB_PATH="${KERNEL_BUILD}/arch/arm64/boot/dts/rockchip/${KERNEL_DTB}"
require_file "${KERNEL_IMAGE}" "kernel Image"
require_file "${KERNEL_DTB_PATH}" "board DTB"

# Rockchip U-Boot merges /chosen/bootargs from the DTB after extlinux APPEND
# and replaces duplicate keys such as root=. Keep extlinux authoritative so
# the packaged image always boots the rootfs partition selected by its label.
# Controlled by DTB_STRIP_BOOTARGS in board profile (default: yes).
if [ "${DTB_STRIP_BOOTARGS:-yes}" = "yes" ]; then
    fdtget -l "${KERNEL_DTB_PATH}" / >/dev/null ||
        die "Built board DTB is invalid: ${KERNEL_DTB_PATH}"
    if fdtget -t s "${KERNEL_DTB_PATH}" /chosen bootargs >/dev/null 2>&1; then
        log_info "Removing /chosen/bootargs from packaged ${KERNEL_DTB}"
        fdtput -d "${KERNEL_DTB_PATH}" /chosen bootargs
    fi
    if fdtget -t s "${KERNEL_DTB_PATH}" /chosen bootargs >/dev/null 2>&1; then
        die "Packaged DTB still defines /chosen/bootargs: ${KERNEL_DTB_PATH}"
    fi
else
    log_info "DTB_STRIP_BOOTARGS=no; preserving /chosen/bootargs in ${KERNEL_DTB}"
fi

install -m 0644 "${KERNEL_IMAGE}" "${COMMON_OUTPUT}/Image"
install -m 0644 "${KERNEL_DTB_PATH}" "${COMMON_OUTPUT}/${KERNEL_DTB}"
install -m 0644 "${KERNEL_BUILD}/.config" "${COMMON_OUTPUT}/kernel.config"
printf '%s\n' "${KERNEL_RELEASE}" >"${COMMON_OUTPUT}/kernel-release"

if [ -n "${KERNEL_DTBO:-}" ]; then
    mkdir -p "${COMMON_OUTPUT}/overlays"
    for dtbo in ${KERNEL_DTBO}; do
        dtbo_src=""
        for candidate in "${KERNEL_BUILD}/arch/arm64/boot/dts/rockchip/overlay/${dtbo}" \
                         "${KERNEL_BUILD}/arch/arm64/boot/dts/rockchip/${dtbo}"; do
            if [ -f "${candidate}" ]; then
                dtbo_src="${candidate}"
                break
            fi
        done
        if [ -n "${dtbo_src}" ]; then
            install -m 0644 "${dtbo_src}" "${COMMON_OUTPUT}/overlays/${dtbo}"
            log_info "Installed DTBO overlay: ${dtbo}"
        else
            log_warn "KERNEL_DTBO specified ${dtbo} but file was not found under Kbuild output"
        fi
    done
fi
tar --numeric-owner --owner=0 --group=0 -C "${MODULES_STAGE}" \
    -cpf "${COMMON_OUTPUT}/modules.tar" lib

if [ -f "${KERNEL_BUILD}/System.map" ]; then
    install -m 0644 "${KERNEL_BUILD}/System.map" "${COMMON_OUTPUT}/System.map"
fi

write_common_metadata "${COMMON_OUTPUT}/kernel-build-info.txt" \
    "source_manifest=${SOURCE_MANIFEST:-}" \
    "kernel_revision=$(git_revision "${KERNEL_DIR}")" \
    "kernel_release=${KERNEL_RELEASE}" \
    "kernel_defconfig=${KERNEL_DEFCONFIG}" \
    "kernel_dtb=${KERNEL_DTB}" \
    "dtb_bootargs=extlinux-only-v1" \
    "kernel_source_view=symlink-clean-v1" \
    "cross_compile=${CROSS_COMPILE}" \
    "jobs=${JOBS_RESOLVED}"

log_info "Kernel artifacts: ${COMMON_OUTPUT}"
run_hook post_build_kernel
