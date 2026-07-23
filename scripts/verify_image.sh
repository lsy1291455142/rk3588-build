#!/usr/bin/env bash
set -Eeuo pipefail

export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_board_profile
validate_board_source_revisions
validate_rootfs_choice
if [ "${ROOTFS}" = "debian" ]; then
    resolve_debian_release
fi

require_cmd sgdisk stat dd cmp mdir mcopy grep awk sed sha256sum \
    blkid e2fsck debugfs realpath fdtget
if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    require_cmd unsquashfs
fi

COMMON_OUTPUT="$(board_common_output_dir)"
VARIANT_OUTPUT="$(variant_output_dir)"
IMAGE_STEM="$(image_stem)"
IMAGE_PATH="${IMAGE_PATH:-${VARIANT_OUTPUT}/${IMAGE_STEM}.img}"
SHA256_PATH="${VARIANT_OUTPUT}/${IMAGE_STEM}.sha256"
KERNEL_IMAGE="${COMMON_OUTPUT}/Image"
DTB_IMAGE="${COMMON_OUTPUT}/${KERNEL_DTB}"
DOWNLOAD_LOADER_IMAGE="${COMMON_OUTPUT}/download-loader.bin"
IDBLOCK_IMAGE="${COMMON_OUTPUT}/idblock.img"
UBOOT_IMAGE="${COMMON_OUTPUT}/uboot.img"
if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    ROOTFS_IMAGE="${VARIANT_OUTPUT}/rootfs.squashfs"
    INITRD_IMAGE="${VARIANT_OUTPUT}/initrd.img"
else
    ROOTFS_IMAGE="${VARIANT_OUTPUT}/rootfs.ext4"
    INITRD_IMAGE=""
fi
KERNEL_RELEASE_FILE="${COMMON_OUTPUT}/kernel-release"
KERNEL_CONFIG="${COMMON_OUTPUT}/kernel.config"
KERNEL_BUILD_INFO="${COMMON_OUTPUT}/kernel-build-info.txt"
UBOOT_BUILD_INFO="${COMMON_OUTPUT}/uboot-build-info.txt"
ROOTFS_BUILD_INFO="${VARIANT_OUTPUT}/rootfs-build-info.txt"
IMAGE_BUILD_INFO="${VARIANT_OUTPUT}/image-build-info.txt"
ROOTFS_USERNAME="${ROOTFS_USERNAME:-rk3588}"

require_file "${IMAGE_PATH}" "raw disk image"
require_file "${SHA256_PATH}" "image checksum file"
require_file "${KERNEL_IMAGE}" "kernel Image"
require_file "${DTB_IMAGE}" "board DTB"
require_file "${DOWNLOAD_LOADER_IMAGE}" "download-loader.bin"
require_file "${IDBLOCK_IMAGE}" "idblock.img"
require_file "${UBOOT_IMAGE}" "uboot.img"
require_file "${ROOTFS_IMAGE}" "root filesystem image"
if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    require_file "${INITRD_IMAGE}" "initramfs"
fi
require_file "${KERNEL_RELEASE_FILE}" "kernel release"
require_file "${KERNEL_CONFIG}" "kernel configuration"
require_file "${KERNEL_BUILD_INFO}" "kernel build metadata"
require_file "${UBOOT_BUILD_INFO}" "U-Boot build metadata"
require_file "${ROOTFS_BUILD_INFO}" "rootfs build metadata"
require_file "${IMAGE_BUILD_INFO}" "image build metadata"

verify_extlinux_dtb() {
    local dtb="$1"
    local description="$2"

    fdtget -l "${dtb}" / >/dev/null ||
        die "${description} is not a valid DTB: ${dtb}"
    if fdtget -t s "${dtb}" /chosen bootargs >/dev/null 2>&1; then
        die "${description} defines /chosen/bootargs and can override extlinux"
    fi
}

verify_extlinux_dtb "${DTB_IMAGE}" "Board DTB artifact"
[ "$(metadata_value "${KERNEL_BUILD_INFO}" dtb_bootargs)" = \
    "extlinux-only-v1" ] ||
    die "Kernel metadata does not record the extlinux-only DTB contract"

if [ -n "${SOURCE_MANIFEST:-}" ]; then
    [ "$(metadata_value "${KERNEL_BUILD_INFO}" source_manifest)" = "${SOURCE_MANIFEST}" ] ||
        die "Kernel metadata does not identify ${SOURCE_MANIFEST}"
    [ "$(metadata_value "${KERNEL_BUILD_INFO}" kernel_revision)" = \
        "${EXPECTED_KERNEL_REVISION}" ] || die "Kernel metadata revision mismatch"
    [ "$(metadata_value "${UBOOT_BUILD_INFO}" uboot_revision)" = \
        "${EXPECTED_UBOOT_REVISION}" ] || die "U-Boot metadata revision mismatch"
    [ "$(metadata_value "${UBOOT_BUILD_INFO}" rkbin_revision)" = \
        "${EXPECTED_RKBIN_REVISION}" ] || die "rkbin metadata revision mismatch"
    [ "$(metadata_value "${IMAGE_BUILD_INFO}" buildroot_revision)" = \
        "${EXPECTED_BUILDROOT_REVISION}" ] || die "Buildroot metadata revision mismatch"
fi

for required_config in \
    CONFIG_AUTOFS_FS=y CONFIG_CGROUPS=y CONFIG_DEVTMPFS=y \
    CONFIG_DEVTMPFS_MOUNT=y CONFIG_EXT4_FS=y CONFIG_FHANDLE=y \
    CONFIG_HW_RANDOM_VIRTIO=y CONFIG_MEMCG=y CONFIG_MMC_BLOCK=y \
    CONFIG_NAMESPACES=y CONFIG_RTC_DRV_PL031=y CONFIG_SECCOMP=y \
    CONFIG_SERIAL_AMBA_PL011=y CONFIG_SERIAL_AMBA_PL011_CONSOLE=y \
    CONFIG_TMPFS=y CONFIG_TMPFS_POSIX_ACL=y CONFIG_TMPFS_XATTR=y \
    CONFIG_UNIX=y CONFIG_VIRTIO=y CONFIG_VIRTIO_BLK=y \
    CONFIG_VIRTIO_MMIO=y CONFIG_VIRTIO_NET=y; do
    grep -qx "${required_config}" "${KERNEL_CONFIG}" ||
        die "Kernel artifact lacks required configuration ${required_config}"
done

WORK_DIR="$(mktemp -d "${VARIANT_OUTPUT}/.image-verify.XXXXXX")"
trap 'rm -rf -- "${WORK_DIR}"' EXIT

IMAGE_SECTORS=$((IMAGE_SIZE_MIB * 2048))
BOOT_FIRST_EXPECTED=$((BOOT_START_MIB * 2048))
BOOT_LAST_EXPECTED=$((BOOT_FIRST_EXPECTED + BOOT_SIZE_MIB * 2048 - 1))
ROOT_FIRST_EXPECTED=$((BOOT_LAST_EXPECTED + 1))

# The embedded rootfs artifact (ext4 for rw-ext4, SquashFS for ro-overlay) drives
# the on-disk geometry. Mirror the formulas used by make_image.sh.
ROOTFS_BYTES="$(stat -c '%s' "${ROOTFS_IMAGE}")"
if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    # SquashFS root sized to the image plus 1 MiB slack; the data partition
    # (overlay upper + user data) starts after it and is sized by DATA_SIZE_MIB
    # or fills the rest of the disk.
    ROOT_MIB=$(((ROOTFS_BYTES + 1048575) / 1048576 + 1))
    ROOT_SECTORS=$((ROOT_MIB * 2048))
    ROOT_LAST_EXPECTED=$((ROOT_FIRST_EXPECTED + ROOT_SECTORS - 1))
    DATA_FIRST_EXPECTED=$((ROOT_LAST_EXPECTED + 1))
    if [ "${DATA_SIZE_MIB}" -gt 0 ]; then
        DATA_LAST_EXPECTED=$((DATA_FIRST_EXPECTED + DATA_SIZE_MIB * 2048 - 1))
    else
        DATA_LAST_EXPECTED=$((IMAGE_SECTORS - 34))
    fi
else
    ROOT_LAST_EXPECTED=$((IMAGE_SECTORS - 34))
fi

IMAGE_BYTES_EXPECTED=$((IMAGE_SIZE_MIB * 1024 * 1024))

[ "$(stat -c '%s' "${IMAGE_PATH}")" -eq "${IMAGE_BYTES_EXPECTED}" ] ||
    die "Unexpected image size: ${IMAGE_PATH}"
sgdisk --verify "${IMAGE_PATH}" >/dev/null

partition_field() {
    local partition="$1"
    local field="$2"
    sgdisk --info="${partition}" "${IMAGE_PATH}" |
        awk -F: -v wanted="${field}" '
            $1 == wanted {
                value = $2
                sub(/^[[:space:]]+/, "", value)
                print value
                exit
            }'
}

first_sector() {
    partition_field "$1" "First sector" | awk '{print $1}'
}

last_sector() {
    partition_field "$1" "Last sector" | awk '{print $1}'
}

partition_code() {
    sgdisk -p "${IMAGE_PATH}" 2>/dev/null | awk -v n="$1" '$1 == n {print $6}'
}

partition_name() {
    partition_field "$1" "Partition name" | sed "s/^'//;s/'$//"
}

[ "$(first_sector 1)" = "${BOOT_FIRST_EXPECTED}" ] ||
    die "Boot partition starts at the wrong sector"
[ "$(last_sector 1)" = "${BOOT_LAST_EXPECTED}" ] ||
    die "Boot partition ends at the wrong sector"
[ "$(partition_code 1)" = "0700" ] ||
    die "Boot partition type is not 0700"
[ "$(partition_name 1)" = "boot" ] ||
    die "Boot partition name is not boot"
[ "$(first_sector 2)" = "${ROOT_FIRST_EXPECTED}" ] ||
    die "Root partition starts at the wrong sector"
[ "$(last_sector 2)" = "${ROOT_LAST_EXPECTED}" ] ||
    die "Root partition ends at the wrong sector"
[ "$(partition_code 2)" = "8300" ] ||
    die "Root partition type is not 8300"
[ "$(partition_name 2)" = "rootfs" ] ||
    die "Root partition name is not rootfs"
if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    [ "$(first_sector 3)" = "${DATA_FIRST_EXPECTED}" ] ||
        die "Data partition starts at the wrong sector"
    [ "$(last_sector 3)" = "${DATA_LAST_EXPECTED}" ] ||
        die "Data partition ends at the wrong sector"
    [ "$(partition_code 3)" = "8300" ] ||
        die "Data partition type is not 8300"
    [ "$(partition_name 3)" = "data" ] ||
        die "Data partition name is not data"
fi

extract_bytes() {
    local source="$1"
    local destination="$2"
    local offset="$3"
    local count="$4"
    dd if="${source}" of="${destination}" bs=4M \
        iflag=skip_bytes,count_bytes skip="${offset}" count="${count}" \
        conv=sparse status=none
}

compare_embedded_file() {
    local expected="$1"
    local sector="$2"
    local extracted="$3"
    local size
    size="$(stat -c '%s' "${expected}")"
    extract_bytes "${IMAGE_PATH}" "${extracted}" "$((sector * 512))" "${size}"
    cmp --silent "${expected}" "${extracted}" ||
        die "Embedded data does not match $(basename "${expected}")"
}

read_image_magic() {
    dd if="$1" bs=1 count=4 status=none
}

bootloader_layout_verify "${IMAGE_PATH}" "${COMMON_OUTPUT}" "${WORK_DIR}"

BOOT_OFFSET=$((BOOT_FIRST_EXPECTED * 512))
MTOOLS_IMAGE="${IMAGE_PATH}@@${BOOT_OFFSET}"
mdir -i "${MTOOLS_IMAGE}" :: >/dev/null
mcopy -i "${MTOOLS_IMAGE}" ::/Image "${WORK_DIR}/Image"
mcopy -i "${MTOOLS_IMAGE}" "::/${KERNEL_DTB}" "${WORK_DIR}/${KERNEL_DTB}"
mcopy -i "${MTOOLS_IMAGE}" ::/extlinux/extlinux.conf "${WORK_DIR}/extlinux.conf"
cmp --silent "${KERNEL_IMAGE}" "${WORK_DIR}/Image" ||
    die "FAT Image does not match the kernel artifact"
cmp --silent "${DTB_IMAGE}" "${WORK_DIR}/${KERNEL_DTB}" ||
    die "FAT DTB does not match the board artifact"
verify_extlinux_dtb "${WORK_DIR}/${KERNEL_DTB}" "FAT DTB"
grep -Fqx "    FDT /${KERNEL_DTB}" "${WORK_DIR}/extlinux.conf" ||
    die "extlinux.conf does not select ${KERNEL_DTB}"
if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    mcopy -i "${MTOOLS_IMAGE}" ::/initrd.img "${WORK_DIR}/initrd.img"
    cmp --silent "${INITRD_IMAGE}" "${WORK_DIR}/initrd.img" ||
        die "FAT initrd.img does not match the initramfs artifact"
    grep -Fqx "    INITRD /initrd.img" "${WORK_DIR}/extlinux.conf" ||
        die "extlinux.conf does not load INITRD /initrd.img"
    grep -Fq "root=PARTLABEL=rootfs rootwait ro" "${WORK_DIR}/extlinux.conf" ||
        die "extlinux.conf does not boot read-only root=PARTLABEL=rootfs"
    grep -Fq "overlayroot=PARTLABEL=data" "${WORK_DIR}/extlinux.conf" ||
        die "extlinux.conf does not enable overlayroot=PARTLABEL=data"
else
    grep -Fq "root=PARTLABEL=rootfs rootwait rw" "${WORK_DIR}/extlinux.conf" ||
        die "extlinux.conf does not boot root=PARTLABEL=rootfs"
fi
grep -Fq "console=${CONSOLE}" "${WORK_DIR}/extlinux.conf" ||
    die "extlinux.conf does not configure ${CONSOLE}"

if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    extract_bytes "${IMAGE_PATH}" "${WORK_DIR}/rootfs.squashfs" \
        "$((ROOT_FIRST_EXPECTED * 512))" "${ROOTFS_BYTES}"
    cmp --silent "${ROOTFS_IMAGE}" "${WORK_DIR}/rootfs.squashfs" ||
        die "Embedded rootfs does not match rootfs.squashfs"
    [ "$(read_image_magic "${WORK_DIR}/rootfs.squashfs")" = "hsqs" ] ||
        die "Embedded root filesystem is not a SquashFS image"
else
    extract_bytes "${IMAGE_PATH}" "${WORK_DIR}/rootfs.ext4" \
        "$((ROOT_FIRST_EXPECTED * 512))" "${ROOTFS_BYTES}"
    cmp --silent "${ROOTFS_IMAGE}" "${WORK_DIR}/rootfs.ext4" ||
        die "Embedded rootfs does not match rootfs.ext4"
    e2fsck -fn "${WORK_DIR}/rootfs.ext4" >/dev/null
    [ "$(blkid -s LABEL -o value "${WORK_DIR}/rootfs.ext4")" = "rootfs" ] ||
        die "Embedded root filesystem label is not rootfs"
fi

# Content checks read files from the embedded rootfs. rw-ext4 exposes an ext4
# image (read via debugfs); ro-overlay exposes a SquashFS (extracted once, read
# via the filesystem path). The rf_* helpers abstract both representations.
if [ "${ROOTFS_MODE}" = "ro-overlay" ]; then
    # Extract the embedded SquashFS root. The verify container runs as root
    # (see Makefile _verify-one), so device nodes and ownership are preserved.
    unsquashfs -d "${WORK_DIR}/rootfs" "${WORK_DIR}/rootfs.squashfs" >/dev/null ||
        die "Unable to extract embedded SquashFS root filesystem"
    rf_cat()  { cat -- "${WORK_DIR}/rootfs$1" 2>/dev/null; }
    rf_exists() { [ -e "${WORK_DIR}/rootfs$1" ] || [ -L "${WORK_DIR}/rootfs$1" ]; }
    rf_is_symlink() { [ -L "${WORK_DIR}/rootfs$1" ]; }
    rf_owner_root() { [ "$(stat -c '%u:%g' "${WORK_DIR}/rootfs$1")" = "0:0" ]; }
else
    rf_cat()  { debugfs -R "cat $1" "${WORK_DIR}/rootfs.ext4" 2>/dev/null; }
    rf_exists() { debugfs -R "stat $1" "${WORK_DIR}/rootfs.ext4" 2>&1 | grep -q 'Inode:'; }
    rf_is_symlink() { debugfs -R "stat $1" "${WORK_DIR}/rootfs.ext4" 2>&1 | grep -q 'Type: symlink'; }
    rf_owner_root() { debugfs -R "stat $1" "${WORK_DIR}/rootfs.ext4" 2>&1 | grep -Eq 'User:[[:space:]]+0[[:space:]]+Group:[[:space:]]+0'; }
fi

KERNEL_RELEASE="$(cat "${KERNEL_RELEASE_FILE}")"
if [ "${ROOTFS}" = "buildroot" ]; then
    MODULES_DIR="/lib/modules/${KERNEL_RELEASE}"
else
    rf_cat /etc/debian_version | grep -Eq "^${DEBIAN_RELEASE}([.]|$)" ||
        die "Debian rootfs is not Debian ${DEBIAN_RELEASE}"
    MODULES_DIR="/usr/lib/modules/${KERNEL_RELEASE}"
fi
rf_exists "${MODULES_DIR}" ||
    die "Embedded rootfs lacks modules for ${KERNEL_RELEASE}"
rf_owner_root "${MODULES_DIR}" ||
    die "Embedded kernel modules are not owned by root"
rf_cat /etc/passwd | grep -q "^${ROOTFS_USERNAME}:" ||
    die "Embedded rootfs lacks user ${ROOTFS_USERNAME}"
rf_cat /etc/shadow | grep -Eq '^root:[^!*:][^:]*:' ||
    die "Embedded root account is not enabled"

if [ "${ROOTFS}" = "buildroot" ]; then
    rf_cat /etc/init.d/S02rootfs-resize | grep -Fq "resize2fs \"\$rootdev\"" ||
        die "Buildroot rootfs lacks the first-boot resize hook"
else
    rf_is_symlink /lib ||
        die "Debian rootfs lost the /lib usrmerge symlink"
    rf_exists /usr/lib/ld-linux-aarch64.so.1 ||
        die "Debian rootfs lacks the AArch64 ELF interpreter"
    rf_exists /usr/lib/systemd/systemd ||
        die "Debian rootfs lacks systemd init"

    ROOTFS_META="${VARIANT_OUTPUT}/rootfs-build-info.txt"
    NETWORK_STACK=""
    DEBIAN_PACKAGES_META=""
    DEBIAN_OVERLAYS_META=""
    if [ -f "${ROOTFS_META}" ]; then
        NETWORK_STACK="$(metadata_value "${ROOTFS_META}" network_stack || true)"
        DEBIAN_PACKAGES_META="$(metadata_value "${ROOTFS_META}" debian_packages || true)"
        DEBIAN_OVERLAYS_META="$(metadata_value "${ROOTFS_META}" debian_overlays || true)"
    fi
    # Back-compat: older images without debian_overlays metadata keep previous
    # full-attachment expectations.
    if [ -z "${DEBIAN_OVERLAYS_META}" ] && [ -f "${ROOTFS_META}" ]; then
        DEBIAN_OVERLAYS_META="base,console,firstboot,firstboot-info,network"
    fi
    overlay_enabled() {
        local want="$1"
        case ",${DEBIAN_OVERLAYS_META}," in
            *,"${want}",*) return 0 ;;
            *) return 1 ;;
        esac
    }

    if overlay_enabled firstboot; then
        rf_cat /usr/local/sbin/sbc-firstboot | grep -Fq "sgdisk -e \"\$rootdisk\"" ||
            die "Debian rootfs lacks the first-boot GPT repair"
        rf_cat /usr/local/sbin/sbc-firstboot | grep -Fq "partnum=\"\$(cat \"\$sys_block/partition\")\"" ||
            die "Debian rootfs does not derive the root partition from sysfs"
        rf_cat /usr/local/sbin/sbc-firstboot | grep -Fq "growpart \"\$rootdisk\" \"\$partnum\"" ||
            die "Debian rootfs lacks the first-boot partition growth"
        rf_cat /usr/local/sbin/sbc-firstboot | grep -Fq "resize2fs \"\$rootdev\"" ||
            die "Debian rootfs lacks the first-boot filesystem growth"
        rf_cat /etc/systemd/system/sbc-firstboot.service | grep -Fq 'WantedBy=multi-user.target' ||
            die "Debian rootfs lacks the first-boot resize service"
        if rf_cat /etc/systemd/system/sbc-firstboot.service | grep -Fq 'Before=ssh.service'; then
            die "Debian first-boot resize must not block SSH startup"
        fi
        rf_cat /etc/systemd/system/sbc-firstboot.service | grep -Fq 'TimeoutStartSec=10min' ||
            die "Debian first-boot resize service lacks a startup timeout"
        rf_cat /etc/systemd/system/sbc-firstboot.service | grep -Fq 'ExecStart=-/usr/local/sbin/sbc-firstboot' ||
            die "Debian first-boot resize failure can degrade system startup"
        rf_exists /etc/systemd/system/multi-user.target.wants/sbc-firstboot.service ||
            die "Debian rootfs does not enable sbc-firstboot.service"
        rf_exists /usr/sbin/sgdisk || die "Debian rootfs lacks sgdisk"
        rf_exists /usr/bin/growpart || die "Debian rootfs lacks growpart"
        if overlay_enabled firstboot-info ||
            rf_exists /usr/local/sbin/sbc-firstboot-info; then
            rf_cat /usr/local/sbin/sbc-firstboot | grep -Fq 'sbc-firstboot-info' ||
                die "Debian firstboot does not optionally invoke firstboot-info"
        fi
    fi

    if overlay_enabled base; then
        rf_cat /etc/systemd/system/ssh.service.d/10-hostkeys.conf | grep -Fq 'ExecStartPre=/usr/bin/ssh-keygen -A' ||
            die "Debian SSH service does not generate missing host keys"
        rf_exists /etc/systemd/system/multi-user.target.wants/ssh.service ||
            die "Debian rootfs does not enable ssh.service"
        if [ "${DEBIAN_RELEASE}" != "11" ]; then
            rf_exists /etc/systemd/system/sysinit.target.wants/systemd-resolved.service ||
                die "Debian rootfs does not enable systemd-resolved.service"
        fi
    fi

    if overlay_enabled console; then
        CONSOLE_SPEED="${CONSOLE#*,}"
        CONSOLE_SPEED="${CONSOLE_SPEED%%[!0-9]*}"
        rf_cat /etc/systemd/system/serial-getty@${CONSOLE%%,*}.service.d/10-baud.conf |
            grep -Fq -- "--keep-baud ${CONSOLE_SPEED},115200" ||
            die "Debian serial getty does not preserve the board console speed"
        rf_exists /etc/systemd/system/getty.target.wants/serial-getty@${CONSOLE%%,*}.service ||
            die "Debian rootfs does not enable serial-getty@${CONSOLE%%,*}.service"
    fi

    if overlay_enabled network; then
        if [ "${NETWORK_STACK}" = "NetworkManager" ] ||
            rf_exists /usr/sbin/NetworkManager; then
            NET_UNIT_PATH=/etc/systemd/system/multi-user.target.wants/NetworkManager.service
            rf_exists "${NET_UNIT_PATH}" || die "Debian rootfs does not enable NetworkManager"
            if rf_exists /etc/systemd/system/multi-user.target.wants/systemd-networkd.service; then
                die "Debian NetworkManager rootfs must not enable systemd-networkd"
            fi
        else
            NET_UNIT_PATH=/etc/systemd/system/multi-user.target.wants/systemd-networkd.service
            rf_exists "${NET_UNIT_PATH}" || die "Debian rootfs does not enable systemd-networkd"
        fi
    fi

    # Package presence checks use the recorded apt package list (exact names).
    case ",${DEBIAN_PACKAGES_META}," in
        *,i2c-tools,*)
            rf_exists /usr/sbin/i2cdetect || die "Debian rootfs with i2c-tools lacks i2cdetect"
            ;;
    esac
    case ",${DEBIAN_PACKAGES_META}," in
        *,wpasupplicant,*)
            rf_exists /usr/sbin/wpa_supplicant || die "Debian rootfs with wpasupplicant lacks binary"
            ;;
    esac

fi

(
    cd "${VARIANT_OUTPUT}"
    sha256sum --check "$(basename "${SHA256_PATH}")"
)

log_info "Image verification passed: ${IMAGE_PATH}"
