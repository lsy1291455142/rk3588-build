#!/usr/bin/env bash
# Shared logging helpers for all build scripts and the container entrypoint.
# Source this file (it is never executed directly) and call the log_* helpers.
# Color codes are emitted only when stderr is a terminal, so piped/CI output
# stays free of escape sequences.

if [ -n "${_LOG_SH_SOURCED:-}" ]; then
    return
fi
_LOG_SH_SOURCED=1

if [ -t 2 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

log_info()  { printf '%s[INFO]%s %s\n'  "${GREEN}"  "${NC}" "$*" >&2; }
log_warn()  { printf '%s[WARN]%s %s\n'  "${YELLOW}" "${NC}" "$*" >&2; }
log_error() { printf '%s[ERROR]%s %s\n' "${RED}"    "${NC}" "$*" >&2; }
log_step()  { printf '%s[STEP]%s %s\n'  "${CYAN}"   "${NC}" "$*" >&2; }
