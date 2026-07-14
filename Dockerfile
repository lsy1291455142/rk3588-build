# =============================================================================
# RK3588 Linux BSP Docker 编译环境
# 支持 x86_64 / ARM64 宿主机多架构构建
# =============================================================================

FROM ubuntu:22.04 AS base

LABEL maintainer="rk3588-build"
LABEL description="RK3588 Linux BSP Docker Build Environment (multi-arch)"

# ---- 避免交互式安装提示 ----
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# ---- 架构检测 ----
RUN ARCH=$(dpkg --print-architecture) && \
    echo "宿主机架构: ${ARCH}" && \
    echo "${ARCH}" > /etc/host_arch

# ---- 添加 i386 架构 (仅 x86_64 宿主机需要, Rockchip 部分 32 位工具) ----
RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
        dpkg --add-architecture i386; \
    fi

# ---- 基础系统依赖 (x86_64 / ARM64 通用) ----
RUN apt-get update && apt-get install -y --no-install-recommends \
    # 编译工具链 (host)
    build-essential \
    gcc-aarch64-linux-gnu \
    gcc-arm-linux-gnueabihf \
    # 通用构建工具
    make \
    cmake \
    ninja-build \
    pkg-config \
    # 版本控制
    git \
    git-lfs \
    # Python
    python3 \
    python3-pip \
    python3-setuptools \
    python3-wheel \
    # 内核/uboot 构建依赖
    bc \
    bison \
    flex \
    libncurses5-dev \
    libncursesw5-dev \
    libssl-dev \
    libelf-dev \
    # 设备树编译
    device-tree-compiler \
    # 压缩/打包工具
    lz4 \
    liblzo2-dev \
    lzop \
    xz-utils \
    zstd \
    cpio \
    rsync \
    unzip \
    # 文件系统工具
    mtools \
    dosfstools \
    e2fsprogs \
    genext2fs \
    fakeroot \
    # 烧写/镜像工具
    android-sdk-libsparse-utils \
    # 其他
    wget \
    curl \
    ca-certificates \
    gnupg \
    openssh-client \
    vim \
    ccache \
    swig \
    u-boot-tools \
    # 文档构建 (可选)
    sphinx-common \
    && rm -rf /var/lib/apt/lists/*

# ---- 安装 repo 工具 (手动安装最新版, apt 版本过旧) ----
RUN curl -sLo /usr/local/bin/repo https://storage.googleapis.com/git-repo-downloads/repo && \
    chmod a+x /usr/local/bin/repo && \
    repo version

# ---- x86_64 宿主机专属: 32 位兼容库 (部分 Rockchip 工具需要) ----
RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
        apt-get update && apt-get install -y --no-install-recommends \
            libc6:i386 \
            libstdc++6:i386 \
            zlib1g:i386 \
        && rm -rf /var/lib/apt/lists/*; \
    fi

# ---- ARM64 宿主机专属: 原生编译工具 (可选, 加速本地编译) ----
RUN if [ "$(dpkg --print-architecture)" = "arm64" ]; then \
        apt-get update && apt-get install -y --no-install-recommends \
            gcc \
            g++ \
        && rm -rf /var/lib/apt/lists/*; \
    fi

# ---- 安装 Python 依赖 ----
# Ubuntu 22.04 的 pip 不支持 --break-system-packages, 直接安装即可
RUN python3 -m pip install --no-cache-dir \
    pycryptodome \
    pyelftools \
    jsonschema \
    jinja2

# ---- 配置 Git ----
RUN git config --global user.email "rk3588-builder@local" && \
    git config --global user.name "RK3588 Builder" && \
    git lfs install

# ---- 配置交叉编译环境变量 ----
# ARM64 宿主机可选用原生 GCC 加速, 默认仍用交叉编译保持一致性
ENV CROSS_COMPILE=aarch64-linux-gnu-
ENV ARCH=arm64
ENV CCACHE_DIR=/home/builder/.ccache

# ---- 创建工作用户 (避免 root 权限问题) ----
RUN useradd -m -s /bin/bash builder && \
    mkdir -p /home/builder/sdk && \
    chown -R builder:builder /home/builder

# ---- 配置 ccache ----
RUN mkdir -p /home/builder/.ccache && \
    chown -R builder:builder /home/builder/.ccache

# ---- 架构信息标记 ----
RUN echo "========================================" && \
    echo "  宿主机架构 : $(dpkg --print-architecture)" && \
    echo "  交叉编译   : aarch64-linux-gnu-" && \
    echo "  目标架构   : arm64 (RK3588)" && \
    if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
        echo "  i386 兼容  : 已启用 (Rockchip 工具)"; \
    else \
        echo "  i386 兼容  : 不适用 (非 x86_64 宿主)"; \
    fi && \
    echo "========================================"

USER builder
WORKDIR /home/builder/sdk

# ---- 入口脚本 + 源码拉取脚本 ----
COPY --chown=builder:builder scripts/entrypoint.sh /home/builder/entrypoint.sh
COPY --chown=builder:builder scripts/fetch_sources.sh /home/builder/fetch_sources.sh
RUN chmod +x /home/builder/entrypoint.sh /home/builder/fetch_sources.sh

ENTRYPOINT ["/home/builder/entrypoint.sh"]
CMD ["/bin/bash"]
