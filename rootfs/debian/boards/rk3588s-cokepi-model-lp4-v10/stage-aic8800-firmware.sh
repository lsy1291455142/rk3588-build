#!/usr/bin/env bash
# Optional manual helper: stage Radxa aic8800-firmware into this board overlay.
# Rootfs build already runs this via boards/<board>/plugin.sh; use the CLI to
# refresh firmware or pin a different deb without rebuilding immediately.
#
# Usage:
#   ./rootfs/debian/boards/rk3588s-cokepi-model-lp4-v10/stage-aic8800-firmware.sh
#   ./rootfs/debian/boards/rk3588s-cokepi-model-lp4-v10/stage-aic8800-firmware.sh /path/or/url.deb
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-aic8800.sh
source "${SELF_DIR}/lib-aic8800.sh"
stage_aic8800_firmware "${SELF_DIR}" "${1:-}"
