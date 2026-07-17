#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_board_profile
validate_board_source_revisions
require_cmd make tar git install realpath

KERNEL_DIR="${SDK_DIR}/kernel"
KERNEL_FRAGMENT="${CONFIG_DIR}/kernel/rootfs-base.config"
COMMON_OUTPUT="$(board_common_output_dir)"
KERNEL_BUILD="$(board_build_dir kernel)"
MODULES_STAGE="${KERNEL_BUILD}/modules-stage"
JOBS_RESOLVED="$(resolve_jobs)"
CROSS_COMPILE="${CROSS_COMPILE-aarch64-linux-gnu-}"

require_dir "${KERNEL_DIR}" "kernel source"
require_file "${KERNEL_DIR}/arch/arm64/configs/${KERNEL_DEFCONFIG}" "kernel defconfig"
require_file "${KERNEL_FRAGMENT}" "kernel rootfs config fragment"
require_file "${KERNEL_DIR}/scripts/kconfig/merge_config.sh" "kernel merge_config.sh"

mkdir -p "${KERNEL_BUILD}" "${COMMON_OUTPUT}"

make_args=(
    -C "${KERNEL_DIR}"
    "O=${KERNEL_BUILD}"
    "ARCH=arm64"
    "CROSS_COMPILE=${CROSS_COMPILE}"
)

log_step "Configuring kernel for ${BOARD}"
make "${make_args[@]}" "${KERNEL_DEFCONFIG}"
(
    cd "${KERNEL_DIR}"
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

install -m 0644 "${KERNEL_IMAGE}" "${COMMON_OUTPUT}/Image"
install -m 0644 "${KERNEL_DTB_PATH}" "${COMMON_OUTPUT}/${KERNEL_DTB}"
install -m 0644 "${KERNEL_BUILD}/.config" "${COMMON_OUTPUT}/kernel.config"
printf '%s\n' "${KERNEL_RELEASE}" >"${COMMON_OUTPUT}/kernel-release"
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
    "cross_compile=${CROSS_COMPILE}" \
    "jobs=${JOBS_RESOLVED}"

log_info "Kernel artifacts: ${COMMON_OUTPUT}"
