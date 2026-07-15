.DEFAULT_GOAL := help

-include .env

.PHONY: help build build-nocache build-builder build-debian-builder \
	fetch fetch-510 fetch-61 fetch-66 fetch-firefly fetch-radxa \
	fetch-orangepi update shell debian-shell \
	build-kernel build-uboot build-rootfs image verify-image pack \
	build-all test-debian-all check clean clean-all status \
	require-board validate-rootfs prepare-output debian-preflight \
	_buildroot-rootfs _debian-rootfs _image-one _verify-one

DEFAULT_BOARD := rk3588-evb1-lp4-v10-linux
BOARD ?=
BOARD_FOR_COMPONENT = $(if $(strip $(BOARD)),$(BOARD),$(DEFAULT_BOARD))
ROOTFS ?= buildroot
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
		'  make fetch-510                     Fetch the Rockchip Linux 5.10 SDK' \
		'  make shell                         Open the primary build container' \
		'' \
		'Components (BOARD defaults to $(DEFAULT_BOARD)):' \
		'  make build-kernel [BOARD=...]' \
		'  make build-uboot [BOARD=...]' \
		'  make build-rootfs [BOARD=...] ROOTFS=buildroot|debian|all' \
		'' \
		'Complete images (BOARD is required):' \
		'  make build-all BOARD=$(DEFAULT_BOARD) ROOTFS=buildroot' \
		'  make build-all BOARD=$(DEFAULT_BOARD) ROOTFS=debian DEBIAN_RELEASE=13' \
		'  make build-all BOARD=$(DEFAULT_BOARD) ROOTFS=all DEBIAN_RELEASE=13' \
		'  make image BOARD=... ROOTFS=...' \
		'  make verify-image BOARD=... ROOTFS=...' \
		'  make test-debian-all BOARD=...      Build Debian 11, 12, and 13 images' \
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
	docker compose run --rm -it rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh

fetch-510:
	docker compose run --rm --no-deps -T \
		-e MANIFEST=rk3588-linux-5.10.xml rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh

fetch-61:
	docker compose run --rm --no-deps -T \
		-e MANIFEST=rk3588-linux-6.1.xml rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh

fetch-66:
	docker compose run --rm --no-deps -T \
		-e MANIFEST=rk3588-linux-6.6.xml rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh

fetch-firefly:
	docker compose run --rm --no-deps -T \
		-e MANIFEST=rk3588-firefly.xml rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh

fetch-radxa:
	docker compose run --rm --no-deps -T \
		-e MANIFEST=rk3588-radxa.xml rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh

fetch-orangepi:
	docker compose run --rm --no-deps -T \
		-e MANIFEST=rk3588-orangepi.xml rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh

update:
	docker compose run --rm --no-deps -T rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh update

shell:
	docker compose run --rm rk3588-build /bin/bash

debian-shell:
	docker compose run --rm debian-rootfs /bin/bash

prepare-output:
	@mkdir -p output
	@chmod a+rwx output 2>/dev/null || true

build-kernel: prepare-output
	docker compose run --rm --no-deps -T \
		-e BOARD="$(BOARD_FOR_COMPONENT)" -e JOBS="$(JOBS)" \
		rk3588-build bash /home/builder/scripts/build_kernel.sh

build-uboot: prepare-output
	docker compose run --rm --no-deps -T \
		-e BOARD="$(BOARD_FOR_COMPONENT)" -e JOBS="$(JOBS)" \
		rk3588-build bash /home/builder/scripts/build_uboot.sh

validate-rootfs:
	@case "$(ROOTFS)" in \
		buildroot|debian|all) ;; \
		*) echo "ROOTFS must be buildroot, debian, or all" >&2; exit 2 ;; \
	esac

build-rootfs: validate-rootfs
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
		rk3588-build bash /home/builder/scripts/build_buildroot.sh

debian-preflight:
	@arch=$$(docker compose run --rm --no-deps -T debian-rootfs \
		dpkg --print-architecture 2>/dev/null) || { \
			echo "Cannot run the linux/arm64 Debian builder." >&2; \
			echo "Run 'make build-debian-builder' and enable Docker ARM64/binfmt support." >&2; \
			exit 1; \
		}; \
	test "$$arch" = arm64 || { \
		echo "Debian builder returned '$$arch', expected arm64." >&2; \
		exit 1; \
	}

_debian-rootfs: prepare-output debian-preflight
	docker compose run --rm --no-deps -T \
		-e BOARD="$(BOARD_FOR_COMPONENT)" -e ROOTFS=debian \
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
		echo "Example: make build-all BOARD=$(DEFAULT_BOARD) ROOTFS=buildroot" >&2; \
		exit 2; \
	}

image: require-board validate-rootfs
	@case "$(ROOTFS)" in \
		buildroot) $(MAKE) --no-print-directory _image-one ROOTFS=buildroot ;; \
		debian) $(MAKE) --no-print-directory _image-one ROOTFS=debian ;; \
		all) \
			$(MAKE) --no-print-directory _image-one ROOTFS=buildroot && \
			$(MAKE) --no-print-directory _image-one ROOTFS=debian ;; \
	esac

_image-one: prepare-output
	docker compose run --rm --no-deps -T \
		-e BOARD="$(BOARD)" -e ROOTFS="$(ROOTFS)" \
		-e DEBIAN_RELEASE="$(DEBIAN_RELEASE)" \
		-e ROOTFS_USERNAME="$(ROOTFS_USERNAME)" -e ZSTD_LEVEL="$(ZSTD_LEVEL)" \
		rk3588-build bash /home/builder/scripts/make_image.sh
	$(MAKE) --no-print-directory _verify-one

verify-image: require-board validate-rootfs
	@case "$(ROOTFS)" in \
		buildroot) $(MAKE) --no-print-directory _verify-one ROOTFS=buildroot ;; \
		debian) $(MAKE) --no-print-directory _verify-one ROOTFS=debian ;; \
		all) \
			$(MAKE) --no-print-directory _verify-one ROOTFS=buildroot && \
			$(MAKE) --no-print-directory _verify-one ROOTFS=debian ;; \
	esac

_verify-one: prepare-output
	docker compose run --rm --no-deps -T \
		-e BOARD="$(BOARD)" -e ROOTFS="$(ROOTFS)" \
		-e DEBIAN_RELEASE="$(DEBIAN_RELEASE)" \
		-e ROOTFS_USERNAME="$(ROOTFS_USERNAME)" \
		rk3588-build bash /home/builder/scripts/verify_image.sh

pack: image

build-all: require-board validate-rootfs
	$(MAKE) --no-print-directory build-uboot BOARD="$(BOARD)"
	$(MAKE) --no-print-directory build-kernel BOARD="$(BOARD)"
	$(MAKE) --no-print-directory build-rootfs BOARD="$(BOARD)" ROOTFS="$(ROOTFS)"
	$(MAKE) --no-print-directory image BOARD="$(BOARD)" ROOTFS="$(ROOTFS)"

test-debian-all: require-board
	$(MAKE) --no-print-directory build-uboot BOARD="$(BOARD)"
	$(MAKE) --no-print-directory build-kernel BOARD="$(BOARD)"
	@for release in 11 12 13; do \
		$(MAKE) --no-print-directory build-rootfs BOARD="$(BOARD)" \
			ROOTFS=debian DEBIAN_RELEASE=$$release && \
		$(MAKE) --no-print-directory image BOARD="$(BOARD)" \
			ROOTFS=debian DEBIAN_RELEASE=$$release || exit $$?; \
	done

check:
	docker compose config --quiet
	docker compose run --rm --no-deps -T rk3588-build \
		bash /home/builder/scripts/check.sh

status:
	docker compose ps
	docker volume ls --filter name=rk3588

clean:
	docker compose down --remove-orphans

clean-all:
	docker compose down --remove-orphans --volumes --rmi local
