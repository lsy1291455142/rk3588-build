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
if [ "${JOBS}" = "0" ]; then JOBS=$(nproc 2>/dev/null || echo 4); fi
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

# ---- 配置 Git (防止 repo init / commit 失败) ----
setup_git() {
    if ! git config --global user.email >/dev/null 2>&1; then
        git config --global user.email "rk3588-builder@local"
    fi
    if ! git config --global user.name >/dev/null 2>&1; then
        git config --global user.name "RK3588 Builder"
    fi
    git lfs install --skip-smudge >/dev/null 2>&1 || git lfs install >/dev/null 2>&1
}

# ---- 主逻辑 ----
setup_compiler
setup_ccache
setup_git
show_banner


# ---- 运行环境自我检测 (仅在进入交互式 Shell 时触发) ----
check_environment() {
    log_step "正在执行编译环境自检..."
    local ok=true

    # 1. 检查基础工具链
    for cmd in gcc g++ aarch64-linux-gnu-gcc make cmake ninja dtc git git-lfs repo; do
        if command -v $cmd &>/dev/null; then
            echo -e "  ${GREEN}[✓]${NC} $cmd"
        else
            echo -e "  ${RED}[✗]${NC} $cmd ${YELLOW}(缺失)${NC}"
            ok=false
        fi
    done

    # 2. 检查 Python 核心签名/打包库 (特殊适配 pycryptodome 导入名 Crypto/Cryptodome)
    local py_libs_ok=true
    for lib in elftools jsonschema jinja2; do
        if ! python3 -c "import $lib" >/dev/null 2>&1; then
            py_libs_ok=false
        fi
    done
    if ! python3 -c "import Crypto" >/dev/null 2>&1 && ! python3 -c "import Cryptodome" >/dev/null 2>&1; then
        py_libs_ok=false
    fi

    if ${py_libs_ok}; then
        echo -e "  ${GREEN}[✓]${NC} python3 libraries (Cryptodome, elftools, jsonschema, jinja2)"
    else
        echo -e "  ${RED}[✗]${NC} python3 libraries ${YELLOW}(存在缺失, 影响固件打包)${NC}"
        ok=false
    fi

    if ${ok}; then
        log_info "🎉 所有编译工具和系统依赖已就绪，环境验证通过！"
    else
        log_warn "⚠️ 发现编译环境依赖缺失，请检查上方标红的 [✗] 项目！"
    fi
    echo ""
}

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

# 如果是进入交互式 Shell，自动输出环境自检
if [ "$1" = "/bin/bash" ] && [ $# -eq 1 ]; then
    check_environment
fi

log_info "环境准备就绪，进入 Shell"

# 执行传入的命令 (默认 /bin/bash)
exec "$@"
