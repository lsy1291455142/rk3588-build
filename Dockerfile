FROM ubuntu:22.04 AS rk3588-build

LABEL maintainer="rk3588-build"
LABEL description="RK3588 BSP, Buildroot, and raw image build environment"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV ARCH=arm64
ENV CROSS_COMPILE=aarch64-linux-gnu-
ENV CCACHE_DIR=/home/builder/.ccache
ENV PROJECT_DIR=/home/builder
ENV SDK_DIR=/home/builder/sdk
ENV OUTPUT_DIR=/home/builder/output

RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
        dpkg --add-architecture i386; \
    fi && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        android-sdk-libsparse-utils \
        bash \
        bc \
        binutils \
        bison \
        build-essential \
        bzip2 \
        ca-certificates \
        ccache \
        cmake \
        cpio \
        curl \
        device-tree-compiler \
        diffutils \
        dosfstools \
        e2fsprogs \
        fakeroot \
        file \
        findutils \
        flex \
        g++ \
        gawk \
        gcc \
        gcc-aarch64-linux-gnu \
        gcc-arm-linux-gnueabihf \
        gdisk \
        gettext \
        git \
        git-lfs \
        gnupg \
        gzip \
        kmod \
        libelf-dev \
        liblzo2-dev \
        libncurses-dev \
        libssl-dev \
        libxml2-utils \
        libyaml-dev \
        lz4 \
        lzop \
        make \
        mtools \
        ninja-build \
        openssh-client \
        gosu \
        openssl \
        patch \
        perl \
        pkg-config \
        python-is-python3 \
        python3 \
        python3-dev \
        python3-pip \
        python3-setuptools \
        python3-wheel \
        rsync \
        sed \
        shellcheck \
        swig \
        tar \
        u-boot-tools \
        unzip \
        util-linux \
        uuid-dev \
        wget \
        xz-utils \
        zstd && \
    rm -rf /var/lib/apt/lists/*

RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            libc6:i386 \
            libstdc++6:i386 \
            zlib1g:i386 && \
        rm -rf /var/lib/apt/lists/*; \
    fi

RUN if [ "$(dpkg --print-architecture)" = "arm64" ]; then \
        apt-get update && \
        apt-get install -y --no-install-recommends \
            qemu-user-static && \
        rm -rf /var/lib/apt/lists/*; \
    fi

RUN curl -fsSL -o /usr/local/bin/repo \
        https://storage.googleapis.com/git-repo-downloads/repo && \
    chmod 0755 /usr/local/bin/repo && \
    python3 -m pip install --no-cache-dir \
        jinja2 \
        jsonschema \
        pycryptodome \
        pyelftools

RUN git config --global user.email "rk3588-builder@local" && \
    git config --global user.name "RK3588 Builder" && \
    git lfs install

RUN useradd -m -s /bin/bash builder && \
    mkdir -p /home/builder/sdk /home/builder/output /home/builder/.ccache && \
    chown -R builder:builder /home/builder

COPY --chown=builder:builder scripts/ /home/builder/scripts/
COPY --chown=builder:builder manifests/ /home/builder/manifests/
COPY --chown=builder:builder configs/ /home/builder/configs/
COPY --chown=builder:builder rootfs/ /home/builder/rootfs/
RUN find /home/builder/scripts /home/builder/rootfs -type f -name '*.sh' \
        -exec chmod 0755 {} +

WORKDIR /home/builder

ENTRYPOINT ["/bin/bash", "/home/builder/scripts/entrypoint.sh"]
CMD ["/bin/bash"]


FROM debian:trixie-slim AS debian-rootfs

LABEL maintainer="rk3588-build"
LABEL description="Native ARM64 Debian rootfs build environment"

ENV DEBIAN_FRONTEND=noninteractive
ENV PROJECT_DIR=/home/builder
ENV SDK_DIR=/home/builder/sdk
ENV OUTPUT_DIR=/home/builder/output

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        coreutils \
        debian-archive-keyring \
        e2fsprogs \
        findutils \
        gnupg \
        kmod \
        mmdebstrap \
        mount \
        passwd \
        systemd \
        tar \
        util-linux \
        xz-utils && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /home/builder/sdk /home/builder/output

COPY scripts/ /home/builder/scripts/
COPY configs/ /home/builder/configs/
COPY rootfs/ /home/builder/rootfs/
RUN find /home/builder/scripts /home/builder/rootfs -type f -name '*.sh' \
        -exec chmod 0755 {} +

WORKDIR /home/builder
CMD ["/bin/bash"]
