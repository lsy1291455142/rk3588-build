#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_board_profile
validate_board_source_revisions
ROOTFS=buildroot
require_cmd make openssl tar blkid debugfs e2fsck realpath

BUILDROOT_DIR="${SDK_DIR}/buildroot"
BUILDROOT_EXTERNAL="${ROOTFS_CONFIG_DIR}/buildroot"
COMMON_OUTPUT="$(board_common_output_dir)"
VARIANT_OUTPUT="$(variant_output_dir)"
BUILD_DIR="$(board_build_dir buildroot)"
MODULES_TAR="${COMMON_OUTPUT}/modules.tar"
KERNEL_RELEASE_FILE="${COMMON_OUTPUT}/kernel-release"
USERS_TABLE="${BUILD_DIR}/users.txt"
POST_BUILD_SCRIPT="${BUILD_DIR}/post-build.sh"
JOBS_RESOLVED="$(resolve_jobs)"
# ROOTFS_USERNAME / ROOTFS_PASSWORD defaults are applied by
# validate_rootfs_credentials() below; do not preset them here.

require_dir "${BUILDROOT_DIR}" "Buildroot source"
require_dir "${BUILDROOT_EXTERNAL}" "Buildroot external tree"
require_file "${BUILDROOT_EXTERNAL}/configs/rk3588_rootfs_defconfig" "Buildroot defconfig"
require_file "${MODULES_TAR}" "kernel modules archive; run build-kernel first"
require_file "${KERNEL_RELEASE_FILE}" "kernel release; run build-kernel first"
validate_rootfs_credentials

mkdir -p "${BUILD_DIR}" "${VARIANT_OUTPUT}"

PASSWORD_HASH="$(printf '%s\n' "${ROOTFS_PASSWORD}" | openssl passwd -6 -stdin)"
printf '%s -1 %s -1 %s /home/%s /bin/sh wheel %s\n' \
    "${ROOTFS_USERNAME}" "${ROOTFS_USERNAME}" "${PASSWORD_HASH}" \
    "${ROOTFS_USERNAME}" "${ROOTFS_USERNAME}" >"${USERS_TABLE}"

cp "${BUILDROOT_EXTERNAL}/board/rk3588/post-build.sh" "${POST_BUILD_SCRIPT}"
chmod 0755 "${POST_BUILD_SCRIPT}"

make_args=(
    -C "${BUILDROOT_DIR}"
    "O=${BUILD_DIR}"
    "BR2_EXTERNAL=${BUILDROOT_EXTERNAL}"
)

log_step "Configuring Buildroot for ${BOARD}"
make "${make_args[@]}" rk3588_rootfs_defconfig

export KERNEL_MODULES_TAR="${MODULES_TAR}"
export TARGET_USERNAME="${ROOTFS_USERNAME}"

log_step "Building Buildroot rootfs"
make "${make_args[@]}" -j"${JOBS_RESOLVED}" \
    "BR2_ROOTFS_USERS_TABLES=${USERS_TABLE}" \
    "BR2_ROOTFS_POST_BUILD_SCRIPT=${POST_BUILD_SCRIPT}" \
    "BR2_TARGET_GENERIC_ROOT_PASSWD=${ROOTFS_PASSWORD}" \
    "BR2_TARGET_ROOTFS_EXT2_SIZE=${ROOTFS_SIZE_MIB}M"

ROOTFS_IMAGE="${BUILD_DIR}/images/rootfs.ext4"
ROOTFS_TAR="${BUILD_DIR}/images/rootfs.tar"
require_file "${ROOTFS_IMAGE}" "Buildroot ext4 rootfs"
require_file "${ROOTFS_TAR}" "Buildroot rootfs tarball"

cp --sparse=always "${ROOTFS_IMAGE}" "${VARIANT_OUTPUT}/rootfs.ext4"
cp "${ROOTFS_TAR}" "${VARIANT_OUTPUT}/rootfs.tar"
install -m 0644 "${BUILD_DIR}/.config" "${VARIANT_OUTPUT}/buildroot.config"

[ "$(blkid -s LABEL -o value "${VARIANT_OUTPUT}/rootfs.ext4")" = "rootfs" ] ||
    die "Buildroot rootfs label is not rootfs"
e2fsck -fn "${VARIANT_OUTPUT}/rootfs.ext4"

KERNEL_RELEASE="$(cat "${KERNEL_RELEASE_FILE}")"
debugfs -R "stat /lib/modules/${KERNEL_RELEASE}" \
    "${VARIANT_OUTPUT}/rootfs.ext4" 2>&1 | grep -q 'Inode:' ||
    die "Buildroot rootfs does not contain modules for ${KERNEL_RELEASE}"
debugfs -R "cat /etc/passwd" "${VARIANT_OUTPUT}/rootfs.ext4" 2>/dev/null |
    grep -q "^${ROOTFS_USERNAME}:" ||
    die "Buildroot rootfs does not contain user ${ROOTFS_USERNAME}"
debugfs -R "cat /etc/shadow" "${VARIANT_OUTPUT}/rootfs.ext4" 2>/dev/null |
    grep -Eq '^root:[^!*:][^:]*:' ||
    die "Buildroot root account is not enabled"

write_common_metadata "${VARIANT_OUTPUT}/rootfs-build-info.txt" \
    "rootfs=buildroot" \
    "buildroot_revision=$(git_revision "${BUILDROOT_DIR}")" \
    "kernel_release=${KERNEL_RELEASE}" \
    "username=${ROOTFS_USERNAME}" \
    "root_login=enabled" \
    "rootfs_size_mib=${ROOTFS_SIZE_MIB}" \
    "jobs=${JOBS_RESOLVED}"

log_info "Buildroot rootfs: ${VARIANT_OUTPUT}/rootfs.ext4"
