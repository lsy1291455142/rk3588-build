#!/bin/bash
# =============================================================================
# RK3588 Docker 容器入口脚本
# 支持自动拉取 SDK、交互式 Shell、ARM64 原生编译切换
# =============================================================================

set -e

# ---- 颜色输出 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "${CYAN}[STEP]${NC}  $*" >&2; }

# ---- 环境变量默认值 ----
SDK_DIR="${SDK_DIR:-/home/builder/sdk}"
MANIFEST="${MANIFEST:-}"                     # manifest 文件名, 留空则交互选择
FETCH_ON_START="${FETCH_ON_START:-no}"       # 容器启动时是否自动拉取
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"  # 编译并行数
USE_NATIVE_BUILD="${USE_NATIVE_BUILD:-no}"  # ARM64 原生编译

# ---- 配置交叉编译环境 ----
setup_compiler() {
    local HOST_ARCH
    HOST_ARCH=$(dpkg --print-architecture 2>/dev/null || echo "unknown")

    if [ "${USE_NATIVE_BUILD}" = "yes" ] && [ "${HOST_ARCH}" = "arm64" ]; then
        # ARM64 宿主机: 使用原生 GCC (比交叉编译更快)
        export CROSS_COMPILE=""
        export CC="gcc"
        export CXX="g++"
        log_info "编译模式: ARM64 原生编译 (加速)"
    else
        # 默认: 使用交叉编译 (所有架构通用)
        export CROSS_COMPILE=aarch64-linux-gnu-
        if [ "${USE_NATIVE_BUILD}" = "yes" ] && [ "${HOST_ARCH}" != "arm64" ]; then
            log_warn "USE_NATIVE_BUILD=yes 仅在 ARM64 宿主机有效, 当前架构: ${HOST_ARCH}, 回退到交叉编译"
        fi
    fi
    export ARCH=arm64
}

# ---- 配置 ccache ----
setup_ccache() {
    if command -v ccache &>/dev/null; then
        export PATH="/usr/lib/ccache:${PATH}"
        export CCACHE_DIR="${CCACHE_DIR:-/home/builder/.ccache}"
        export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-10G}"
        log_info "ccache 已启用 (最大: ${CCACHE_MAXSIZE})"
    fi
}

# ---- 显示环境信息 ----
show_banner() {
    local HOST_ARCH
    HOST_ARCH=$(dpkg --print-architecture 2>/dev/null || echo "unknown")

    local manifest_display="${MANIFEST:-交互选择}"
    local compiler_display
    if [ "${USE_NATIVE_BUILD}" = "yes" ] && [ "${HOST_ARCH}" = "arm64" ]; then
        compiler_display="原生 GCC (加速)"
    else
        compiler_display="aarch64-linux-gnu- (交叉编译)"
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║           RK3588 Linux BSP Build Environment            ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    echo "║  宿主机架构   : ${HOST_ARCH}"
    echo "║  Manifest    : ${manifest_display}"
    echo "║  SDK Dir     : ${SDK_DIR}"
    echo "║  编译器       : ${compiler_display}"
    echo "║  目标架构     : arm64 (RK3588)"
    echo "║  Jobs        : ${JOBS}"
    echo "║  Fetch on Start: ${FETCH_ON_START}"
    if [ "${HOST_ARCH}" = "amd64" ]; then
    echo "║  i386 兼容    : 已启用 (Rockchip 工具)"
    else
    echo "║  i386 兼容    : 不适用 (非 x86_64)"
    fi
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
}

# ---- 检查 SDK 是否已拉取 ----
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
setup_compiler
setup_ccache
show_banner

if [ "${FETCH_ON_START}" = "yes" ]; then
    log_step "自动拉取 SDK (MANIFEST=${MANIFEST:-交互选择})"
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
