# =============================================================================
# RK3588 Docker 编译环境 - 便捷命令
# =============================================================================

.PHONY: build shell fetch build-kernel build-uboot clean help

# 默认配置
IMAGE ?= rk3588-build:latest
CONTAINER ?= rk3588-build

help: ## 显示帮助信息
	@echo ""
	@echo "RK3588 Docker 编译环境 - 可用命令:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""

build: ## 构建 Docker 镜像
	docker compose build

build-nocache: ## 构建 Docker 镜像 (无缓存)
	docker compose build --no-cache

shell: ## 进入容器交互式 Shell
	docker compose run --rm rk3588-build /bin/bash

fetch: ## 拉取完整 SDK (交互选择版本)
	docker compose run --rm -e FETCH_ON_START=yes -it rk3588-build /bin/bash -c \
		"/home/builder/fetch_sources.sh && echo 'SDK 拉取完成'"

fetch-510: ## 拉取 SDK Linux 5.10 LTS
	docker compose run --rm -e FETCH_ON_START=yes -e MANIFEST=rk3588-linux-5.10.xml rk3588-build /bin/bash -c \
		"/home/builder/fetch_sources.sh && echo 'SDK 拉取完成'"

fetch-61: ## 拉取 SDK Linux 6.1 LTS
	docker compose run --rm -e FETCH_ON_START=yes -e MANIFEST=rk3588-linux-6.1.xml rk3588-build /bin/bash -c \
		"/home/builder/fetch_sources.sh && echo 'SDK 拉取完成'"

fetch-66: ## 拉取 SDK Linux 6.6
	docker compose run --rm -e FETCH_ON_START=yes -e MANIFEST=rk3588-linux-6.6.xml rk3588-build /bin/bash -c \
		"/home/builder/fetch_sources.sh && echo 'SDK 拉取完成'"

build-kernel: ## 编译 Kernel (需先拉取源码)
	docker compose run --rm rk3588-build /bin/bash -c \
		"cd /home/builder/sdk/kernel && \
		 make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- rockchip_linux_defconfig && \
		 make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j\$$(nproc)"

build-uboot: ## 编译 U-Boot (需先拉取源码)
	docker compose run --rm rk3588-build /bin/bash -c \
		"cd /home/builder/sdk/u-boot && \
		 make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- rk3588_defconfig && \
		 make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j\$$(nproc)"

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
