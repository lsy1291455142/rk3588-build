.DEFAULT_GOAL := help

-include .env

.PHONY: help build build-nocache build-builder build-debian-builder \
	register-arm64-binfmt \
	fetch-custom fetch-510 fetch-61 fetch-66 fetch-firefly fetch-radxa \
	fetch-rock5c fetch-orangepi update shell debian-shell \
	use-rockchip-5.10 use-rockchip-6.1 use-rockchip-6.6 \
	use-firefly use-radxa use-rock5c use-orangepi use-current \
	build-kernel build-uboot build-rootfs image verify-image pack \
	build-all test-debian-all test-debian-qemu check clean clean-all status \
	require-board require-sdk-volume validate-rootfs prepare-output \
	debian-preflight _use_switch _buildroot-rootfs _debian-rootfs \
	_image-one _verify-one

DEFAULT_BOARD := rk3588-evb1-lp4-v10-linux
BOARD ?=
BOARD_FOR_COMPONENT = $(if $(strip $(BOARD)),$(BOARD),$(DEFAULT_BOARD))
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
		'  make build-debian-builder' \
		'  make fetch-rock5c' \
		'  make build-all BOARD=rk3588s-rock-5c SDK_VOLUME=rk3588-sdk-rock5c ROOTFS=debian DEBIAN_RELEASE=13' \
		'  make test-debian-qemu BOARD=rk3588s-rock-5c SDK_VOLUME=rk3588-sdk-rock5c DEBIAN_RELEASE=13' \
		'' \
		'No .env file, make use-*, host QEMU, or manual Docker volume setup is required.' \
		'' \
		'Environment:' \
		'  make build                         Build the primary Docker builder' \
		'  make build-debian-builder          Build the ARM64 Debian builder' \
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
		'Switch active SDK (writes .env):' \
		'  make use-rockchip-5.10             -> rk3588-sdk-rockchip-5.10' \
		'  make use-rockchip-6.1              -> rk3588-sdk-rockchip-6.1' \
		'  make use-rockchip-6.6              -> rk3588-sdk-rockchip-6.6' \
		'  make use-firefly                  -> rk3588-sdk-firefly' \
		'  make use-radxa                    -> rk3588-sdk-radxa' \
		'  make use-rock5c                   -> rk3588-sdk-rock5c' \
		'  make use-orangepi                 -> rk3588-sdk-orangepi' \
		'  make use-current                  Show current SDK_VOLUME' \
		'' \
		'Build components (SDK_VOLUME required):' \
		'  make build-kernel SDK_VOLUME=... [BOARD=...]' \
		'  make build-uboot  SDK_VOLUME=... [BOARD=...]' \
		'  make build-rootfs SDK_VOLUME=... [BOARD=...] ROOTFS=buildroot|debian|all' \
		'' \
		'Complete images (BOARD and SDK_VOLUME required):' \
		'  make build-all BOARD=$(DEFAULT_BOARD) SDK_VOLUME=... ROOTFS=buildroot' \
		'  make build-all BOARD=$(DEFAULT_BOARD) SDK_VOLUME=... ROOTFS=debian DEBIAN_RELEASE=13' \
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
	docker run --privileged --rm tonistiigi/binfmt --install arm64 >/dev/null

build-debian-builder: register-arm64-binfmt
	SDK_VOLUME=rk3588-sdk-build docker compose build debian-rootfs

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


# ---- Switch active SDK (writes .env) ----
_use_switch:
	@if [ -z "$(SWITCH_VOL)" ]; then echo "Internal target"; exit 1; fi
	touch .env
	@if grep -q '^SDK_VOLUME=' .env; then \
		sed -i 's|^SDK_VOLUME=.*|SDK_VOLUME=$(SWITCH_VOL)|' .env; \
	else \
		echo 'SDK_VOLUME=$(SWITCH_VOL)' >> .env; \
	fi
	@echo "Switched to: $(SWITCH_VOL)"
	@echo "All make commands now use this SDK volume."

use-rockchip-5.10: SWITCH_VOL=rk3588-sdk-rockchip-5.10
use-rockchip-5.10: _use_switch
use-rockchip-6.1: SWITCH_VOL=rk3588-sdk-rockchip-6.1
use-rockchip-6.1: _use_switch
use-rockchip-6.6: SWITCH_VOL=rk3588-sdk-rockchip-6.6
use-rockchip-6.6: _use_switch
use-firefly: SWITCH_VOL=rk3588-sdk-firefly
use-firefly: _use_switch
use-radxa: SWITCH_VOL=rk3588-sdk-radxa
use-radxa: _use_switch
use-rock5c: SWITCH_VOL=rk3588-sdk-rock5c
use-rock5c: _use_switch
use-orangepi: SWITCH_VOL=rk3588-sdk-orangepi
use-orangepi: _use_switch

use-current:
	@if [ -f .env ] && grep -q '^SDK_VOLUME=' .env; then \
		echo "Current SDK_VOLUME: $$(grep '^SDK_VOLUME=' .env | cut -d= -f2)"; \
	else \
		echo "SDK_VOLUME not set. Run 'make use-rockchip-5.10' or edit .env"; \
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
		echo "Example: make build-kernel SDK_VOLUME=rk3588-sdk-rockchip-5.10" >&2; \
		exit 1; \
	fi

build-kernel: prepare-output require-sdk-volume
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e BOARD="$(BOARD_FOR_COMPONENT)" -e JOBS="$(JOBS)" \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		rk3588-build bash /home/builder/scripts/build_kernel.sh

build-uboot: prepare-output require-sdk-volume
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e BOARD="$(BOARD_FOR_COMPONENT)" -e JOBS="$(JOBS)" \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		rk3588-build bash /home/builder/scripts/build_uboot.sh

validate-rootfs:
	@case "$(ROOTFS)" in \
		buildroot|debian|all) ;; \
		*) echo "ROOTFS must be buildroot, debian, or all" >&2; exit 2 ;; \
	esac

build-rootfs: validate-rootfs require-sdk-volume
	@case "$(ROOTFS)" in \
		buildroot) $(MAKE) --no-print-directory _buildroot-rootfs ;; \
		debian) $(MAKE) --no-print-directory _debian-rootfs ;; \
		all) \
			$(MAKE) --no-print-directory _buildroot-rootfs && \
			$(MAKE) --no-print-directory _debian-rootfs ;; \
	esac

_buildroot-rootfs: prepare-output
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e BOARD="$(BOARD_FOR_COMPONENT)" -e ROOTFS=buildroot \
		-e ROOTFS_USERNAME="$(ROOTFS_USERNAME)" \
		-e ROOTFS_PASSWORD="$(ROOTFS_PASSWORD)" -e JOBS="$(JOBS)" \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		rk3588-build bash /home/builder/scripts/build_buildroot.sh

debian-preflight:
	@arch=$$(SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		debian-rootfs \
		bash -c 'dpkg --print-architecture 2>/dev/null' 2>/dev/null | tail -1) || { \
			echo "Cannot run the linux/arm64 Debian builder." >&2; \
			echo "Attempting to register ARM64 binfmt emulation..." >&2; \
			docker run --privileged --rm tonistiigi/binfmt --install arm64 >/dev/null 2>&1 || true; \
			arch=$$(SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
				-e SDK_VOLUME=$(SDK_VOLUME) \
				debian-rootfs \
				bash -c 'dpkg --print-architecture 2>/dev/null' 2>/dev/null | tail -1) || { \
				echo "Still cannot run the linux/arm64 Debian builder." >&2; \
				echo "Run 'make build-debian-builder' and ensure Docker ARM64/binfmt support is available." >&2; \
				exit 1; \
			}; \
		}; \
	test "$$arch" = "arm64" || { \
		echo "Debian builder returned '$$arch', expected arm64." >&2; \
		exit 1; \
	}

_debian-rootfs: prepare-output debian-preflight
	SDK_VOLUME=$(SDK_VOLUME) docker compose run --rm --no-deps -T \
		-e BOARD="$(BOARD_FOR_COMPONENT)" -e ROOTFS=debian \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		-e DEBIAN_RELEASE="$(DEBIAN_RELEASE)" \
		-e ROOTFS_USERNAME="$(ROOTFS_USERNAME)" \
		-e ROOTFS_PASSWORD="$(ROOTFS_PASSWORD)" \
		-e DEBIAN_MIRROR="$(DEBIAN_MIRROR)" \
		-e DEBIAN_SECURITY_MIRROR="$(DEBIAN_SECURITY_MIRROR)" \
		-e DEBIAN_ALLOW_ARCHIVE_FALLBACK="$(DEBIAN_ALLOW_ARCHIVE_FALLBACK)" \
		debian-rootfs bash /home/builder/scripts/build_debian.sh

require-board:
	@test -n "$(strip $(BOARD))" || { \
		echo "BOARD is required for final images." >&2; \
		echo "Example: make build-all BOARD=$(DEFAULT_BOARD) SDK_VOLUME=... ROOTFS=buildroot" >&2; \
		exit 2; \
	}

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
