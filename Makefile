.DEFAULT_GOAL := help

-include .env

.PHONY: help build build-nocache build-builder build-debian-builder \
	register-arm64-binfmt \
	import-local-sdk verify-sdk-volume verify-cokepi-sdk \
	fetch-custom fetch-510 fetch-61 fetch-66 fetch-firefly fetch-radxa \
	fetch-rock5c fetch-orangepi update shell debian-shell \
	use-volume use-volume-rockchip-5.10 use-volume-rockchip-6.1 use-volume-rockchip-6.6 \
	use-volume-firefly use-volume-radxa use-volume-rock5c use-volume-orangepi \
	use-board use-board-evb1 use-board-rock5c use-board-cokepi-plus \
	use-board-cokepi-model use-current \
	build-kernel build-uboot build-rootfs image verify-image pack \
	build-all test-debian-all test-debian-qemu check clean clean-all status \
	require-board require-sdk-volume validate-rootfs prepare-output \
	debian-preflight _use_sdk_switch _use_board_switch _buildroot-rootfs _debian-rootfs \
	_image-one _verify-one

BOARD ?=
ROOTFS ?= buildroot
SDK_VOLUME ?=
DEBIAN_RELEASE ?= 13
ROOTFS_USERNAME ?= rk3588
ROOTFS_PASSWORD ?= rk3588
DEBIAN_MIRROR ?= http://deb.debian.org/debian
DEBIAN_SECURITY_MIRROR ?= http://security.debian.org/debian-security
DEBIAN_ALLOW_ARCHIVE_FALLBACK ?= yes
JOBS ?= 0
ZSTD_LEVEL ?= 6
QEMU_TIMEOUT ?= 600
QEMU_MEMORY_MIB ?= 1024
QEMU_CPUS ?= 2

help:
	@printf '%s\n' \
		'RK3588 full system image build' \
		'' \
		'ROCK 5C Debian 13 complete build and simulated boot test:' \
		'  make build' \
		'  make fetch-rock5c' \
		'  make build-all BOARD=rk3588s-rock-5c SDK_VOLUME=rk3588-sdk-rock5c ROOTFS=debian DEBIAN_RELEASE=13' \
		'  make test-debian-qemu BOARD=rk3588s-rock-5c SDK_VOLUME=rk3588-sdk-rock5c DEBIAN_RELEASE=13' \
		'' \
		'No host QEMU or manual Docker volume setup is required. BOARD/SDK may come from make use-volume-*/use-board-* or CLI.' \
		'' \
		'Environment:' \
		'  make build                         Build the primary Docker builder' \
		'  make build-debian-builder          Optionally prebuild the ARM64 Debian builder' \
		'' \
		'Import an already downloaded SDK (bind-backed volume, no source copy):' \
		'  make import-local-sdk SDK_PATH=/absolute/path SDK_VOLUME=rk3588-sdk-local' \
		'  make verify-sdk-volume SDK_VOLUME=rk3588-sdk-local' \
		'  make verify-cokepi-sdk SDK_VOLUME=rk3588-sdk-cokepi-rkr9' \
		'' \
		'Fetch SDK (each uses a separate volume):' \
		'  make fetch-510                     Rockchip Linux 5.10 -> rk3588-sdk-rockchip-5.10' \
		'  make fetch-61                      Rockchip Linux 6.1 -> rk3588-sdk-rockchip-6.1' \
		'  make fetch-66                      Rockchip Linux 6.6 -> rk3588-sdk-rockchip-6.6' \
		'  make fetch-firefly                 Firefly AIO-3588 -> rk3588-sdk-firefly' \
		'  make fetch-radxa                   Radxa Rock 5B -> rk3588-sdk-radxa' \
		'  make fetch-rock5c                  Radxa Rock 5C -> rk3588-sdk-rock5c' \
		'  make fetch-orangepi                OrangePi 5 -> rk3588-sdk-orangepi' \
		'  make fetch-custom SDK_VOLUME=... MANIFEST=...   Custom local manifest' \
		'  make update SDK_VOLUME=<volume>    Update an existing SDK' \
		'' \
		'Switch active SDK volume (writes .env SDK_VOLUME only):' \
		'  make use-volume                  Interactive volume picker' \
		'  make use-volume-rockchip-5.10      -> rk3588-sdk-rockchip-5.10' \
		'  make use-volume-rockchip-6.1       -> rk3588-sdk-rockchip-6.1' \
		'  make use-volume-rockchip-6.6       -> rk3588-sdk-rockchip-6.6' \
		'  make use-volume-firefly           -> rk3588-sdk-firefly' \
		'  make use-volume-radxa             -> rk3588-sdk-radxa' \
		'  make use-volume-rock5c            -> rk3588-sdk-rock5c' \
		'  make use-volume-orangepi          -> rk3588-sdk-orangepi' \
		'' \
		'Switch active board (writes .env BOARD only):' \
		'  make use-board                    Interactive board picker' \
		'  make use-board-evb1               -> rk3588-evb1-lp4-v10-linux' \
		'  make use-board-rock5c             -> rk3588s-rock-5c' \
		'  make use-board-cokepi-plus        -> rk3588-cokepi-plus-lp4-v10' \
		'  make use-board-cokepi-model       -> rk3588s-cokepi-model-lp4-v10' \
		'  make use-current                  Show current SDK_VOLUME and BOARD' \
		'' \
		'Build components (BOARD and SDK_VOLUME required):' \
		'  make build-kernel [BOARD=...] [SDK_VOLUME=...]' \
		'  make build-uboot  [BOARD=...] [SDK_VOLUME=...]' \
		'  make build-rootfs [BOARD=...] [SDK_VOLUME=...] ROOTFS=buildroot|debian|all' \
		'' \
		'Complete images (BOARD and SDK_VOLUME required):' \
		'  make build-all ROOTFS=buildroot' \
		'  make build-all ROOTFS=debian DEBIAN_RELEASE=13' \
		'  make image      BOARD=... SDK_VOLUME=... ROOTFS=...' \
		'  make verify-image BOARD=... SDK_VOLUME=... ROOTFS=...' \
		'  make test-debian-all BOARD=... SDK_VOLUME=...' \
		'  make test-debian-qemu BOARD=... SDK_VOLUME=... DEBIAN_RELEASE=13' \
		'' \
		'Validation:' \
		'  make check'

build:
	SDK_VOLUME=rk3588-sdk-build docker compose build rk3588-build

build-nocache:
	SDK_VOLUME=rk3588-sdk-build docker compose build --no-cache rk3588-build

build-builder:
	SDK_VOLUME=rk3588-sdk-build docker compose build rk3588-build

register-arm64-binfmt:
	@docker_arch=$$(docker info --format '{{.Architecture}}' 2>/dev/null) || { \
		echo "ERROR: Cannot determine the Docker daemon architecture." >&2; \
		exit 1; \
	}; \
	case "$$docker_arch" in \
		amd64|x86_64) \
			echo "Registering ARM64 binfmt emulation on $$docker_arch Docker host..."; \
			docker run --privileged --rm tonistiigi/binfmt --install arm64 >/dev/null ;; \
		arm64|aarch64) \
			echo "Docker host is $$docker_arch; ARM64 binfmt emulation is not required." ;; \
		*) \
			echo "ERROR: Unsupported Docker daemon architecture: $$docker_arch" >&2; \
			exit 1 ;; \
	esac

build-debian-builder: register-arm64-binfmt
	SDK_VOLUME=rk3588-sdk-build docker compose build debian-rootfs

import-local-sdk:
	@SDK_PATH="$(SDK_PATH)" SDK_VOLUME="$(SDK_VOLUME)" \
		bash scripts/import_local_sdk.sh
	@$(MAKE) --no-print-directory _use_sdk_switch SWITCH_VOL="$(SDK_VOLUME)"

verify-sdk-volume: require-sdk-volume
	@docker image inspect rk3588-build:latest >/dev/null 2>&1 || { \
		echo "ERROR: rk3588-build:latest is missing; run 'make build' first." >&2; \
		exit 1; \
	}
	@docker run --rm --user 1000:1000 \
		--mount type=volume,src="$(SDK_VOLUME)",dst=/home/builder/sdk \
		--entrypoint /bin/bash rk3588-build:latest -Eeuo pipefail -c \
		'for component in kernel u-boot rkbin buildroot; do \
			test -d "/home/builder/sdk/$$component" || { \
				echo "Missing SDK component: $$component" >&2; exit 1; \
			}; \
		done; \
		test -w /home/builder/sdk || { \
			echo "SDK root is not writable by the builder user (uid 1000)" >&2; exit 1; \
		}; \
		printf "SDK volume %s is ready at /home/builder/sdk\n" "$(SDK_VOLUME)"'

verify-cokepi-sdk: verify-sdk-volume
	@docker run --rm --user 1000:1000 \
		--mount type=volume,src="$(SDK_VOLUME)",dst=/home/builder/sdk \
		--entrypoint /bin/bash rk3588-build:latest -Eeuo pipefail -c \
		'files=( \
			device/rockchip/.chips/rk3588/rockchip_rk3588_cokepi_lp4_defconfig \
			device/rockchip/.chips/rk3588/rockchip_rk3588s_cokepi_lp4_defconfig \
			kernel/arch/arm64/configs/cokepi_main_defconfig \
			kernel/arch/arm64/boot/dts/rockchip/rk3588-cpp-hdmi.dts \
			kernel/arch/arm64/boot/dts/rockchip/rk3588s-cpm-hdmi1.dts \
			u-boot/configs/rk3588_defconfig \
		); \
		for file in "$${files[@]}"; do \
			test -f "/home/builder/sdk/$$file" || { \
				echo "Missing CokePi SDK file: $$file" >&2; exit 1; \
			}; \
		done; \
		grep -Fq '\''RK_KERNEL_CFG="cokepi_main_defconfig"'\'' \
			/home/builder/sdk/device/rockchip/.chips/rk3588/rockchip_rk3588_cokepi_lp4_defconfig; \
		grep -Fq '\''RK_KERNEL_CFG="cokepi_main_defconfig"'\'' \
			/home/builder/sdk/device/rockchip/.chips/rk3588/rockchip_rk3588s_cokepi_lp4_defconfig; \
		grep -Fq '\''model = "Rockchip RK3588 CokePi Plus LP4 V10 Board";'\'' \
			/home/builder/sdk/kernel/arch/arm64/boot/dts/rockchip/rk3588-cpp-hdmi.dts; \
		grep -Fq '\''model = "Rockchip RK3588S CokePi Model LP4 V10 Board";'\'' \
			/home/builder/sdk/kernel/arch/arm64/boot/dts/rockchip/rk3588s-cpm-hdmi1.dts; \
		printf "CokePi Plus and CokePi Model HDMI definitions are ready in %s\n" "$(SDK_VOLUME)"'

fetch-custom:
	@if [ -z "$(SDK_VOLUME)" ]; then \
		echo "ERROR: SDK_VOLUME is required." >&2; exit 1; \
	fi
	@if [ -z "$(MANIFEST)" ] && { [ -z "$(CUSTOM_MANIFEST_URL)" ] || [ -z "$(CUSTOM_MANIFEST_NAME)" ]; }; then \
		echo "Usage (local):  make fetch-custom SDK_VOLUME=<volume> MANIFEST=<file.xml>" >&2; \
		echo "Usage (remote): make fetch-custom SDK_VOLUME=<volume> CUSTOM_MANIFEST_URL=<url> CUSTOM_MANIFEST_NAME=<file.xml>" >&2; \
		exit 1; \
	fi
	docker volume create $(SDK_VOLUME) >/dev/null
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		-e MANIFEST=$(MANIFEST) \
		-e CUSTOM_MANIFEST_URL=$(CUSTOM_MANIFEST_URL) \
		-e CUSTOM_MANIFEST_NAME=$(CUSTOM_MANIFEST_NAME) \
		rk3588-build bash /home/builder/scripts/fetch_sources.sh

fetch-510: SDK_VOLUME=rk3588-sdk-rockchip-5.10
fetch-510:
	docker volume create $(SDK_VOLUME) >/dev/null
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e MANIFEST=rk3588-linux-5.10.xml -e SDK_VOLUME=rk3588-sdk-rockchip-5.10 rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh

fetch-61: SDK_VOLUME=rk3588-sdk-rockchip-6.1
fetch-61:
	docker volume create $(SDK_VOLUME) >/dev/null
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e MANIFEST=rk3588-linux-6.1.xml -e SDK_VOLUME=rk3588-sdk-rockchip-6.1 rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh

fetch-66: SDK_VOLUME=rk3588-sdk-rockchip-6.6
fetch-66:
	docker volume create $(SDK_VOLUME) >/dev/null
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e MANIFEST=rk3588-linux-6.6.xml -e SDK_VOLUME=rk3588-sdk-rockchip-6.6 rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh

fetch-firefly: SDK_VOLUME=rk3588-sdk-firefly
fetch-firefly:
	docker volume create $(SDK_VOLUME) >/dev/null
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e MANIFEST=rk3588-firefly.xml -e SDK_VOLUME=rk3588-sdk-firefly rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh

fetch-radxa: SDK_VOLUME=rk3588-sdk-radxa
fetch-radxa:
	docker volume create $(SDK_VOLUME) >/dev/null
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e MANIFEST=rk3588-radxa.xml -e SDK_VOLUME=rk3588-sdk-radxa rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh

fetch-rock5c: SDK_VOLUME=rk3588-sdk-rock5c
fetch-rock5c:
	docker volume create $(SDK_VOLUME) >/dev/null
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e BOARD=rk3588s-rock-5c \
		-e MANIFEST=rk3588-rock5c.xml -e SDK_VOLUME=rk3588-sdk-rock5c rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh

fetch-orangepi: SDK_VOLUME=rk3588-sdk-orangepi
fetch-orangepi:
	docker volume create $(SDK_VOLUME) >/dev/null
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e MANIFEST=rk3588-orangepi.xml -e SDK_VOLUME=rk3588-sdk-orangepi rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh


# ---- Switch active SDK volume (writes .env SDK_VOLUME only) ----
_use_sdk_switch:
	@if [ -z "$(SWITCH_VOL)" ]; then echo "Internal target"; exit 1; fi
	touch .env
	@if grep -q '^SDK_VOLUME=' .env; then \
		sed -i 's|^SDK_VOLUME=.*|SDK_VOLUME=$(SWITCH_VOL)|' .env; \
	else \
		echo 'SDK_VOLUME=$(SWITCH_VOL)' >> .env; \
	fi
	@echo "Switched SDK_VOLUME to: $(SWITCH_VOL)"
	@echo "BOARD is unchanged. Use make use-board or make use-board-* to set the board."

use-volume:
	@vols="$$(docker volume ls --filter name=rk3588-sdk --format '{{.Name}}' 2>/dev/null | sort)"; \
	if [ -z "$$vols" ]; then \
		echo "ERROR: no SDK volumes found." >&2; \
		echo "Fetch one first, e.g. make fetch-rock5c" >&2; \
		exit 1; \
	fi; \
	current="$$( [ -f .env ] && grep '^SDK_VOLUME=' .env | cut -d= -f2- || true )"; \
	echo "Available SDK volumes:"; \
	i=0; \
	for vol in $$vols; do \
		i=$$((i+1)); \
		mark=""; \
		[ "$$vol" = "$$current" ] && mark=" (current)"; \
		printf '  %d) %s%s\n' "$$i" "$$vol" "$$mark"; \
	done; \
	printf 'Select volume [1-%d]: ' "$$i" >&2; \
	if ! { read -r choice <>/dev/tty; } 2>/dev/null; then read -r choice; fi; \
	selected=""; \
	if printf '%s' "$$choice" | grep -Eq '^[0-9]+$$'; then \
		j=0; \
		for vol in $$vols; do \
			j=$$((j+1)); \
			if [ "$$j" -eq "$$choice" ]; then selected="$$vol"; break; fi; \
		done; \
	else \
		for vol in $$vols; do \
			if [ "$$vol" = "$$choice" ]; then selected="$$vol"; break; fi; \
		done; \
	fi; \
	if [ -z "$$selected" ]; then \
		echo "ERROR: invalid selection: $$choice" >&2; \
		exit 1; \
	fi; \
	$(MAKE) --no-print-directory _use_sdk_switch SWITCH_VOL="$$selected"

use-volume-rockchip-5.10: SWITCH_VOL=rk3588-sdk-rockchip-5.10
use-volume-rockchip-5.10: _use_sdk_switch
use-volume-rockchip-6.1: SWITCH_VOL=rk3588-sdk-rockchip-6.1
use-volume-rockchip-6.1: _use_sdk_switch
use-volume-rockchip-6.6: SWITCH_VOL=rk3588-sdk-rockchip-6.6
use-volume-rockchip-6.6: _use_sdk_switch
use-volume-firefly: SWITCH_VOL=rk3588-sdk-firefly
use-volume-firefly: _use_sdk_switch
use-volume-radxa: SWITCH_VOL=rk3588-sdk-radxa
use-volume-radxa: _use_sdk_switch
use-volume-rock5c: SWITCH_VOL=rk3588-sdk-rock5c
use-volume-rock5c: _use_sdk_switch
use-volume-orangepi: SWITCH_VOL=rk3588-sdk-orangepi
use-volume-orangepi: _use_sdk_switch

# ---- Switch active board (writes .env BOARD only) ----
_use_board_switch:
	@if [ -z "$(SWITCH_BOARD)" ]; then echo "Internal target"; exit 1; fi
	@if [ ! -f "configs/boards/$(SWITCH_BOARD).conf" ]; then \
		echo "ERROR: unknown board profile: $(SWITCH_BOARD)" >&2; \
		echo "Available board profiles:" >&2; \
		ls -1 configs/boards/*.conf 2>/dev/null | sed 's|.*/||; s|\.conf$$||; s|^|  |' >&2; \
		exit 1; \
	fi
	touch .env
	@if grep -q '^BOARD=' .env; then \
		sed -i 's|^BOARD=.*|BOARD=$(SWITCH_BOARD)|' .env; \
	else \
		echo 'BOARD=$(SWITCH_BOARD)' >> .env; \
	fi
	@echo "Switched BOARD to: $(SWITCH_BOARD)"
	@echo "SDK_VOLUME is unchanged. Use make use-volume or make use-volume-* to set the SDK volume."

use-board:
	@boards="$$(ls -1 configs/boards/*.conf 2>/dev/null | sed 's|.*/||; s|\.conf$$||' | sort)"; \
	if [ -z "$$boards" ]; then \
		echo "ERROR: no board profiles found in configs/boards/" >&2; \
		exit 1; \
	fi; \
	current="$$( [ -f .env ] && grep '^BOARD=' .env | cut -d= -f2- || true )"; \
	echo "Available board profiles:"; \
	i=0; \
	for board in $$boards; do \
		i=$$((i+1)); \
		mark=""; \
		[ "$$board" = "$$current" ] && mark=" (current)"; \
		desc=""; \
		if [ -f "configs/boards/$$board.conf" ]; then \
			desc="$$(grep -E '^BOARD_DESCRIPTION=' "configs/boards/$$board.conf" | head -1 | cut -d= -f2- | sed 's/^"//; s/"$$//')"; \
		fi; \
		if [ -n "$$desc" ]; then \
			printf '  %d) %s - %s%s\n' "$$i" "$$board" "$$desc" "$$mark"; \
		else \
			printf '  %d) %s%s\n' "$$i" "$$board" "$$mark"; \
		fi; \
	done; \
	printf 'Select board [1-%d]: ' "$$i" >&2; \
	if ! { read -r choice <>/dev/tty; } 2>/dev/null; then read -r choice; fi; \
	selected=""; \
	if printf '%s' "$$choice" | grep -Eq '^[0-9]+$$'; then \
		j=0; \
		for board in $$boards; do \
			j=$$((j+1)); \
			if [ "$$j" -eq "$$choice" ]; then selected="$$board"; break; fi; \
		done; \
	else \
		for board in $$boards; do \
			if [ "$$board" = "$$choice" ]; then selected="$$board"; break; fi; \
		done; \
	fi; \
	if [ -z "$$selected" ]; then \
		echo "ERROR: invalid selection: $$choice" >&2; \
		exit 1; \
	fi; \
	$(MAKE) --no-print-directory _use_board_switch SWITCH_BOARD="$$selected"

use-board-evb1: SWITCH_BOARD=rk3588-evb1-lp4-v10-linux
use-board-evb1: _use_board_switch
use-board-rock5c: SWITCH_BOARD=rk3588s-rock-5c
use-board-rock5c: _use_board_switch
use-board-cokepi-plus: SWITCH_BOARD=rk3588-cokepi-plus-lp4-v10
use-board-cokepi-plus: _use_board_switch
use-board-cokepi-model: SWITCH_BOARD=rk3588s-cokepi-model-lp4-v10
use-board-cokepi-model: _use_board_switch

use-current:
	@if [ -f .env ] && grep -q '^SDK_VOLUME=' .env; then \
		echo "Current SDK_VOLUME: $$(grep '^SDK_VOLUME=' .env | cut -d= -f2)"; \
	else \
		echo "SDK_VOLUME not set. Run 'make use-volume' or edit .env"; \
	fi
	@if [ -f .env ] && grep -q '^BOARD=' .env; then \
		echo "Current BOARD: $$(grep '^BOARD=' .env | cut -d= -f2)"; \
	else \
		echo "BOARD not set. Run 'make use-board' or edit .env"; \
	fi

update:
	@if [ -z "$(SDK_VOLUME)" ]; then \
		echo "Usage: make update SDK_VOLUME=<volume>" >&2; \
		echo "" >&2; \
		echo "Available SDK volumes:" >&2; \
		docker volume ls --filter name=rk3588-sdk --format '  {{.Name}}' 2>/dev/null; \
		exit 1; \
	fi
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		rk3588-build bash /home/builder/scripts/fetch_sources.sh update

shell:
	@if [ -z "$(SDK_VOLUME)" ]; then \
		echo "Usage: make shell SDK_VOLUME=<volume>" >&2; \
		exit 1; \
	fi
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		rk3588-build /bin/bash

debian-shell:
	@if [ -z "$(SDK_VOLUME)" ]; then \
		echo "Usage: make debian-shell SDK_VOLUME=<volume>" >&2; \
		exit 1; \
	fi
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		debian-rootfs /bin/bash

prepare-output:
	@mkdir -p output
	@chmod a+rwx output 2>/dev/null || true
	@if [ -d output ]; then find output -type d -exec chmod a+rwx {} + 2>/dev/null || true; fi

require-sdk-volume:
	@if [ -z "$(SDK_VOLUME)" ]; then \
		echo "ERROR: SDK_VOLUME is required." >&2; \
		echo "Use a fetch-* target first, then specify SDK_VOLUME for build targets." >&2; \
		echo "" >&2; \
		echo "Available SDK volumes:" >&2; \
		docker volume ls --filter name=rk3588-sdk --format '  {{.Name}}' 2>/dev/null; \
		echo "" >&2; \
		echo "Example: make use-volume && make use-board && make build-kernel" >&2; \
		echo "Or:      make build-kernel BOARD=rk3588s-rock-5c SDK_VOLUME=rk3588-sdk-rock5c" >&2; \
		exit 1; \
	fi

require-board:
	@test -n "$(strip $(BOARD))" || { \
		echo "ERROR: BOARD is required." >&2; \
		echo "Run a use-board-* target first, set BOARD in .env, or pass BOARD=... on the command line." >&2; \
		echo "" >&2; \
		echo "Available board profiles:" >&2; \
		ls -1 configs/boards/*.conf 2>/dev/null | sed 's|.*/||; s|\.conf$$||; s|^|  |' >&2; \
		echo "" >&2; \
		echo "Example: make use-board && make build-kernel" >&2; \
		echo "Or:      make build-kernel BOARD=rk3588s-rock-5c SDK_VOLUME=rk3588-sdk-rock5c" >&2; \
		exit 2; \
	}

build-kernel: prepare-output require-board require-sdk-volume
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e BOARD="$(BOARD)" -e JOBS="$(JOBS)" \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		rk3588-build bash /home/builder/scripts/build_kernel.sh

build-uboot: prepare-output require-board require-sdk-volume
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e BOARD="$(BOARD)" -e JOBS="$(JOBS)" \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		rk3588-build bash /home/builder/scripts/build_uboot.sh

validate-rootfs:
	@case "$(ROOTFS)" in \
		buildroot|debian|all) ;; \
		*) echo "ROOTFS must be buildroot, debian, or all" >&2; exit 2 ;; \
	esac

build-rootfs: validate-rootfs require-board require-sdk-volume
	@case "$(ROOTFS)" in \
		buildroot) $(MAKE) --no-print-directory _buildroot-rootfs ;; \
		debian) $(MAKE) --no-print-directory _debian-rootfs ;; \
		all) \
			$(MAKE) --no-print-directory _buildroot-rootfs && \
			$(MAKE) --no-print-directory _debian-rootfs ;; \
	esac

_buildroot-rootfs: prepare-output
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e BOARD="$(BOARD)" -e ROOTFS=buildroot \
		-e ROOTFS_USERNAME="$(ROOTFS_USERNAME)" \
		-e ROOTFS_PASSWORD="$(ROOTFS_PASSWORD)" -e JOBS="$(JOBS)" \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		rk3588-build bash /home/builder/scripts/build_buildroot.sh

debian-preflight: build-debian-builder
	@probe_output=$$(SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		--pull never \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		--entrypoint /bin/sh debian-rootfs \
		-c 'printf "RK3588_DEBIAN_ARCH=%s\n" "$$(dpkg --print-architecture)"') || { \
			echo "ERROR: Cannot run the linux/arm64 Debian builder." >&2; \
			exit 1; \
		}; \
	arch=$$(printf '%s\n' "$$probe_output" | \
		sed -n 's/^RK3588_DEBIAN_ARCH=//p' | tail -1); \
	test "$$arch" = "arm64" || { \
		echo "ERROR: Debian builder architecture probe returned '$${arch:-no result}', expected arm64." >&2; \
		exit 1; \
	}; \
	echo "Debian builder architecture: $$arch"

_debian-rootfs: prepare-output debian-preflight
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e BOARD="$(BOARD)" -e ROOTFS=debian \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		-e DEBIAN_RELEASE="$(DEBIAN_RELEASE)" \
		-e ROOTFS_USERNAME="$(ROOTFS_USERNAME)" \
		-e ROOTFS_PASSWORD="$(ROOTFS_PASSWORD)" \
		-e DEBIAN_MIRROR="$(DEBIAN_MIRROR)" \
		-e DEBIAN_SECURITY_MIRROR="$(DEBIAN_SECURITY_MIRROR)" \
		-e DEBIAN_ALLOW_ARCHIVE_FALLBACK="$(DEBIAN_ALLOW_ARCHIVE_FALLBACK)" \
		debian-rootfs bash /home/builder/scripts/build_debian.sh

image: require-board validate-rootfs require-sdk-volume
	@case "$(ROOTFS)" in \
		buildroot) $(MAKE) --no-print-directory _image-one ROOTFS=buildroot SDK_VOLUME=$(SDK_VOLUME) ;; \
		debian) $(MAKE) --no-print-directory _image-one ROOTFS=debian SDK_VOLUME=$(SDK_VOLUME) ;; \
		all) \
			$(MAKE) --no-print-directory _image-one ROOTFS=buildroot SDK_VOLUME=$(SDK_VOLUME) && \
			$(MAKE) --no-print-directory _image-one ROOTFS=debian SDK_VOLUME=$(SDK_VOLUME) ;; \
	esac

_image-one: prepare-output
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e BOARD="$(BOARD)" -e ROOTFS="$(ROOTFS)" \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		-e DEBIAN_RELEASE="$(DEBIAN_RELEASE)" \
		-e ROOTFS_USERNAME="$(ROOTFS_USERNAME)" -e ZSTD_LEVEL="$(ZSTD_LEVEL)" \
		rk3588-build bash /home/builder/scripts/make_image.sh
	$(MAKE) --no-print-directory _verify-one SDK_VOLUME=$(SDK_VOLUME)

verify-image: require-board validate-rootfs require-sdk-volume
	@case "$(ROOTFS)" in \
		buildroot) $(MAKE) --no-print-directory _verify-one ROOTFS=buildroot SDK_VOLUME=$(SDK_VOLUME) ;; \
		debian) $(MAKE) --no-print-directory _verify-one ROOTFS=debian SDK_VOLUME=$(SDK_VOLUME) ;; \
		all) \
			$(MAKE) --no-print-directory _verify-one ROOTFS=buildroot SDK_VOLUME=$(SDK_VOLUME) && \
			$(MAKE) --no-print-directory _verify-one ROOTFS=debian SDK_VOLUME=$(SDK_VOLUME) ;; \
	esac

_verify-one: prepare-output
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e BOARD="$(BOARD)" -e ROOTFS="$(ROOTFS)" \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		-e DEBIAN_RELEASE="$(DEBIAN_RELEASE)" \
		-e ROOTFS_USERNAME="$(ROOTFS_USERNAME)" \
		rk3588-build bash /home/builder/scripts/verify_image.sh

pack: image

build-all: require-board validate-rootfs require-sdk-volume
	$(MAKE) --no-print-directory build-uboot BOARD="$(BOARD)" SDK_VOLUME=$(SDK_VOLUME)
	$(MAKE) --no-print-directory build-kernel BOARD="$(BOARD)" SDK_VOLUME=$(SDK_VOLUME)
	$(MAKE) --no-print-directory build-rootfs BOARD="$(BOARD)" ROOTFS="$(ROOTFS)" SDK_VOLUME=$(SDK_VOLUME)
	$(MAKE) --no-print-directory image BOARD="$(BOARD)" ROOTFS="$(ROOTFS)" SDK_VOLUME=$(SDK_VOLUME)

test-debian-all: require-board require-sdk-volume
	$(MAKE) --no-print-directory build-uboot BOARD="$(BOARD)" SDK_VOLUME=$(SDK_VOLUME)
	$(MAKE) --no-print-directory build-kernel BOARD="$(BOARD)" SDK_VOLUME=$(SDK_VOLUME)
	@for release in 11 12 13; do \
		$(MAKE) --no-print-directory build-rootfs BOARD="$(BOARD)" \
			ROOTFS=debian DEBIAN_RELEASE=$$release SDK_VOLUME=$(SDK_VOLUME) && \
		$(MAKE) --no-print-directory image BOARD="$(BOARD)" \
			ROOTFS=debian DEBIAN_RELEASE=$$release SDK_VOLUME=$(SDK_VOLUME) || exit $$?; \
	done

test-debian-qemu: require-board require-sdk-volume
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e BOARD="$(BOARD)" -e ROOTFS=debian \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		-e DEBIAN_RELEASE="$(DEBIAN_RELEASE)" \
		-e ROOTFS_USERNAME="$(ROOTFS_USERNAME)" \
		-e ROOTFS_PASSWORD="$(ROOTFS_PASSWORD)" \
		-e QEMU_TIMEOUT="$(QEMU_TIMEOUT)" \
		-e QEMU_MEMORY_MIB="$(QEMU_MEMORY_MIB)" \
		-e QEMU_CPUS="$(QEMU_CPUS)" \
		rk3588-build bash /home/builder/scripts/test_debian_qemu.sh

check:
	docker volume create rk3588-sdk-check >/dev/null
	SDK_VOLUME=rk3588-sdk-check docker compose config --quiet
	SDK_VOLUME=rk3588-sdk-check docker compose run --rm --no-deps -T \
		-e SDK_VOLUME=rk3588-sdk-check \
		rk3588-build bash /home/builder/scripts/check.sh

status:
	SDK_VOLUME=$(if $(SDK_VOLUME),$(SDK_VOLUME),rk3588-sdk-status) docker compose ps
	docker volume ls --filter name=rk3588

clean:
	SDK_VOLUME=$(if $(SDK_VOLUME),$(SDK_VOLUME),rk3588-sdk-clean) docker compose down --remove-orphans

clean-all:
	SDK_VOLUME=$(if $(SDK_VOLUME),$(SDK_VOLUME),rk3588-sdk-clean) docker compose down --remove-orphans --volumes --rmi local
