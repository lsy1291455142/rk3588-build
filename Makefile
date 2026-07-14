# =============================================================================
# RK3588 Docker 编译环境 - 便捷命令
# =============================================================================

.PHONY: build build-nocache shell fetch fetch-510 fetch-61 fetch-66 \
        fetch-firefly fetch-radxa fetch-orangepi update \
        build-kernel build-uboot build-all pack \
        up down logs clean status help

# 默认配置
IMAGE ?= rk3588-build:latest
CONTAINER ?= rk3588-build

help: ## 显示帮助信息
	@echo ""
	@echo "RK3588 Docker 编译环境 - 可用命令:"
	@echo ""
	@echo "  镜像管理:"
	@grep -E '^(build|build-nocache):' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "    \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  SDK 拉取:"
	@grep -E '^(fetch|update)' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "    \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  编译:"
	@grep -E '^(build-kernel|build-uboot|build-all|pack):' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "    \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  容器管理:"
	@grep -E '^(shell|up|down|logs|status|clean):' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "    \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""

# =============================================================================
# 镜像管理
# =============================================================================

build: ## 构建 Docker 镜像
	docker compose build --progress=plain

build-nocache: ## 构建 Docker 镜像 (无缓存)
	docker compose build --no-cache --progress=plain

# =============================================================================
# SDK 拉取 - Rockchip 官方
# =============================================================================

fetch: ## 拉取完整 SDK (交互选择版本)
	docker compose run --rm -it rk3588-build /bin/bash -c \
		"/home/builder/fetch_sources.sh && echo 'SDK 拉取完成'"

fetch-510: ## 拉取 Rockchip SDK Linux 5.10 LTS
	docker compose run --rm -e MANIFEST=rk3588-linux-5.10.xml rk3588-build /bin/bash -c \
		"/home/builder/fetch_sources.sh && echo 'SDK 拉取完成'"

fetch-61: ## 拉取 Rockchip SDK Linux 6.1 LTS
	docker compose run --rm -e MANIFEST=rk3588-linux-6.1.xml rk3588-build /bin/bash -c \
		"/home/builder/fetch_sources.sh && echo 'SDK 拉取完成'"

fetch-66: ## 拉取 Rockchip SDK Linux 6.6
	docker compose run --rm -e MANIFEST=rk3588-linux-6.6.xml rk3588-build /bin/bash -c \
		"/home/builder/fetch_sources.sh && echo 'SDK 拉取完成'"

# =============================================================================
# SDK 拉取 - 第三方 BSP
# =============================================================================

fetch-firefly: ## 拉取 Firefly AIO-3588 BSP
	docker compose run --rm -e MANIFEST=rk3588-firefly.xml rk3588-build /bin/bash -c \
		"/home/builder/fetch_sources.sh && echo 'Firefly BSP 拉取完成'"

fetch-radxa: ## 拉取 Radxa Rock 5B BSP
	docker compose run --rm -e MANIFEST=rk3588-radxa.xml rk3588-build /bin/bash -c \
		"/home/builder/fetch_sources.sh && echo 'Radxa BSP 拉取完成'"

fetch-orangepi: ## 拉取 OrangePi 5 BSP
	docker compose run --rm -e MANIFEST=rk3588-orangepi.xml rk3588-build /bin/bash -c \
		"/home/builder/fetch_sources.sh && echo 'OrangePi BSP 拉取完成'"

update: ## 更新当前已拉取的 SDK 仓库 (自动同步最新代码)
	docker compose run --rm -it rk3588-build /bin/bash -c \
		"/home/builder/fetch_sources.sh update && echo 'SDK 仓库更新完成'"

# =============================================================================
# 编译
# =============================================================================

build-kernel: ## 编译 Kernel (需先拉取源码)
	@mkdir -p output
	docker compose run --rm rk3588-build /bin/bash -c \
		"cd /home/builder/sdk/kernel && \
		 make rockchip_linux_defconfig && \
		 make -j\$$(nproc) && \
		 cp arch/arm64/boot/Image /home/builder/output/ && \
		 cp arch/arm64/boot/dts/rockchip/rk3588*.dtb /home/builder/output/ 2>/dev/null || true && \
		 echo 'Kernel 编译产物已输出到宿主机: ./output/'"

build-uboot: ## 编译 U-Boot (需先拉取源码)
	@mkdir -p output
	docker compose run --rm rk3588-build /bin/bash -c \
		"cd /home/builder/sdk/u-boot && \
		 make rk3588_defconfig && \
		 make -j\$$(nproc) && \
		 cp u-boot.bin /home/builder/output/ && \
		 cp u-boot.img /home/builder/output/ 2>/dev/null || true && \
		 cp u-boot.itb /home/builder/output/ 2>/dev/null || true && \
		 echo 'U-Boot 编译产物已输出到宿主机: ./output/'"

build-all: ## 一键编译所有组件 (Kernel + U-Boot)
	@mkdir -p output
	docker compose run --rm rk3588-build /bin/bash -c \
		"echo '===== 编译 U-Boot =====' && \
		 cd /home/builder/sdk/u-boot && \
		 make rk3588_defconfig && \
		 make -j\$$(nproc) && \
		 cp u-boot.bin /home/builder/output/ && \
		 cp u-boot.img /home/builder/output/ 2>/dev/null || true && \
		 cp u-boot.itb /home/builder/output/ 2>/dev/null || true && \
		 echo '' && \
		 echo '===== 编译 Kernel =====' && \
		 cd /home/builder/sdk/kernel && \
		 make rockchip_linux_defconfig && \
		 make -j\$$(nproc) && \
		 cp arch/arm64/boot/Image /home/builder/output/ && \
		 cp arch/arm64/boot/dts/rockchip/rk3588*.dtb /home/builder/output/ 2>/dev/null || true && \
		 echo '' && \
		 echo '===== 编译完成，产物已输出到宿主机: ./output/ ====='"

pack: ## 一键收集并打包固件到 output/ 目录
	@mkdir -p output
	docker compose run --rm rk3588-build /bin/bash -c \
		"cd /home/builder/sdk && \
		 echo '===== 收集已编译的固件 =====' && \
		 if [ -f kernel/arch/arm64/boot/Image ]; then \
		   cp kernel/arch/arm64/boot/Image /home/builder/output/ && \
		   cp kernel/arch/arm64/boot/dts/rockchip/rk3588*.dtb /home/builder/output/ 2>/dev/null || true; \
		 fi && \
		 if [ -f u-boot/u-boot.bin ]; then \
		   cp u-boot/u-boot.bin /home/builder/output/ && \
		   cp u-boot/u-boot.img /home/builder/output/ 2>/dev/null || true && \
		   cp u-boot/u-boot.itb /home/builder/output/ 2>/dev/null || true; \
		 fi && \
		 echo '收集完成，宿主机产物目录: ./output/'"

# =============================================================================
# 容器管理
# =============================================================================

shell: ## 进入容器交互式 Shell
	docker compose run --rm rk3588-build /bin/bash

up: ## 启动容器 (后台)
	docker compose up -d

down: ## 停止并删除容器
	docker compose down

logs: ## 查看容器日志
	docker compose logs -f

clean: ## 清理容器和镜像
	docker compose down -v --rmi all

status: ## 查看容器状态
	@echo "=== Docker 容器 ==="
	@docker ps -a --filter name=$(CONTAINER) --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
	@echo ""
	@echo "=== Docker 卷 ==="
	@docker volume ls --filter name=rk3588
	@echo ""
	@echo "=== 磁盘使用 ==="
	@docker system df 2>/dev/null || true
