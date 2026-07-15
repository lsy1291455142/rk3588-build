#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_board_profile
require_cmd make tar git realpath

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

for required_config in CONFIG_DEVTMPFS=y CONFIG_EXT4_FS=y CONFIG_MMC_BLOCK=y; do
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
tar --numeric-owner -C "${MODULES_STAGE}" -cpf "${COMMON_OUTPUT}/modules.tar" lib

if [ -f "${KERNEL_BUILD}/System.map" ]; then
    install -m 0644 "${KERNEL_BUILD}/System.map" "${COMMON_OUTPUT}/System.map"
fi

write_common_metadata "${COMMON_OUTPUT}/kernel-build-info.txt" \
    "kernel_revision=$(git_revision "${KERNEL_DIR}")" \
    "kernel_release=${KERNEL_RELEASE}" \
    "kernel_defconfig=${KERNEL_DEFCONFIG}" \
    "kernel_dtb=${KERNEL_DTB}" \
    "cross_compile=${CROSS_COMPILE}" \
    "jobs=${JOBS_RESOLVED}"

log_info "Kernel artifacts: ${COMMON_OUTPUT}"
