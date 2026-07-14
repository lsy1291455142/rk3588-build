#!/bin/bash
# =============================================================================
# RK3588 SDK 源码拉取脚本
# 支持多种 BSP 来源 + 交互式分支选择
# =============================================================================

set -e

# ---- 颜色输出 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "${CYAN}[STEP]${NC}  $*"; }

# ---- 配置 ----
SDK_DIR="${SDK_DIR:-/home/builder/sdk}"
BSP_SOURCE="${BSP_SOURCE:-rockchip}"
BRANCH="${BRANCH:-}"                # 留空则交互选择
DEPTH="${DEPTH:-1}"                 # 浅克隆深度, 0=完整克隆
JOBS="${JOBS:-4}"                   # repo 并行拉取数

# ---- BSP 源配置 (实际验证过的分支) ----
ROCKCHIP_GITHUB="https://github.com/rockchip-linux"

# Rockchip kernel 实际分支: develop-4.19, develop-5.10, develop-6.1, develop-6.6
# Rockchip u-boot 实际分支: next-dev, master
# Rockchip rkbin 实际分支: master

FIREFLY_GITLAB="https://gitlab.com/firefly-linux"
RADXA_GITHUB="https://github.com/radxa"
ORANGEPI_GITHUB="https://github.com/orangepi-xunlong"

# ---- 交互式选择工具 ----

# 列出远程仓库分支
list_remote_branches() {
    local url="$1"
    git ls-remote --heads "${url}" 2>/dev/null | awk -F'/' '{print $NF}' | sort
}

# 交互式选择分支
pick_branch() {
    local url="$1"
    local repo_name="$2"
    local default_branch="$3"

    # 如果 BRANCH 已设置, 直接使用
    if [ -n "${BRANCH}" ]; then
        echo "${BRANCH}"
        return 0
    fi

    # 非交互模式 (无 TTY), 使用默认
    if [ ! -t 0 ]; then
        log_warn "非交互模式, ${repo_name} 使用默认分支: ${default_branch}"
        echo "${default_branch}"
        return 0
    fi

    log_step "获取 ${repo_name} 远程分支列表..."
    local branches
    branches=$(list_remote_branches "${url}")

    if [ -z "${branches}" ]; then
        log_warn "无法获取分支列表, 使用默认: ${default_branch}"
        echo "${default_branch}"
        return 0
    fi

    # 显示分支列表
    echo ""
    echo -e "${BOLD}  ${repo_name} 可用分支:${NC}"
    echo "  ─────────────────────────"

    local i=1
    local default_idx=1
    local branch_array=()
    while IFS= read -r b; do
        branch_array+=("${b}")
        if [ "${b}" = "${default_branch}" ]; then
            default_idx=${i}
            echo -e "  ${CYAN}${i}) ${b} ${GREEN}[推荐]${NC}"
        else
            echo "  ${i}) ${b}"
        fi
        i=$((i + 1))
    done <<< "${branches}"

    echo ""
    echo -en "  请选择 [1-$((i-1))] (默认 ${default_idx}): "

    local choice
    read -r choice

    if [ -z "${choice}" ]; then
        choice=${default_idx}
    fi

    # 验证输入
    if ! echo "${choice}" | grep -qE '^[0-9]+$' || [ "${choice}" -lt 1 ] || [ "${choice}" -ge "${i}" ]; then
        log_warn "无效选择, 使用默认分支: ${default_branch}"
        echo "${default_branch}"
        return 0
    fi

    local selected="${branch_array[$((choice - 1))]}"
    log_info "已选择: ${selected}"
    echo "${selected}"
}

# 交互式选择 BSP 来源
pick_bsp_source() {
    # 如果已设置且非默认, 直接使用
    if [ -n "${BSP_SOURCE}" ] && [ "${BSP_SOURCE}" != "rockchip" ]; then
        echo "${BSP_SOURCE}"
        return 0
    fi

    # 非交互模式
    if [ ! -t 0 ]; then
        echo "rockchip"
        return 0
    fi

    echo ""
    echo -e "${BOLD}  选择 BSP 来源:${NC}"
    echo "  ─────────────────────────"
    echo -e "  ${CYAN}1) rockchip${NC}   ${GREEN}[推荐]${NC} Rockchip 官方 GitHub (最通用)"
    echo "  2) firefly     Firefly AIO-3588 BSP (较完整)"
    echo "  3) radxa       Radxa Rock 5B BSP (社区活跃)"
    echo "  4) orangepi    Orange Pi 5 BSP"
    echo "  5) custom      自定义 Manifest URL"
    echo ""
    echo -en "  请选择 [1-5] (默认 1): "

    local choice
    read -r choice
    choice="${choice:-1}"

    case "${choice}" in
        1) echo "rockchip" ;;
        2) echo "firefly" ;;
        3) echo "radxa" ;;
        4) echo "orangepi" ;;
        5) echo "custom" ;;
        *) log_warn "无效选择, 使用 rockchip"; echo "rockchip" ;;
    esac
}

# ---- Git 克隆 ----
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

    # 交互式选择各组件分支
    local kernel_branch
    kernel_branch=$(pick_branch "${ROCKCHIP_GITHUB}/kernel" "Kernel" "develop-5.10")

    local uboot_branch
    uboot_branch=$(pick_branch "${ROCKCHIP_GITHUB}/u-boot" "U-Boot" "next-dev")

    git_clone "${ROCKCHIP_GITHUB}/kernel"     "kernel"     "${kernel_branch}"
    git_clone "${ROCKCHIP_GITHUB}/u-boot"     "u-boot"     "${uboot_branch}"
    git_clone "${ROCKCHIP_GITHUB}/rkbin"      "rkbin"      "master"
    git_clone "${ROCKCHIP_GITHUB}/buildroot"  "buildroot"  "master"
    git_clone "${ROCKCHIP_GITHUB}/docs"       "docs"       "master"

    # 可选: 拉取设备树 overlays
    if [ "${EXTRA_COMPONENTS}" = "yes" ]; then
        log_step "拉取额外组件..."
        git_clone "${ROCKCHIP_GITHUB}/device-tree" "device-tree" "master" 2>/dev/null || \
            log_warn "device-tree 仓库拉取失败, 跳过"
    fi

    log_info "Rockchip 官方 SDK 拉取完成"
    log_info "  kernel   : ${SDK_DIR}/kernel  (${kernel_branch})"
    log_info "  u-boot   : ${SDK_DIR}/u-boot  (${uboot_branch})"
    log_info "  rkbin    : ${SDK_DIR}/rkbin"
    log_info "  buildroot: ${SDK_DIR}/buildroot"
}

fetch_firefly() {
    log_step "===== 拉取 Firefly AIO-3588 BSP ====="
    cd "${SDK_DIR}"

    local kernel_branch
    kernel_branch=$(pick_branch "${FIREFLY_GITLAB}/kernel.git" "Kernel" "main")

    local uboot_branch
    uboot_branch=$(pick_branch "${FIREFLY_GITLAB}/u-boot.git" "U-Boot" "main")

    git_clone "${FIREFLY_GITLAB}/kernel.git"    "kernel"    "${kernel_branch}"
    git_clone "${FIREFLY_GITLAB}/u-boot.git"    "u-boot"    "${uboot_branch}"
    git_clone "${FIREFLY_GITLAB}/rkbin.git"     "rkbin"     "main"
    git_clone "${FIREFLY_GITLAB}/buildroot.git" "buildroot" "main"

    log_info "Firefly BSP 拉取完成"
}

fetch_radxa() {
    log_step "===== 拉取 Radxa Rock 5B BSP ====="
    cd "${SDK_DIR}"

    local kernel_branch
    kernel_branch=$(pick_branch "${RADXA_GITHUB}/kernel.git" "Kernel" "main")

    local uboot_branch
    uboot_branch=$(pick_branch "${RADXA_GITHUB}/u-boot.git" "U-Boot" "main")

    git_clone "${RADXA_GITHUB}/kernel.git"   "kernel"   "${kernel_branch}"
    git_clone "${RADXA_GITHUB}/u-boot.git"   "u-boot"   "${uboot_branch}"
    git_clone "${ROCKCHIP_GITHUB}/rkbin"     "rkbin"    "master"

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

    local kernel_branch
    kernel_branch=$(pick_branch "${ORANGEPI_GITHUB}/orangepi5-linux.git" "Kernel" "main")

    local uboot_branch
    uboot_branch=$(pick_branch "${ORANGEPI_GITHUB}/orangepi5-uboot.git" "U-Boot" "main")

    git_clone "${ORANGEPI_GITHUB}/orangepi5-linux.git"   "kernel"   "${kernel_branch}"
    git_clone "${ORANGEPI_GITHUB}/orangepi5-uboot.git"   "u-boot"   "${uboot_branch}"
    git_clone "${ROCKCHIP_GITHUB}/rkbin"                 "rkbin"    "master"

    log_info "Orange Pi BSP 拉取完成"
}

# ---- 主流程 ----
main() {
    log_info "SDK 目录: ${SDK_DIR}"

    mkdir -p "${SDK_DIR}"
    cd "${SDK_DIR}"

    # 交互式选择 BSP 来源
    if [ -z "${BSP_SOURCE}" ] || [ "${BSP_SOURCE}" = "rockchip" ]; then
        BSP_SOURCE=$(pick_bsp_source)
    fi
    log_info "BSP 来源: ${BSP_SOURCE}"

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
            local rev
            rev=$(cd "${SDK_DIR}/${comp}" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
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
