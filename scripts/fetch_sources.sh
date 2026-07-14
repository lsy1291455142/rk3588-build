#!/bin/bash
# =============================================================================
# RK3588 SDK 源码拉取脚本
# 使用 repo + manifest 拉取完整 SDK, 支持交互式选择
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
BSP_SOURCE="${BSP_SOURCE:-}"
MANIFEST="${MANIFEST:-}"          # manifest 文件名, 留空则交互选择
DEPTH="${DEPTH:-1}"               # 浅克隆深度, 0=完整克隆
JOBS="${JOBS:-$(nproc)}"          # repo 并行拉取数

# ---- 内置 manifest 路径 ----
LOCAL_MANIFESTS="/home/builder/manifests"

# ---- 可用 SDK 配置 ----
declare -A SDK_OPTIONS
SDK_OPTIONS=(
  ["1"]="rk3588-linux-5.10.xml|Linux 5.10 LTS (Rockchip 官方推荐)"
  ["2"]="rk3588-linux-6.1.xml|Linux 6.1 LTS"
  ["3"]="rk3588-linux-6.6.xml|Linux 6.6 (最新)"
  ["4"]="custom|自定义 Manifest URL"
)

# ---- 交互式选择 SDK 版本 ----
pick_sdk_version() {
    # 如果 MANIFEST 已设置, 直接使用
    if [ -n "${MANIFEST}" ]; then
        log_info "使用指定 Manifest: ${MANIFEST}"
        echo "${MANIFEST}"
        return 0
    fi

    # 非交互模式 (无 TTY), 使用默认
    if [ ! -t 0 ] && [ ! -t 1 ]; then
        log_warn "非交互模式, 使用默认 SDK: Linux 5.10 LTS"
        echo "rk3588-linux-5.10.xml"
        return 0
    fi

    echo ""
    echo -e "${BOLD}  选择 RK3588 SDK 版本:${NC}"
    echo "  ─────────────────────────────────────────────"

    for key in $(echo "${!SDK_OPTIONS[@]}" | tr ' ' '\n' | sort -n); do
        local val="${SDK_OPTIONS[$key]}"
        local xml="${val%%|*}"
        local desc="${val##*|}"
        if [ "${key}" = "1" ]; then
            echo -e "  ${CYAN}${key}) ${desc}${NC} ${GREEN}[推荐]${NC}"
        else
            echo -e "  ${CYAN}${key}) ${desc}${NC}"
        fi
    done

    echo ""
    echo -en "  请选择 [1-4] (默认 1): "

    local choice
    read -r choice
    choice="${choice:-1}"

    local val="${SDK_OPTIONS[$choice]:-${SDK_OPTIONS[1]}}"
    local xml="${val%%|*}"

    if [ "${xml}" = "custom" ]; then
        if [ -z "${CUSTOM_MANIFEST_URL}" ]; then
            echo -en "  请输入自定义 Manifest URL: "
            read -r CUSTOM_MANIFEST_URL
        fi
        echo "custom"
    else
        log_info "已选择: ${val##*|}"
        echo "${xml}"
    fi
}

# ---- 使用 repo + 本地 manifest 拉取 SDK ----
fetch_sdk_with_local_manifest() {
    local manifest_file="$1"

    log_step "===== 使用 repo 拉取完整 SDK ====="
    log_info "Manifest: ${manifest_file}"

    cd "${SDK_DIR}"

    if [ ! -f "${LOCAL_MANIFESTS}/${manifest_file}" ]; then
        log_error "Manifest 文件不存在: ${LOCAL_MANIFESTS}/${manifest_file}"
        exit 1
    fi

    # repo init 使用本地 manifest
    # --manifest-url 指向本地目录, repo 会从该 git 仓库读取 manifest
    # 这里用 file:// 协议指向本地
    if [ ! -d ".repo" ]; then
        log_step "初始化 repo..."
        # 创建临时 git 仓库作为 manifest 源 (repo 要求 manifest-url 是 git 仓库)
        local tmp_manifest_repo="/tmp/rk3588-manifest-repo"
        if [ -d "${tmp_manifest_repo}" ]; then
            rm -rf "${tmp_manifest_repo}"
        fi
        cp -r "${LOCAL_MANIFESTS}" "${tmp_manifest_repo}"
        cd "${tmp_manifest_repo}"
        git init -q
        git add -A
        git commit -q -m "manifest" --allow-empty 2>/dev/null || true
        cd "${SDK_DIR}"

        repo init -u "file://${tmp_manifest_repo}" -m "${manifest_file}" -b master
    else
        log_info ".repo 已存在, 跳过 init (如需重新初始化请先删除 .repo 目录)"
    fi

    # repo sync
    local sync_opts="-j${JOBS}"
    if [ "${DEPTH}" != "0" ]; then
        sync_opts="${sync_opts} --depth=${DEPTH}"
    fi

    log_step "同步 SDK 源码 (并行: ${JOBS})..."
    repo sync ${sync_opts}
}

# ---- 使用自定义远程 manifest URL ----
fetch_sdk_with_custom_manifest() {
    log_step "===== 使用自定义 Manifest 拉取 SDK ====="
    log_info "Manifest URL: ${CUSTOM_MANIFEST_URL}"

    cd "${SDK_DIR}"

    if [ ! -d ".repo" ]; then
        repo init -u "${CUSTOM_MANIFEST_URL}" -m "${CUSTOM_MANIFEST_NAME:-default.xml}" -b "${BRANCH:-main}"
    else
        log_info ".repo 已存在, 跳过 init"
    fi

    local sync_opts="-j${JOBS}"
    if [ "${DEPTH}" != "0" ]; then
        sync_opts="${sync_opts} --depth=${DEPTH}"
    fi

    repo sync ${sync_opts}
}

# ---- 主流程 ----
main() {
    log_info "SDK 目录: ${SDK_DIR}"
    mkdir -p "${SDK_DIR}"

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
    local components="kernel u-boot rkbin buildroot"

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
        echo "  ├── buildroot/   根文件系统构建"
        echo "  └── docs/        文档"
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
