.DEFAULT_GOAL := help

-include .env

.PHONY: help build build-nocache build-builder build-debian-builder \
	fetch fetch-510 fetch-61 fetch-66 fetch-firefly fetch-radxa \
	fetch-orangepi update shell debian-shell \
	build-kernel build-uboot build-rootfs image verify-image pack \
	build-all test-debian-all check clean clean-all status \
	require-board require-sdk-volume validate-rootfs prepare-output \
	debian-preflight _buildroot-rootfs _debian-rootfs _image-one _verify-one

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

help:
	@printf '%s\n' \
		'RK3588 full system image build' \
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
		'  make fetch-orangepi                OrangePi 5 -> rk3588-sdk-orangepi' \
		'  make update SDK_VOLUME=<volume>    Update an existing SDK' \
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
		'' \
		'Validation:' \
		'  make check'

build:
	docker compose build rk3588-build

build-nocache:
	docker compose build --no-cache rk3588-build

build-builder:
	docker compose build rk3588-build

build-debian-builder:
	docker compose build debian-rootfs

fetch:
	@if [ -z "$(SDK_VOLUME)" ]; then \
		echo "Usage: make fetch SDK_VOLUME=<volume> [MANIFEST=<file>]" >&2; \
		echo "Or use a specific fetch target (fetch-510, fetch-radxa, etc.)" >&2; \
		exit 1; \
	fi
	docker compose run --rm -it \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		-e MANIFEST=$(MANIFEST) \
		rk3588-build bash /home/builder/scripts/fetch_sources.sh

fetch-510:
	docker compose run --rm --no-deps -T \
		-e MANIFEST=rk3588-linux-5.10.xml -e SDK_VOLUME=rk3588-sdk-rockchip-5.10 rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh

fetch-61:
	docker compose run --rm --no-deps -T \
		-e MANIFEST=rk3588-linux-6.1.xml -e SDK_VOLUME=rk3588-sdk-rockchip-6.1 rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh

fetch-66:
	docker compose run --rm --no-deps -T \
		-e MANIFEST=rk3588-linux-6.6.xml -e SDK_VOLUME=rk3588-sdk-rockchip-6.6 rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh

fetch-firefly:
	docker compose run --rm --no-deps -T \
		-e MANIFEST=rk3588-firefly.xml -e SDK_VOLUME=rk3588-sdk-firefly rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh

fetch-radxa:
	docker compose run --rm --no-deps -T \
		-e MANIFEST=rk3588-radxa.xml -e SDK_VOLUME=rk3588-sdk-radxa rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh

fetch-orangepi:
	docker compose run --rm --no-deps -T \
		-e MANIFEST=rk3588-orangepi.xml -e SDK_VOLUME=rk3588-sdk-orangepi rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh

update:
	@if [ -z "$(SDK_VOLUME)" ]; then \
		echo "Usage: make update SDK_VOLUME=<volume>" >&2; \
		echo "" >&2; \
		echo "Available SDK volumes:" >&2; \
		docker volume ls --filter name=rk3588-sdk --format '  {{.Name}}' 2>/dev/null; \
		exit 1; \
	fi
	docker compose run --rm --no-deps -T \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		rk3588-build bash /home/builder/scripts/fetch_sources.sh update

shell:
	@if [ -z "$(SDK_VOLUME)" ]; then \
		echo "Usage: make shell SDK_VOLUME=<volume>" >&2; \
		exit 1; \
	fi
	docker compose run --rm \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		rk3588-build /bin/bash

debian-shell:
	@if [ -z "$(SDK_VOLUME)" ]; then \
		echo "Usage: make debian-shell SDK_VOLUME=<volume>" >&2; \
		exit 1; \
	fi
	docker compose run --rm \
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
	docker compose run --rm --no-deps -T \
		-e BOARD="$(BOARD_FOR_COMPONENT)" -e JOBS="$(JOBS)" \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		rk3588-build bash /home/builder/scripts/build_kernel.sh

build-uboot: prepare-output require-sdk-volume
	docker compose run --rm --no-deps -T \
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
	docker compose run --rm --no-deps -T \
		-e BOARD="$(BOARD_FOR_COMPONENT)" -e ROOTFS=buildroot \
		-e ROOTFS_USERNAME="$(ROOTFS_USERNAME)" \
		-e ROOTFS_PASSWORD="$(ROOTFS_PASSWORD)" -e JOBS="$(JOBS)" \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		rk3588-build bash /home/builder/scripts/build_buildroot.sh

debian-preflight:
	@arch=$$(docker compose run --rm --no-deps -T \
		-e SDK_VOLUME=$(SDK_VOLUME) \
		debian-rootfs \
		bash -c 'dpkg --print-architecture 2>/dev/null' 2>/dev/null | tail -1) || { \
			echo "Cannot run the linux/arm64 Debian builder." >&2; \
			echo "Attempting to register ARM64 binfmt emulation..." >&2; \
			docker run --privileged --rm tonistiigi/binfmt --install arm64 >/dev/null 2>&1 || true; \
			arch=$$(docker compose run --rm --no-deps -T \
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
	docker compose run --rm --no-deps -T \
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
	docker compose run --rm --no-deps -T \
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
	docker compose run --rm --no-deps -T \
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

check:
	docker compose config --quiet 2>/dev/null || true
	docker compose run --rm --no-deps -T \
		-e SDK_VOLUME=rk3588-sdk-check \
		rk3588-build bash /home/builder/scripts/check.sh

status:
	docker compose ps
	docker volume ls --filter name=rk3588

clean:
	docker compose down --remove-orphans

clean-all:
	docker compose down --remove-orphans --volumes --rmi local
