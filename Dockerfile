# =============================================================================
# RK3588 Linux BSP Docker 编译环境
# 支持自动拉取 Rockchip 官方 / 开发板厂商公开 SDK 源码
# =============================================================================

FROM ubuntu:22.04 AS base

LABEL maintainer="rk3588-build"
LABEL description="RK3588 Linux BSP Docker Build Environment"

# ---- 避免交互式安装提示 ----
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# ---- 添加 i386 架构 (部分 Rockchip 32位工具需要) ----
RUN dpkg --add-architecture i386

# ---- 基础系统依赖 ----
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
    repo \
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
    ssh \
    vim \
    ccache \
    swig \
    u-boot-tools \
    # 32位兼容 (部分 Rockchip 工具需要)
    libc6:i386 \
    libstdc++6:i386 \
    zlib1g:i386 \
    # 文档构建 (可选)
    sphinx-common \
    && rm -rf /var/lib/apt/lists/*

# ---- 安装 Python 依赖 ----
RUN python3 -m pip install --no-cache-dir --break-system-packages \
    pycryptodome \
    pyelftools \
    jsonschema \
    jinja2

# ---- 配置 Git ----
RUN git config --global user.email "rk3588-builder@local" && \
    git config --global user.name "RK3588 Builder" && \
    git config --global lfs.install

# ---- 配置交叉编译环境变量 ----
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

USER builder
WORKDIR /home/builder/sdk

# ---- 入口脚本 ----
COPY --chown=builder:builder scripts/entrypoint.sh /home/builder/entrypoint.sh
RUN chmod +x /home/builder/entrypoint.sh

ENTRYPOINT ["/home/builder/entrypoint.sh"]
CMD ["/bin/bash"]
