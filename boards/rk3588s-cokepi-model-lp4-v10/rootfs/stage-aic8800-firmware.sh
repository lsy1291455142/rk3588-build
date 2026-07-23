#!/usr/bin/env bash
# Optional host helper: stage Radxa aic8800-firmware into this board overlay.
# Rootfs build does NOT need this: board plugin installs from packages/*.deb
# (or pre-staged overlay) directly into the rootfs without writing the board tree
# (docker mounts rootfs/:ro).
#
# Usage (on a writable host checkout):
#   ./boards/rk3588s-cokepi-model-lp4-v10/rootfs/stage-aic8800-firmware.sh
#   ./boards/rk3588s-cokepi-model-lp4-v10/rootfs/stage-aic8800-firmware.sh /path/or/url.deb
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-aic8800.sh
source "${SELF_DIR}/lib-aic8800.sh"
stage_aic8800_firmware "${SELF_DIR}" "${1:-}"
