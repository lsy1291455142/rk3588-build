#!/usr/bin/env bash
# Optional host helper: stage Radxa aic8800-firmware into this board overlay.
# Rootfs build does NOT need this: board plugin installs from packages/*.deb
# (or pre-staged overlay) directly into the rootfs without writing the board tree
# (docker mounts rootfs/:ro).
#
# Usage (on a writable host checkout):
#   ./boards/rk3588-muse/rootfs/stage-fcu761k-firmware.sh
#   ./boards/rk3588-muse/rootfs/stage-fcu761k-firmware.sh /path/or/url.deb
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-fcu761k.sh
source "${SELF_DIR}/lib-fcu761k.sh"
stage_fcu761k_firmware "${SELF_DIR}" "${1:-}"
