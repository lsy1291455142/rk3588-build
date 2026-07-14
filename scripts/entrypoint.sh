#!/bin/bash
# =============================================================================
# RK3588 Docker 容器入口脚本
# 支持自动拉取源码、交互式 Shell
# =============================================================================

set -e

# ---- 颜色输出 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "${CYAN}[STEP]${NC}  $*"; }

# ---- 环境变量默认值 ----
SDK_DIR="${SDK_DIR:-/home/builder/sdk}"
BSP_SOURCE="${BSP_SOURCE:-rockchip}"       # rockchip | firefly | radxa | orangepi
BRANCH="${BRANCH:-stable-5.10}"             # 内核分支
FETCH_ON_START="${FETCH_ON_START:-no}"      # 容器启动时是否自动拉取
JOBS="${JOBS:-$(nproc)}"                    # 编译并行数

export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

# ---- 显示环境信息 ----
show_banner() {
    local HOST_ARCH=$(dpkg --print-architecture 2>/dev/null || echo "unknown")
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║           RK3588 Linux BSP Build Environment            ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    echo "║  宿主机架构  : ${HOST_ARCH}"
    echo "║  BSP Source  : ${BSP_SOURCE}"
    echo "║  Branch      : ${BRANCH}"
    echo "║  SDK Dir     : ${SDK_DIR}"
    echo "║  Cross Compile: ${CROSS_COMPILE}"
    echo "║  目标架构    : arm64 (RK3588)"
    echo "║  Jobs        : ${JOBS}"
    echo "║  Fetch on Start: ${FETCH_ON_START}"
    if [ "${HOST_ARCH}" = "amd64" ]; then
    echo "║  i386 兼容   : 已启用 (Rockchip 工具)"
    else
    echo "║  i386 兼容   : 不适用 (非 x86_64)"
    fi
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
}

# ---- 检查源码是否已拉取 ----
check_sdk() {
    if [ -d "${SDK_DIR}/kernel" ] && [ -d "${SDK_DIR}/u-boot" ]; then
        log_info "SDK 源码已存在: ${SDK_DIR}"
        return 0
    else
        log_warn "SDK 源码尚未拉取"
        return 1
    fi
}

# ---- 主逻辑 ----
show_banner

if [ "${FETCH_ON_START}" = "yes" ]; then
    log_step "自动拉取源码 (BSP_SOURCE=${BSP_SOURCE}, BRANCH=${BRANCH})"
    if [ -f "/home/builder/fetch_sources.sh" ]; then
        /home/builder/fetch_sources.sh
    else
        log_error "fetch_sources.sh 不存在，跳过拉取"
    fi
else
    check_sdk || log_warn "提示: 设置 FETCH_ON_START=yes 或手动运行 fetch_sources.sh"
fi

log_info "环境准备就绪，进入 Shell"

# 执行传入的命令 (默认 /bin/bash)
exec "$@"
