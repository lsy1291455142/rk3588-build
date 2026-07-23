#!/bin/bash
# =============================================================================
# SDK 源码拉取脚本
# 使用 repo + manifest 拉取完整 SDK
# =============================================================================

set -e

# ---- 共享日志工具 ----
# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"

# ---- 配置 ----
SDK_DIR="${SDK_DIR:-/home/builder/sdk}"
MANIFEST="${MANIFEST:-}"          # 本地 manifest 文件名
DEPTH="${DEPTH:-1}"               # 浅克隆深度, 0=完整克隆
JOBS="${JOBS:-$(nproc)}"          # repo 并行拉取数
if [ "${JOBS}" = "0" ]; then JOBS=$(nproc 2>/dev/null || echo 4); fi
MAX_RETRIES="${MAX_RETRIES:-3}"   # repo sync 最大重试次数
MIN_DISK_GB="${MIN_DISK_GB:-10}"  # 最小磁盘空间 (GB)

# ---- 内置 manifest 路径 ----
LOCAL_MANIFESTS="/home/builder/manifests"

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

# ---- 带重试的 repo sync ----
repo_sync_with_retry() {
    local attempt=1

    while [ "${attempt}" -le "${MAX_RETRIES}" ]; do
        log_step "repo sync (第 ${attempt}/${MAX_RETRIES} 次)..."

        if repo sync "$@"; then
            log_info "repo sync 成功"
            return 0
        else
            log_warn "repo sync 失败 (第 ${attempt}/${MAX_RETRIES} 次)"
            if [ "${attempt}" -lt "${MAX_RETRIES}" ]; then
                local wait_sec=$((attempt * 10))
                log_info "等待 ${wait_sec} 秒后重试..."
                sleep "${wait_sec}"
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
        find "${LOCAL_MANIFESTS}" -maxdepth 1 -type f -name '*.xml' \
            -printf '  - %f\n' 2>/dev/null
        exit 1
    fi

    log_step "准备 manifest 仓库..."
    # 创建临时 git 仓库作为 manifest 源 (repo 要求 manifest-url 是 git 仓库)
    local tmp_manifest_repo="/tmp/sbc-manifest-repo"
    if [ -d "${tmp_manifest_repo}" ]; then
        rm -rf "${tmp_manifest_repo}"
    fi
    cp -r "${LOCAL_MANIFESTS}" "${tmp_manifest_repo}"
    cd "${tmp_manifest_repo}"
    git init -q -b master
    git add -A
    git commit -q -m "manifest" --allow-empty 2>/dev/null || true
    cd "${SDK_DIR}"

    local -a init_opts=(
        -u "file://${tmp_manifest_repo}"
        -m "${manifest_file}"
        -b master
    )
    if [ "${DEPTH}" != "0" ]; then
        init_opts+=("--depth=${DEPTH}")
    fi

    log_step "执行 repo init..."
    if ! repo init "${init_opts[@]}"; then
        log_warn "repo init 失败，可能是 .repo 目录损坏。正在自动清理并重新尝试..."
        rm -rf .repo
        repo init "${init_opts[@]}"
    fi

    # repo sync (带重试)
    repo_sync_with_retry "-j${JOBS}"
}

# ---- 使用自定义远程 manifest URL ----
fetch_sdk_with_custom_manifest() {
    [ -n "${CUSTOM_MANIFEST_URL:-}" ] || {
        log_error "CUSTOM_MANIFEST_URL is required"
        exit 1
    }
    [ -n "${CUSTOM_MANIFEST_NAME:-}" ] || {
        log_error "CUSTOM_MANIFEST_NAME is required"
        exit 1
    }

    log_step "===== 使用自定义 Manifest 拉取 SDK ====="
    log_info "Manifest URL: ${CUSTOM_MANIFEST_URL}"

    cd "${SDK_DIR}"

    local -a init_opts=(
        -u "${CUSTOM_MANIFEST_URL}"
        -m "${CUSTOM_MANIFEST_NAME}"
        -b "${BRANCH:-main}"
    )
    if [ "${DEPTH}" != "0" ]; then
        init_opts+=("--depth=${DEPTH}")
    fi

    log_step "执行 repo init..."
    if ! repo init "${init_opts[@]}"; then
        log_warn "repo init 失败，可能是 .repo 目录损坏。正在自动清理并重新尝试..."
        rm -rf .repo
        repo init "${init_opts[@]}"
    fi

    repo_sync_with_retry "-j${JOBS}"
}

# ---- 主流程 ----
main() {
    log_info "SDK 目录: ${SDK_DIR}"
    mkdir -p "${SDK_DIR}"

    # 磁盘空间检查
    check_disk_space "${SDK_DIR}" || exit 1

    # 检查是否为更新模式
    if [ "$1" = "update" ]; then
        log_step "===== 正在更新 SDK 仓库 ====="
        if [ ! -d "${SDK_DIR}/.repo" ]; then
            log_error "未检测到已初始化的 SDK 仓库 (没有发现 .repo 目录)。请先运行 make fetch BOARD=<board> 或 make fetch-custom。"
            exit 1
        fi

        # 无论如何，先准备好临时 manifest 仓库，防止容器重启后 /tmp 目录丢失导致 repo sync 报错
        log_info "正在准备本地 manifest 仓库镜像..."
        local tmp_manifest_repo="/tmp/sbc-manifest-repo"
        if [ -d "${tmp_manifest_repo}" ]; then
            rm -rf "${tmp_manifest_repo}"
        fi
        cp -r "${LOCAL_MANIFESTS}" "${tmp_manifest_repo}"
        cd "${tmp_manifest_repo}"
        git init -q -b master
        git add -A
        git commit -q -m "manifest" --allow-empty 2>/dev/null || true
        cd "${SDK_DIR}"

        local cur_manifest=""
        if [ -L "${SDK_DIR}/.repo/manifest.xml" ]; then
            cur_manifest=$(basename "$(readlink "${SDK_DIR}/.repo/manifest.xml" 2>/dev/null || echo "")")
        elif [ -f "${SDK_DIR}/.repo/manifest.xml" ]; then
            # 如果是普通文件，比对内容以匹配对应的本地 manifest (针对 NTFS 共享挂载下符号链接变普通文件的情况)
            for f in "${LOCAL_MANIFESTS}"/*.xml; do
                if [ -f "$f" ] && diff -q "${SDK_DIR}/.repo/manifest.xml" "$f" >/dev/null 2>&1; then
                    cur_manifest=$(basename "$f")
                    break
                fi
            done
            # 备用方案：尝试从文件中检索 include name
            if [ -z "${cur_manifest}" ]; then
                cur_manifest=$(sed -n 's/.*include name="\([^"]*\)".*/\1/p' "${SDK_DIR}/.repo/manifest.xml" 2>/dev/null || echo "")
            fi
        fi

        if [ -n "${cur_manifest}" ] && [ -f "${LOCAL_MANIFESTS}/${cur_manifest}" ]; then
            log_info "检测到当前 Manifest 为 ${cur_manifest}，正在重新初始化并更新..."
            
            # 清理已有的 manifest 仓库以防止 git rebase 历史不一致报错 (invalid upstream)
            if [ -d ".repo/manifests" ]; then
                rm -rf ".repo/manifests"
            fi
            if [ -d ".repo/manifests.git" ]; then
                rm -rf ".repo/manifests.git"
            fi

            local -a init_opts=(
                -u "file://${tmp_manifest_repo}"
                -m "${cur_manifest}"
                -b master
            )
            if [ "${DEPTH}" != "0" ]; then
                init_opts+=("--depth=${DEPTH}")
            fi
            repo init "${init_opts[@]}"
        else
            log_info "使用现有 .repo 配置直接同步更新代码..."
        fi

        repo_sync_with_retry "-j${JOBS}"
    else
        if [ -n "${CUSTOM_MANIFEST_URL:-}" ]; then
            fetch_sdk_with_custom_manifest
        elif [ -n "${MANIFEST}" ]; then
            log_info "使用指定 Manifest: ${MANIFEST}"
            fetch_sdk_with_local_manifest "${MANIFEST}"
        else
            log_error "MANIFEST or CUSTOM_MANIFEST_URL/CUSTOM_MANIFEST_NAME is required"
            exit 1
        fi
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
        if [ -n "${BOARD:-}" ]; then
            export PROJECT_DIR="${PROJECT_DIR:-/home/builder}"
            # shellcheck source=lib/common.sh
            source "/home/builder/scripts/lib/common.sh"
            load_board_profile
            validate_board_source_revisions
            log_info "板级锁定源码版本校验通过: ${BOARD}"
        fi
        echo ""
        log_info "🎉 SDK 拉取成功!"
        echo ""
        echo -e "${BOLD}  SDK 目录结构:${NC}"
        echo "  ${SDK_DIR}/"
        echo "  ├── kernel/      Linux 内核源码"
        echo "  ├── u-boot/      U-Boot 引导加载程序"
        echo "  ├── rkbin/       Rockchip 闭源固件 (DDR init, TF-A)"
        echo "  ├── buildroot/   根文件系统构建"
        if [ -d "${SDK_DIR}/docs" ]; then
        echo "  ├── docs/        文档"
        fi
        echo ""
        echo -e "${BOLD}  后续操作:${NC}"
        echo "  make use-board    选择目标板子"
        echo "  make build-all    一键构建完整镜像"
    else
        log_error "部分组件拉取失败, 请检查网络或 manifest 配置"
        exit 1
    fi
}

main "$@"
