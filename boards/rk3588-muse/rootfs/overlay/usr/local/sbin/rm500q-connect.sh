#!/usr/bin/env bash
# =============================================================================
# rm500q-connect — RM500Q-GL 5G modem connection manager
# =============================================================================
# Usage:
#   rm500q-connect status       Show modem status
#   rm500q-connect connect [APN] Establish data connection
#   rm500q-connect disconnect   Close data connection
#   rm500q-connect detect       Check if modem is present
#   rm500q-connect at "CMD"     Send raw AT command
#
# Environment overrides (see lib-rm500q.sh for full list):
#   RM500Q_AT_PORT, RM500Q_DATA_IFACE, RM500Q_APN, RM500Q_AT_TIMEOUT
# =============================================================================
set -Eeuo pipefail

# Source runtime library
LIB_PATH="/usr/local/lib/rm500q.sh"
if [ ! -f "${LIB_PATH}" ]; then
    # Fallback for development/testing (board tree source)
    SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    LIB_PATH="${SELF_DIR}/../lib/rm500q.sh"
fi
# shellcheck source=rm500q.sh
source "${LIB_PATH}"

# -----------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: rm500q-connect <command> [args]

Commands:
  status                 Show full modem status
  connect [APN]          Establish data connection via quectel-CM (default APN: ${RM500Q_APN})
  disconnect             Close data connection (stop quectel-CM)
  detect                 Check if modem is present on PCIe
  at "AT+CMD"            Send raw AT command and show response
  registration           Check network registration status
  signal                 Show signal quality
  cell                   Show serving cell info

Data connection is managed by quectel-CM (QMI over PCIe/MHI).
AT commands are used only for status/signal/registration queries.

Environment:
  RM500Q_AT_PORT         AT command device (default: /dev/mhi_DUN)
  RM500Q_DATA_IFACE      Data interface (default: rmnet_mhi0.1)
  RM500Q_APN             APN (default: cmnet)
  RM500Q_AT_TIMEOUT      AT timeout seconds (default: 5)
  RM500Q_CM_BIN          quectel-CM binary (default: /usr/local/sbin/quectel-CM)
  RM500Q_CM_LOG          quectel-CM log file (default: /var/log/quectel-CM.log)
EOF
}

# -----------------------------------------------------------------------------
main() {
    local cmd="${1:-}"
    shift || true

    case "${cmd}" in
        status)
            rm500q_status
            ;;
        connect)
            rm500q_connect "${1:-}"
            ;;
        disconnect)
            rm500q_disconnect
            ;;
        detect)
            if rm500q_detect; then
                echo "RM500Q-GL: detected"
                lspci -nn 2>/dev/null | grep "17cb:" || true
                exit 0
            else
                echo "RM500Q-GL: not detected"
                exit 1
            fi
            ;;
        at)
            if [ -z "${1:-}" ]; then
                echo "Error: AT command required" >&2
                usage >&2
                exit 2
            fi
            rm500q_at_send "$1"
            ;;
        registration)
            rm500q_check_registration
            ;;
        signal)
            rm500q_signal_quality
            ;;
        cell)
            rm500q_serving_cell
            ;;
        help|--help|-h|"")
            usage
            ;;
        *)
            echo "Unknown command: ${cmd}" >&2
            usage >&2
            exit 2
            ;;
    esac
}

main "$@"
