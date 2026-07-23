#!/bin/bash
# =============================================================================
# RK3588 Docker 容器入口脚本
# 支持自动拉取 SDK、交互式 Shell、ARM64 原生编译切换
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

HOST_ARCH="$(dpkg --print-architecture 2>/dev/null || echo "unknown")"

# ---- Drop to builder user if started as root ----
if [ "$(id -u)" -eq 0 ] && command -v gosu >/dev/null 2>&1; then
    # Ensure output directory is writable by builder before dropping privileges
    mkdir -p /home/builder/output 2>/dev/null || true
    chmod a+rwx /home/builder/output 2>/dev/null || true
    find /home/builder/output -type d -exec chmod a+rwx {} + 2>/dev/null || true

    BUILDER_UID="$(id -u builder 2>/dev/null || echo 1000)"
    BUILDER_GID="$(id -g builder 2>/dev/null || echo 1000)"
    exec gosu "${BUILDER_UID}:${BUILDER_GID}" /bin/bash "${BASH_SOURCE[0]}" "$@"
fi

# ---- 环境变量默认值 ----
SDK_DIR="${SDK_DIR:-/home/builder/sdk}"
MANIFEST="${MANIFEST:-}"                     # manifest 文件名
FETCH_ON_START="${FETCH_ON_START:-no}"       # 容器启动时是否自动拉取
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"  # 编译并行数
if [ "${JOBS}" = "0" ]; then JOBS=$(nproc 2>/dev/null || echo 4); fi
USE_NATIVE_BUILD="${USE_NATIVE_BUILD:-no}"  # ARM64 原生编译

# ---- 配置交叉编译环境 ----
setup_compiler() {
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

# ---- 动态计算终端显示宽度并对齐边框 ----
get_display_width() {
    if command -v python3 &>/dev/null; then
        python3 -c 'import sys, unicodedata; print(sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in sys.argv[1]))' "$1" 2>/dev/null || echo "${#1}"
    else
        echo "${#1}"
    fi
}

print_line() {
    local label="$1"
    local value="$2"
    local content="  ${label}${value}"
    local total_width=56 # 盒子内部总宽度（不含左右边框）
    local width
    width=$(get_display_width "${content}")
    local pad=$((total_width - width))
    local padding=""
    if [ $pad -gt 0 ]; then
        padding=$(printf '%*s' $pad "")
    fi
    echo "║${content}${padding}║"
}

# ---- 显示环境信息 ----
show_banner() {
    local manifest_display="${MANIFEST:-未指定}"
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
    print_line "宿主机架构   : " "${HOST_ARCH}"
    print_line "Manifest    : " "${manifest_display}"
    print_line "SDK Dir     : " "${SDK_DIR}"
    print_line "编译器       : " "${compiler_display}"
    print_line "目标架构     : " "arm64 (RK3588)"
    print_line "Jobs        : " "${JOBS}"
    print_line "Fetch on Start: " "${FETCH_ON_START}"
    if [ "${HOST_ARCH}" = "amd64" ]; then
        print_line "i386 兼容    : " "已启用 (Rockchip 工具)"
    else
        print_line "i386 兼容    : " "不适用 (非 x86_64)"
    fi
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
}


# ---- 检查 SDK 是否已拉取 ----
check_sdk() {
    if [ -d "${SDK_DIR}/kernel" ] &&
        [ -d "${SDK_DIR}/u-boot" ] &&
        [ -d "${SDK_DIR}/rkbin" ] &&
        [ -d "${SDK_DIR}/buildroot" ]; then
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
# 必检命令对应 rk3588-build 容器内各 build_*.sh / make_image.sh / verify_image.sh
# 的 require_cmd；选检命令仅特定板型 (CokePi U-Boot 的 python2) 或阶段
# (test-debian-qemu 的 qemu-system-arm) 需要，缺失只提示不阻断。
check_environment() {
    log_step "正在执行编译环境自检..."
    local ok=true

    _check_cmds() {
        local label="$1"; shift
        echo -e "  ${CYAN}${label}${NC}"
        local c
        for c in "$@"; do
            if command -v "$c" >/dev/null 2>&1; then
                echo -e "    ${GREEN}[✓]${NC} $c"
            else
                echo -e "    ${RED}[✗]${NC} $c ${YELLOW}(缺失)${NC}"
                ok=false
            fi
        done
    }

    _check_cmds_optional() {
        local label="$1"; shift
        echo -e "  ${CYAN}${label}${NC}"
        local c
        for c in "$@"; do
            if command -v "$c" >/dev/null 2>&1; then
                echo -e "    ${GREEN}[✓]${NC} $c"
            else
                echo -e "    ${YELLOW}[!]${NC} $c ${YELLOW}(可选: 仅特定板型/阶段需要)${NC}"
            fi
        done
    }

    _check_cmds "基础工具链" gcc g++ aarch64-linux-gnu-gcc make cmake ninja dtc git git-lfs repo
    _check_cmds "内核构建主机工具" bc bison flex openssl perl fdtget fdtput
    _check_cmds "镜像组装与校验" sgdisk truncate mkfs.vfat mkfs.ext4 mcopy mmd zstd sha256sum install cmp mdir blkid debugfs e2fsck
    _check_cmds "rootfs 打包工具" tar
    _check_cmds_optional "可选: QEMU 测试 / CokePi U-Boot" qemu-system-arm python2

    # Python 解释器与核心库 (特殊适配 pycryptodome 导入名 Crypto/Cryptodome)
    local py_ok=true
    if command -v python3 >/dev/null 2>&1; then
        echo -e "  ${CYAN}Python 运行时${NC}"
        echo -e "    ${GREEN}[✓]${NC} python3"
        for lib in elftools jsonschema jinja2 pexpect; do
            if python3 -c "import $lib" >/dev/null 2>&1; then
                echo -e "    ${GREEN}[✓]${NC} python3:$lib"
            else
                echo -e "    ${RED}[✗]${NC} python3:$lib ${YELLOW}(缺失)${NC}"
                py_ok=false
            fi
        done
        if ! python3 -c "import Crypto" >/dev/null 2>&1 && ! python3 -c "import Cryptodome" >/dev/null 2>&1; then
            echo -e "    ${RED}[✗]${NC} python3:Crypto/Cryptodome ${YELLOW}(缺失)${NC}"
            py_ok=false
        else
            echo -e "    ${GREEN}[✓]${NC} python3:Crypto/Cryptodome"
        fi
    else
        echo -e "  ${RED}[✗]${NC} python3 ${YELLOW}(缺失)${NC}"
        py_ok=false
    fi
    ${py_ok} || ok=false

    if ${ok}; then
        log_info "🎉 所有编译工具和系统依赖已就绪，环境验证通过！"
    else
        log_warn "⚠️ 发现编译环境依赖缺失，请检查上方标红的 [✗] 项目！"
    fi
    echo ""
}

if [ "${FETCH_ON_START}" = "yes" ]; then
    if [ -z "${MANIFEST}" ] && \
        { [ -z "${CUSTOM_MANIFEST_URL:-}" ] || [ -z "${CUSTOM_MANIFEST_NAME:-}" ]; }; then
        log_error "FETCH_ON_START=yes requires MANIFEST or CUSTOM_MANIFEST_URL/CUSTOM_MANIFEST_NAME"
        exit 1
    fi
    log_step "自动拉取 SDK (MANIFEST=${MANIFEST:-未指定})"
    if [ -f "${SCRIPT_DIR}/fetch_sources.sh" ]; then
        bash "${SCRIPT_DIR}/fetch_sources.sh"
    else
        log_error "fetch_sources.sh 不存在，跳过拉取"
    fi
else
    check_sdk || log_warn "提示: 运行 make fetch BOARD=<board>、make fetch-custom 或 make import-local-sdk 拉取/导入 SDK"
fi

# 如果是进入交互式 Shell，自动输出环境自检
if [ "$1" = "/bin/bash" ] && [ $# -eq 1 ]; then
    check_environment
fi

log_info "环境准备就绪，进入 Shell"

# 执行传入的命令 (默认 /bin/bash)
exec "$@"
