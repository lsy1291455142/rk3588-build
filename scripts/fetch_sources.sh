#!/bin/bash
# =============================================================================
# RK3588 SDK 源码拉取脚本
# 支持多种 BSP 来源: rockchip / firefly / radxa / orangepi
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

# ---- 配置 ----
SDK_DIR="${SDK_DIR:-/home/builder/sdk}"
BSP_SOURCE="${BSP_SOURCE:-rockchip}"
BRANCH="${BRANCH:-stable-5.10}"
DEPTH="${DEPTH:-1}"                # 浅克隆深度, 设为 0 表示完整克隆
JOBS="${JOBS:-4}"                  # repo 并行拉取数

# ---- BSP 源配置 ----
# Rockchip 官方 GitHub 组件式拉取
ROCKCHIP_GITHUB="https://github.com/rockchip-linux"
ROCKCHIP_KERNEL_BRANCH="stable-5.10"
ROCKCHIP_UBOOT_BRANCH="next-dev"
ROCKCHIP_RKBIN_BRANCH="master"

# Firefly GitLab
FIREFLY_GITLAB="https://gitlab.com/firefly-linux"
FIREFLY_KERNEL_BRANCH="main"
FIREFLY_UBOOT_BRANCH="main"
FIREFLY_RKBIN_BRANCH="main"

# Radxa GitHub
RADXA_GITHUB="https://github.com/radxa"
RADXA_KERNEL_BRANCH="main"
RADXA_UBOOT_BRANCH="main"

# OrangePi GitHub
ORANGEPI_GITHUB="https://github.com/orangepi-xunlong"
ORANGEPI_KERNEL_BRANCH="main"
ORANGEPI_UBOOT_BRANCH="main"

# ---- 工具函数 ----
git_clone() {
    local url="$1"
    local dir="$2"
    local branch="${3:-main}"

    if [ -d "${dir}" ]; then
        log_info "${dir} 已存在, 跳过拉取 (如需更新请手动 git pull)"
        return 0
    fi

    log_step "克隆 ${url} (branch: ${branch}) -> ${dir}"
    if [ "${DEPTH}" = "0" ]; then
        git clone --branch "${branch}" --single-branch "${url}" "${dir}"
    else
        git clone --depth="${DEPTH}" --branch "${branch}" --single-branch "${url}" "${dir}"
    fi
}

repo_sync() {
    local manifest_url="$1"
    local manifest_branch="${2:-main}"
    local manifest_name="${3:-default.xml}"

    log_step "使用 repo 拉取 (manifest: ${manifest_url}, branch: ${manifest_branch})"

    if [ ! -d ".repo" ]; then
        repo init -u "${manifest_url}" -b "${manifest_branch}" -m "${manifest_name}"
    else
        log_info ".repo 已存在, 跳过 init"
    fi

    repo sync -j"${JOBS}" --force-sync
}

# ---- BSP 拉取函数 ----

fetch_rockchip() {
    log_step "===== 拉取 Rockchip 官方 SDK ====="
    cd "${SDK_DIR}"

    # Rockchip 官方没有公开完整 manifest, 采用组件式拉取
    local kernel_branch="${BRANCH:-${ROCKCHIP_KERNEL_BRANCH}}"
    local uboot_branch="${ROCKCHIP_UBOOT_BRANCH}"

    git_clone "${ROCKCHIP_GITHUB}/kernel"     "kernel"     "${kernel_branch}"
    git_clone "${ROCKCHIP_GITHUB}/u-boot"     "u-boot"     "${uboot_branch}"
    git_clone "${ROCKCHIP_GITHUB}/rkbin"      "rkbin"      "${ROCKCHIP_RKBIN_BRANCH}"
    git_clone "${ROCKCHIP_GITHUB}/buildroot"  "buildroot"  "master"
    git_clone "${ROCKCHIP_GITHUB}/docs"       "docs"       "master"

    # 可选: 拉取设备树 overlays
    if [ "${EXTRA_COMPONENTS}" = "yes" ]; then
        log_step "拉取额外组件..."
        git_clone "${ROCKCHIP_GITHUB}/device-tree" "device-tree" "master" 2>/dev/null || \
            log_warn "device-tree 仓库拉取失败, 跳过"
    fi

    log_info "Rockchip 官方 SDK 拉取完成"
    log_info "  kernel  : ${SDK_DIR}/kernel  (${kernel_branch})"
    log_info "  u-boot  : ${SDK_DIR}/u-boot  (${uboot_branch})"
    log_info "  rkbin   : ${SDK_DIR}/rkbin"
    log_info "  buildroot: ${SDK_DIR}/buildroot"
}

fetch_firefly() {
    log_step "===== 拉取 Firefly AIO-3588 BSP ====="
    cd "${SDK_DIR}"

    # Firefly 提供了较完整的 BSP, 优先尝试 repo manifest
    local manifest_url="${FIREFLY_GITLAB}/manifests.git"

    if repo_sync "${manifest_url}" "${BRANCH}" "rk3588_linux.xml" 2>/dev/null; then
        log_info "Firefly BSP 通过 repo 拉取成功"
    else
        log_warn "repo 拉取失败, 回退到组件式拉取"
        git_clone "${FIREFLY_GITLAB}/kernel.git"       "kernel"    "${FIREFLY_KERNEL_BRANCH}"
        git_clone "${FIREFLY_GITLAB}/u-boot.git"       "u-boot"    "${FIREFLY_UBOOT_BRANCH}"
        git_clone "${FIREFLY_GITLAB}/rkbin.git"        "rkbin"     "${FIREFLY_RKBIN_BRANCH}"
        git_clone "${FIREFLY_GITLAB}/buildroot.git"    "buildroot" "main"
    fi

    log_info "Firefly BSP 拉取完成"
}

fetch_radxa() {
    log_step "===== 拉取 Radxa Rock 5B BSP ====="
    cd "${SDK_DIR}"

    git_clone "${RADXA_GITHUB}/kernel.git"   "kernel"   "${RADXA_KERNEL_BRANCH}"
    git_clone "${RADXA_GITHUB}/u-boot.git"   "u-boot"   "${RADXA_UBOOT_BRANCH}"
    git_clone "${ROCKCHIP_GITHUB}/rkbin"     "rkbin"    "${ROCKCHIP_RKBIN_BRANCH}"

    # Radxa 使用 Debian 构建而非 Buildroot
    if [ "${EXTRA_COMPONENTS}" = "yes" ]; then
        log_step "拉取 Radxa Debian 构建脚本..."
        git_clone "${RADXA_GITHUB}/radxa-debian.git" "debian" "main" 2>/dev/null || \
            log_warn "Radxa Debian 仓库拉取失败, 跳过"
    fi

    log_info "Radxa BSP 拉取完成"
}

fetch_orangepi() {
    log_step "===== 拉取 Orange Pi 5 BSP ====="
    cd "${SDK_DIR}"

    git_clone "${ORANGEPI_GITHUB}/orangepi5-linux.git"   "kernel"   "${ORANGEPI_KERNEL_BRANCH}"
    git_clone "${ORANGEPI_GITHUB}/orangepi5-uboot.git"   "u-boot"   "${ORANGEPI_UBOOT_BRANCH}"
    git_clone "${ROCKCHIP_GITHUB}/rkbin"                 "rkbin"    "${ROCKCHIP_RKBIN_BRANCH}"

    log_info "Orange Pi BSP 拉取完成"
}

# ---- 主流程 ----
main() {
    log_info "SDK 目录: ${SDK_DIR}"
    log_info "BSP 来源: ${BSP_SOURCE}"
    log_info "分支    : ${BRANCH}"

    mkdir -p "${SDK_DIR}"
    cd "${SDK_DIR}"

    case "${BSP_SOURCE}" in
        rockchip)
            fetch_rockchip
            ;;
        firefly)
            fetch_firefly
            ;;
        radxa)
            fetch_radxa
            ;;
        orangepi)
            fetch_orangepi
            ;;
        custom)
            if [ -z "${CUSTOM_MANIFEST_URL}" ]; then
                log_error "BSP_SOURCE=custom 需要设置 CUSTOM_MANIFEST_URL 环境变量"
                exit 1
            fi
            repo_sync "${CUSTOM_MANIFEST_URL}" "${BRANCH}" "${CUSTOM_MANIFEST_NAME:-default.xml}"
            ;;
        *)
            log_error "未知的 BSP_SOURCE: ${BSP_SOURCE}"
            log_error "支持: rockchip | firefly | radxa | orangepi | custom"
            exit 1
            ;;
    esac

    # ---- 拉取后验证 ----
    echo ""
    log_step "===== 源码验证 ====="
    local ok=true

    for comp in kernel u-boot rkbin; do
        if [ -d "${SDK_DIR}/${comp}" ]; then
            local rev=$(cd "${SDK_DIR}/${comp}" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
            log_info "  ✓ ${comp}: ${rev}"
        else
            log_error "  ✗ ${comp}: 缺失"
            ok=false
        fi
    done

    if ${ok}; then
        echo ""
        log_info "🎉 SDK 源码拉取成功! 可以开始编译了"
        log_info "   kernel 编译:  cd kernel && make rockchip_linux_defconfig && make -j\${JOBS}"
        log_info "   u-boot 编译:  cd u-boot && make rk3588_defconfig && make -j\${JOBS}"
    else
        log_error "部分组件拉取失败, 请检查网络或仓库地址"
        exit 1
    fi
}

main "$@"
