#!/bin/bash
# =============================================================================
# RK3588 SDK 源码拉取脚本
# 使用 repo + manifest 拉取完整 SDK, 支持交互式选择 + 多 BSP 来源
# =============================================================================

set -e

# ---- 颜色输出 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "${CYAN}[STEP]${NC}  $*" >&2; }

# ---- 配置 ----
SDK_DIR="${SDK_DIR:-/home/builder/sdk}"
BSP_SOURCE="${BSP_SOURCE:-rockchip}"
MANIFEST="${MANIFEST:-}"          # manifest 文件名, 留空则交互选择
DEPTH="${DEPTH:-1}"               # 浅克隆深度, 0=完整克隆
JOBS="${JOBS:-$(nproc)}"          # repo 并行拉取数
if [ "${JOBS}" = "0" ]; then JOBS=$(nproc 2>/dev/null || echo 4); fi
MAX_RETRIES="${MAX_RETRIES:-3}"   # repo sync 最大重试次数
MIN_DISK_GB="${MIN_DISK_GB:-10}"  # 最小磁盘空间 (GB)

# ---- 内置 manifest 路径 ----
LOCAL_MANIFESTS="/home/builder/manifests"

# ---- 可用 SDK 配置 ----
declare -A SDK_OPTIONS
SDK_OPTIONS=(
  ["1"]="rk3588-linux-5.10.xml|Linux 5.10 LTS (Rockchip 官方推荐)"
  ["2"]="rk3588-linux-6.1.xml|Linux 6.1 LTS"
  ["3"]="rk3588-linux-6.6.xml|Linux 6.6 (最新)"
  ["4"]="rk3588-firefly.xml|Firefly AIO-3588 BSP"
  ["5"]="rk3588-radxa.xml|Radxa Rock 5B BSP"
  ["6"]="rk3588-orangepi.xml|OrangePi 5 BSP"
  ["7"]="custom|自定义 Manifest URL"
)

# ---- 磁盘空间检查 ----
check_disk_space() {
    local target_dir="$1"
    local min_gb="${2:-${MIN_DISK_GB}}"

    local avail_kb
    avail_kb=$(df -k "${target_dir}" 2>/dev/null | awk 'NR==2 {print $4}')

    if [ -n "${avail_kb}" ]; then
        local avail_gb=$((avail_kb / 1024 / 1024))
        if [ "${avail_gb}" -lt "${min_gb}" ]; then
            log_error "磁盘空间不足! 可用: ${avail_gb}GB, 需要: 至少 ${min_gb}GB"
            log_error "SDK 源码 + 编译产物通常需要 30-50GB"
            return 1
        fi
        log_info "磁盘空间: ${avail_gb}GB 可用 (最低要求: ${min_gb}GB)"
    else
        log_warn "无法检测磁盘空间, 继续执行..."
    fi
    return 0
}

# ---- 交互式选择 SDK 版本 ----
pick_sdk_version() {
    # 如果 MANIFEST 已设置, 直接使用
    if [ -n "${MANIFEST}" ]; then
        log_info "使用指定 Manifest: ${MANIFEST}"
        echo "${MANIFEST}"
        return 0
    fi

    # 根据 BSP_SOURCE 自动选择 (非交互模式)
    if [ "${BSP_SOURCE}" != "rockchip" ] && [ -n "${BSP_SOURCE}" ]; then
        case "${BSP_SOURCE}" in
            firefly)
                log_info "BSP_SOURCE=firefly, 使用 Firefly manifest"
                echo "rk3588-firefly.xml"
                return 0
                ;;
            radxa)
                log_info "BSP_SOURCE=radxa, 使用 Radxa manifest"
                echo "rk3588-radxa.xml"
                return 0
                ;;
            orangepi)
                log_info "BSP_SOURCE=orangepi, 使用 OrangePi manifest"
                echo "rk3588-orangepi.xml"
                return 0
                ;;
            custom)
                echo "custom"
                return 0
                ;;
        esac
    fi

    # 非交互模式 (无 TTY), 使用默认
    if [ ! -t 0 ] && [ ! -t 1 ]; then
        log_warn "非交互模式, 使用默认 SDK: Linux 5.10 LTS"
        echo "rk3588-linux-5.10.xml"
        return 0
    fi

    echo "" >&2
    echo -e "${BOLD}  选择 RK3588 SDK 版本:${NC}" >&2
    echo "  ─────────────────────────────────────────────" >&2
    echo "" >&2
    echo -e "  ${BOLD}Rockchip 官方:${NC}" >&2

    for key in 1 2 3; do
        local val="${SDK_OPTIONS[$key]}"
        local desc="${val##*|}"
        if [ "${key}" = "1" ]; then
            echo -e "  ${CYAN}${key}) ${desc}${NC} ${GREEN}[推荐]${NC}" >&2
        else
            echo -e "  ${CYAN}${key}) ${desc}${NC}" >&2
        fi
    done

    echo "" >&2
    echo -e "  ${BOLD}第三方 BSP:${NC}" >&2

    for key in 4 5 6; do
        local val="${SDK_OPTIONS[$key]}"
        local desc="${val##*|}"
        echo -e "  ${CYAN}${key}) ${desc}${NC}" >&2
    done

    echo "" >&2
    echo -e "  ${CYAN}7) 自定义 Manifest URL${NC}" >&2

    echo "" >&2
    echo -en "  请选择 [1-7] (默认 1): " >&2

    local choice
    read -r choice
    choice="${choice:-1}"

    local val="${SDK_OPTIONS[$choice]:-${SDK_OPTIONS[1]}}"
    local xml="${val%%|*}"

    if [ "${xml}" = "custom" ]; then
        if [ -z "${CUSTOM_MANIFEST_URL}" ]; then
            echo -en "  请输入自定义 Manifest URL: " >&2
            read -r CUSTOM_MANIFEST_URL
        fi
        echo "custom"
    else
        log_info "已选择: ${val##*|}"
        echo "${xml}"
    fi
}

# ---- 带重试的 repo sync ----
repo_sync_with_retry() {
    local sync_opts="$1"
    local attempt=1

    while [ ${attempt} -le ${MAX_RETRIES} ]; do
        log_step "repo sync (第 ${attempt}/${MAX_RETRIES} 次)..."

        if repo sync ${sync_opts}; then
            log_info "repo sync 成功"
            return 0
        else
            log_warn "repo sync 失败 (第 ${attempt}/${MAX_RETRIES} 次)"
            if [ ${attempt} -lt ${MAX_RETRIES} ]; then
                local wait_sec=$((attempt * 10))
                log_info "等待 ${wait_sec} 秒后重试..."
                sleep ${wait_sec}
            fi
            attempt=$((attempt + 1))
        fi
    done

    log_error "repo sync 在 ${MAX_RETRIES} 次尝试后仍然失败"
    return 1
}

# ---- 使用 repo + 本地 manifest 拉取 SDK ----
fetch_sdk_with_local_manifest() {
    local manifest_file="$1"

    log_step "===== 使用 repo 拉取完整 SDK ====="
    log_info "Manifest: ${manifest_file}"

    cd "${SDK_DIR}"

    if [ ! -f "${LOCAL_MANIFESTS}/${manifest_file}" ]; then
        log_error "Manifest 文件不存在: ${LOCAL_MANIFESTS}/${manifest_file}"
        log_info "可用的 manifest 文件:"
        ls -1 "${LOCAL_MANIFESTS}"/*.xml 2>/dev/null | while read -r f; do
            echo "  - $(basename "${f}")"
        done
        exit 1
    fi

    log_step "准备 manifest 仓库..."
    # 创建临时 git 仓库作为 manifest 源 (repo 要求 manifest-url 是 git 仓库)
    local tmp_manifest_repo="/tmp/rk3588-manifest-repo"
    if [ -d "${tmp_manifest_repo}" ]; then
        rm -rf "${tmp_manifest_repo}"
    fi
    cp -r "${LOCAL_MANIFESTS}" "${tmp_manifest_repo}"
    cd "${tmp_manifest_repo}"
    git init -q -b master
    git add -A
    git commit -q -m "manifest" --allow-empty 2>/dev/null || true
    cd "${SDK_DIR}"

    local init_opts="-u file://${tmp_manifest_repo} -m ${manifest_file} -b master"
    if [ "${DEPTH}" != "0" ]; then
        init_opts="${init_opts} --depth=${DEPTH}"
    fi

    log_step "执行 repo init..."
    if ! repo init ${init_opts}; then
        log_warn "repo init 失败，可能是 .repo 目录损坏。正在自动清理并重新尝试..."
        rm -rf .repo
        repo init ${init_opts}
    fi

    # repo sync (带重试)
    repo_sync_with_retry "-j${JOBS}"
}

# ---- 使用自定义远程 manifest URL ----
fetch_sdk_with_custom_manifest() {
    log_step "===== 使用自定义 Manifest 拉取 SDK ====="
    log_info "Manifest URL: ${CUSTOM_MANIFEST_URL}"

    cd "${SDK_DIR}"

    local init_opts="-u ${CUSTOM_MANIFEST_URL} -m ${CUSTOM_MANIFEST_NAME:-default.xml} -b ${BRANCH:-main}"
    if [ "${DEPTH}" != "0" ]; then
        init_opts="${init_opts} --depth=${DEPTH}"
    fi

    log_step "执行 repo init..."
    if ! repo init ${init_opts}; then
        log_warn "repo init 失败，可能是 .repo 目录损坏。正在自动清理并重新尝试..."
        rm -rf .repo
        repo init ${init_opts}
    fi

    repo_sync_with_retry "-j${JOBS}"
}

# ---- 主流程 ----
main() {
    log_info "SDK 目录: ${SDK_DIR}"
    mkdir -p "${SDK_DIR}"

    # 磁盘空间检查
    check_disk_space "${SDK_DIR}" || exit 1

    # 交互式选择 SDK 版本
    local chosen_manifest
    chosen_manifest=$(pick_sdk_version)

    if [ "${chosen_manifest}" = "custom" ]; then
        fetch_sdk_with_custom_manifest
    else
        fetch_sdk_with_local_manifest "${chosen_manifest}"
    fi

    # ---- 拉取后验证 ----
    echo ""
    log_step "===== SDK 验证 ====="
    local ok=true
    local components="kernel u-boot rkbin"

    # 根据 manifest 检查 buildroot (非所有 BSP 都有)
    if [ -d "${SDK_DIR}/buildroot" ]; then
        components="${components} buildroot"
    fi

    for comp in ${components}; do
        if [ -d "${SDK_DIR}/${comp}" ]; then
            local rev
            rev=$(cd "${SDK_DIR}/${comp}" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
            local branch
            branch=$(cd "${SDK_DIR}/${comp}" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
            log_info "  ✓ ${comp}: ${rev} (${branch})"
        else
            log_error "  ✗ ${comp}: 缺失"
            ok=false
        fi
    done

    if ${ok}; then
        echo ""
        log_info "🎉 RK3588 SDK 拉取成功!"
        echo ""
        echo -e "${BOLD}  SDK 目录结构:${NC}"
        echo "  ${SDK_DIR}/"
        echo "  ├── kernel/      Linux 内核源码"
        echo "  ├── u-boot/      U-Boot 引导加载程序"
        echo "  ├── rkbin/       Rockchip 闭源固件 (DDR init, TF-A)"
        if [ -d "${SDK_DIR}/buildroot" ]; then
        echo "  ├── buildroot/   根文件系统构建"
        fi
        if [ -d "${SDK_DIR}/docs" ]; then
        echo "  ├── docs/        文档"
        fi
        echo ""
        echo -e "${BOLD}  快速开始编译:${NC}"
        echo "  kernel:  cd kernel && make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- rockchip_linux_defconfig && make -j\${JOBS}"
        echo "  u-boot:  cd u-boot && make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- rk3588_defconfig && make -j\${JOBS}"
    else
        log_error "部分组件拉取失败, 请检查网络或 manifest 配置"
        exit 1
    fi
}

main "$@"
