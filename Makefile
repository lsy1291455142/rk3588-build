.DEFAULT_GOAL := menu

-include .env

.PHONY: help menu build build-nocache build-builder build-debian-builder \
	register-arm64-binfmt \
	import-local-sdk verify-sdk-volume \
	fetch fetch-custom update shell debian-shell \
	use-volume use-board use-rootfs use-rootfs-buildroot use-rootfs-debian \
	use-rootfs-all use-current \
	build-kernel build-uboot build-rootfs image verify-image pack \
	build-all test-debian-all test-debian-qemu check clean clean-all status \
	require-board require-rootfs require-sdk-volume validate-rootfs prepare-output \
	debian-preflight _use_sdk_switch _use_board_switch _use_rootfs_switch \
	_buildroot-rootfs _debian-rootfs \
	_image-one _verify-one \
	list-boards new-board validate-board info

BOARD ?=
ROOTFS ?=
SDK_VOLUME ?=

# Load SDK_VOLUME and SOURCE_MANIFEST from board profile when BOARD is set
ifneq ($(strip $(BOARD)),)
  _BOARD_CONF := configs/boards/$(BOARD).conf
  ifneq ($(wildcard $(_BOARD_CONF)),)
    _SOURCE_MANIFEST := $(shell grep '^SOURCE_MANIFEST=' $(_BOARD_CONF) | cut -d= -f2- | tr -d '"')
    # Auto-derive SDK_VOLUME from manifest if not explicitly set
    ifeq ($(SDK_VOLUME),)
      ifneq ($(_SOURCE_MANIFEST),)
        SDK_VOLUME := rk3588-sdk-$(shell echo '$(_SOURCE_MANIFEST)' | sed 's/^rk3588-//;s/\.xml$$//')
      endif
    endif
  endif
endif

DEBIAN_RELEASE ?= 13
ROOTFS_USERNAME ?= user
ROOTFS_PASSWORD ?= password
ROOTFS_HOSTNAME ?=
DEBIAN_PACKAGES ?=
DEBIAN_FEATURES ?=
DEBIAN_OVERLAYS ?=
DEBIAN_EXTRA_PACKAGES ?=
WIFIBT_CHIP ?=
WIFIBT_SOURCE ?=
WIFIBT_REQUIRED ?=
DEBIAN_MIRROR ?= http://deb.debian.org/debian
DEBIAN_SECURITY_MIRROR ?= http://security.debian.org/debian-security
DEBIAN_ALLOW_ARCHIVE_FALLBACK ?= yes
JOBS ?= 0
ZSTD_LEVEL ?= 6
QEMU_TIMEOUT ?= 600
QEMU_MEMORY_MIB ?= 1024
QEMU_CPUS ?= 2

menu:
	@board="$$( [ -f .env ] && grep '^BOARD=' .env | cut -d= -f2- || true )"; \
	sdk="$$( [ -f .env ] && grep '^SDK_VOLUME=' .env | cut -d= -f2- || true )"; \
	rootfs="$$( [ -f .env ] && grep '^ROOTFS=' .env | cut -d= -f2- || true )"; \
	printf '%s\n' \
		'=== SBC Build Menu ===' \
		"BOARD=$${board:-(not set)}  SDK_VOLUME=$${sdk:-(not set)}  ROOTFS=$${rootfs:-(not set)}" \
		'' \
		'Environment / switch' \
		'  1) build                 Build the primary Docker builder' \
		'  2) use-volume            Interactive SDK volume picker' \
		'  3) use-board             Interactive board picker' \
		'  4) use-rootfs            Interactive rootfs picker' \
		'  5) use-current           Show current BOARD/SDK/ROOTFS' \
		'  6) info                  Show build environment details' \
		'' \
		'SDK' \
		'  7) fetch                 Fetch SDK via board SOURCE_MANIFEST' \
		'  8) update                Update an existing SDK volume' \
		'  9) verify-sdk-volume     Verify SDK volume contents' \
		' 10) shell                 Open builder shell' \
		'' \
		'Build' \
		' 11) build-kernel          Build kernel' \
		' 12) build-uboot           Build U-Boot' \
		' 13) build-rootfs          Build root filesystem' \
		' 14) build-all             Build all components' \
		' 15) image                 Assemble disk image' \
		' 16) verify-image          Verify disk image' \
		' 17) pack                  Build image package' \
		'' \
		'Test / misc' \
		' 18) test-debian-qemu      QEMU boot test (Debian)' \
		' 19) check                 Run project checks' \
		' 20) status                Show compose/volume status' \
		' 21) list-boards           List board profiles' \
		' 22) help                  Full command reference' \
		' 23) clean                 Stop containers' \
		' 24) clean-all             Remove containers, volumes, images' \
		'  0) exit' \
		''; >&2; \
	printf 'Select [0-24] or target name: ' >&2; \
	if ! { read -r choice <>/dev/tty; } 2>/dev/null; then read -r choice; fi; \
	target=""; \
	case "$$choice" in \
		0|"") echo "Bye."; exit 0 ;; \
		1) target=build ;; \
		2) target=use-volume ;; \
		3) target=use-board ;; \
		4) target=use-rootfs ;; \
		5) target=use-current ;; \
		6) target=info ;; \
		7) target=fetch ;; \
		8) target=update ;; \
		9) target=verify-sdk-volume ;; \
		10) target=shell ;; \
		11) target=build-kernel ;; \
		12) target=build-uboot ;; \
		13) target=build-rootfs ;; \
		14) target=build-all ;; \
		15) target=image ;; \
		16) target=verify-image ;; \
		17) target=pack ;; \
		18) target=test-debian-qemu ;; \
		19) target=check ;; \
		20) target=status ;; \
		21) target=list-boards ;; \
		22) target=help ;; \
		23) target=clean ;; \
		24) target=clean-all ;; \
		help|menu|build|build-nocache|build-builder|build-debian-builder| \
		register-arm64-binfmt|import-local-sdk|verify-sdk-volume| \
		fetch|fetch-custom|update|shell|debian-shell|use-volume|use-board|use-rootfs| \
		use-rootfs-buildroot|use-rootfs-debian|use-rootfs-all|use-current| \
		build-kernel|build-uboot|build-rootfs|image|verify-image|pack|build-all| \
		test-debian-all|test-debian-qemu|check|clean|clean-all|status|list-boards| \
		new-board|validate-board|info) target="$$choice" ;; \
		*) \
			echo "ERROR: invalid selection: $$choice" >&2; \
			echo "Tip: enter a number 0-24, or a make target name." >&2; \
			exit 1 ;; \
	esac; \
	echo ">>> make $$target"; \
	$(MAKE) --no-print-directory $$target

help:
	@printf '%s\n' \
		'SBC Linux image build' \
		'' \
		'Interactive menu (default):' \
		'  make                            Numbered target menu' \
		'  make menu                       Same as above' \
		'' \
		'ROCK 5C Debian 13 complete build and simulated boot test:' \
		'  make build' \
		'  make fetch BOARD=rk3588s-rock-5c' \
		'  make build-all BOARD=rk3588s-rock-5c SDK_VOLUME=rk3588-sdk-rock5c ROOTFS=debian DEBIAN_RELEASE=13' \
		'  make test-debian-qemu BOARD=rk3588s-rock-5c SDK_VOLUME=rk3588-sdk-rock5c DEBIAN_RELEASE=13' \
		'' \
		'No host QEMU or manual Docker volume setup is required. BOARD/SDK/ROOTFS may come from use targets or CLI.' \
		'' \
		'Environment:' \
		'  make build                         Build the primary Docker builder' \
		'  make build-debian-builder          Optionally prebuild the ARM64 Debian builder' \
		'' \
		'Import an already downloaded SDK (bind-backed volume, no source copy):' \
		'  make import-local-sdk SDK_PATH=/absolute/path SDK_VOLUME=rk3588-sdk-local' \
		'  make verify-sdk-volume SDK_VOLUME=rk3588-sdk-local' \
		'' \
		'Fetch SDK (each uses a separate volume):' \
		'  make fetch BOARD=<board>           Fetch SDK based on board profile manifest' \
		'  make fetch-custom SDK_VOLUME=... MANIFEST=...   Custom local manifest' \
		'  make update SDK_VOLUME=<volume>    Update an existing SDK' \
		'' \
		'Switch active SDK volume (writes .env SDK_VOLUME only):' \
		'  make use-volume                  Interactive volume picker' \
		'' \
		'Switch active board (writes .env BOARD only):' \
		'  make use-board                   Interactive board picker' \
		'  make use-board BOARD=<board>     Switch to a specific board without prompt' \
		'' \
		'Switch active root filesystem (writes .env ROOTFS only):' \
		'  make use-rootfs                  Interactive rootfs picker' \
		'  make use-rootfs-buildroot         -> buildroot' \
		'  make use-rootfs-debian            -> debian' \
		'  make use-rootfs-all               -> all' \
		'  make use-current                  Show current SDK_VOLUME, BOARD, and ROOTFS' \
		'' \
		'Board Management:' \
		'  make list-boards                   List all available board profiles' \
		'  make new-board BOARD=<name>        Create a new board profile from TEMPLATE' \
		'  make validate-board BOARD=<name>   Validate a board profile syntax' \
		'  make info                          Show current build environment info' \
		'' \
		'Build components (configured values may come from .env or CLI):' \
		'  make build-kernel [BOARD=...] [SDK_VOLUME=...]' \
		'  make build-uboot  [BOARD=...] [SDK_VOLUME=...]' \
		'  make build-rootfs [BOARD=...] [SDK_VOLUME=...] [ROOTFS=...]' \
		'' \
		'Complete images (BOARD, SDK_VOLUME, and ROOTFS required):' \
		'  make build-all [DEBIAN_RELEASE=13] [DEBIAN_PACKAGES=network-manager,wpasupplicant] [DEBIAN_OVERLAYS=base,network]' \
		'  make image' \
		'  make verify-image' \
		'  make test-debian-all BOARD=... SDK_VOLUME=...' \
		'  make test-debian-qemu BOARD=... SDK_VOLUME=... DEBIAN_RELEASE=13' \
		'  DEBIAN_PACKAGES=exact apt names (comma/space); empty=board default/minbase; none=force minbase' \
		'  DEBIAN_OVERLAYS=optional overlays (base,console,firstboot,firstboot-info,network,wifibt); none|all' \
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

fetch: require-board
	@if [ -z "$(_SOURCE_MANIFEST)" ]; then \
		echo "ERROR: Board $(BOARD) does not define SOURCE_MANIFEST." >&2; \
		echo "This board expects a local SDK import, or a custom manifest." >&2; \
		echo "  make import-local-sdk SDK_PATH=/path/to/sdk SDK_VOLUME=<volume>" >&2; \
		echo "  make fetch-custom SDK_VOLUME=<volume> MANIFEST=<file.xml>" >&2; \
		exit 1; \
	fi
	@# Prefer CLI SDK_VOLUME; otherwise always derive from SOURCE_MANIFEST
	@# so an unrelated .env volume is not reused for a different board fetch.
	@if [ "$(origin SDK_VOLUME)" = "command line" ] && [ -n "$(strip $(SDK_VOLUME))" ]; then \
		fetch_vol="$(SDK_VOLUME)"; \
	else \
		fetch_vol="rk3588-sdk-$$(printf '%s' "$(_SOURCE_MANIFEST)" | sed 's/^rk3588-//;s/\.xml$$//')"; \
	fi; \
	if [ -z "$$fetch_vol" ]; then \
		echo "ERROR: cannot determine SDK_VOLUME for fetch." >&2; \
		exit 1; \
	fi; \
	echo "Fetching SDK for $(BOARD) using manifest $(_SOURCE_MANIFEST) -> volume $$fetch_vol"; \
	docker volume create "$$fetch_vol" >/dev/null; \
	SDK_VOLUME="$$fetch_vol" docker compose run --rm --no-deps -T \
		-e BOARD="$(BOARD)" \
		-e MANIFEST=$(_SOURCE_MANIFEST) -e SDK_VOLUME="$$fetch_vol" rk3588-build \
		bash /home/builder/scripts/fetch_sources.sh; \
	$(MAKE) --no-print-directory _use_sdk_switch SWITCH_VOL="$$fetch_vol"


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
	@echo "BOARD is unchanged. Use make use-board to set the board."

use-volume:
	@vols="$$(docker volume ls --filter name=rk3588-sdk --format '{{.Name}}' 2>/dev/null | sort)"; \
	if [ -z "$$vols" ]; then \
		echo "ERROR: no SDK volumes found." >&2; \
		echo "Fetch/import one first, e.g. make fetch BOARD=rk3588s-rock-5c" >&2; \
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
	@manifest=$$(grep '^SOURCE_MANIFEST=' "configs/boards/$(SWITCH_BOARD).conf" | head -1 | cut -d= -f2- | tr -d '"'); \
	if [ -n "$$manifest" ]; then \
		derived="rk3588-sdk-$$(printf '%s' "$$manifest" | sed 's/^rk3588-//;s/\.xml$$//')"; \
		current_sdk="$$(grep '^SDK_VOLUME=' .env 2>/dev/null | cut -d= -f2- || true)"; \
		if [ -z "$$current_sdk" ]; then \
			if grep -q '^SDK_VOLUME=' .env 2>/dev/null; then \
				sed -i "s|^SDK_VOLUME=.*|SDK_VOLUME=$$derived|" .env; \
			else \
				echo "SDK_VOLUME=$$derived" >> .env; \
			fi; \
			echo "SDK_VOLUME was empty; derived from SOURCE_MANIFEST: $$derived"; \
		elif [ "$$current_sdk" != "$$derived" ]; then \
			echo "SDK_VOLUME is unchanged: $$current_sdk"; \
			echo "Board default volume would be: $$derived"; \
			echo "Run 'make use-volume' if you want to switch the SDK volume."; \
		else \
			echo "SDK_VOLUME already matches board default: $$current_sdk"; \
		fi; \
	else \
		echo "Board has no SOURCE_MANIFEST (local SDK board)."; \
		echo "SDK_VOLUME is unchanged. Import with 'make import-local-sdk' or pick via 'make use-volume'."; \
	fi

# BOARD on command line (make use-board BOARD=xxx) switches directly.
# Bare 'make use-board' always prompts, even if .env already has BOARD.
use-board:
	@if [ "$(origin BOARD)" = "command line" ]; then \
		$(MAKE) --no-print-directory _use_board_switch SWITCH_BOARD="$(BOARD)"; \
	else \
		boards="$$(ls -1 configs/boards/*.conf 2>/dev/null | sed 's|.*/||; s|\.conf$$||' | grep -v '^TEMPLATE$$' | sort)"; \
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
		$(MAKE) --no-print-directory _use_board_switch SWITCH_BOARD="$$selected"; \
	fi

# ---- Switch active root filesystem (writes .env ROOTFS only) ----
_use_rootfs_switch:
	@case "$(SWITCH_ROOTFS)" in \
		buildroot|debian|all) ;; \
		*) echo "ERROR: unsupported rootfs: $(SWITCH_ROOTFS)" >&2; exit 1 ;; \
	esac
	touch .env
	@if grep -q '^ROOTFS=' .env; then \
		sed -i 's|^ROOTFS=.*|ROOTFS=$(SWITCH_ROOTFS)|' .env; \
	else \
		echo 'ROOTFS=$(SWITCH_ROOTFS)' >> .env; \
	fi
	@echo "Switched ROOTFS to: $(SWITCH_ROOTFS)"
	@echo "SDK_VOLUME and BOARD are unchanged."

use-rootfs:
	@current="$$( [ -f .env ] && grep '^ROOTFS=' .env | cut -d= -f2- || true )"; \
	echo "Available root filesystems:"; \
	i=0; \
	for rootfs in buildroot debian all; do \
		i=$$((i+1)); \
		mark=""; \
		[ "$$rootfs" = "$$current" ] && mark=" (current)"; \
		printf '  %d) %s%s\n' "$$i" "$$rootfs" "$$mark"; \
	done; \
	printf 'Select rootfs [1-3]: ' >&2; \
	if ! { read -r choice <>/dev/tty; } 2>/dev/null; then read -r choice; fi; \
	case "$$choice" in \
		1|buildroot) selected=buildroot ;; \
		2|debian) selected=debian ;; \
		3|all) selected=all ;; \
		*) echo "ERROR: invalid selection: $$choice" >&2; exit 1 ;; \
	esac; \
	$(MAKE) --no-print-directory _use_rootfs_switch SWITCH_ROOTFS="$$selected"

use-rootfs-buildroot: SWITCH_ROOTFS=buildroot
use-rootfs-buildroot: _use_rootfs_switch
use-rootfs-debian: SWITCH_ROOTFS=debian
use-rootfs-debian: _use_rootfs_switch
use-rootfs-all: SWITCH_ROOTFS=all
use-rootfs-all: _use_rootfs_switch

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
	@if [ -f .env ] && grep -q '^ROOTFS=' .env; then \
		echo "Current ROOTFS: $$(grep '^ROOTFS=' .env | cut -d= -f2)"; \
	else \
		echo "ROOTFS not set. Run 'make use-rootfs' or edit .env"; \
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
		echo "Run make fetch / make import-local-sdk, or set SDK_VOLUME in .env / CLI." >&2; \
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
		echo "Run make use-board, set BOARD in .env, or pass BOARD=... on the command line." >&2; \
		echo "" >&2; \
		echo "Available board profiles:" >&2; \
		ls -1 configs/boards/*.conf 2>/dev/null | sed 's|.*/||; s|\.conf$$||; s|^|  |' >&2; \
		echo "" >&2; \
		echo "Example: make use-board && make build-kernel" >&2; \
		echo "Or:      make build-kernel BOARD=rk3588s-rock-5c SDK_VOLUME=rk3588-sdk-rock5c" >&2; \
		exit 2; \
	}

require-rootfs:
	@test -n "$(strip $(ROOTFS))" || { \
		echo "ERROR: ROOTFS is required." >&2; \
		echo "Run 'make use-rootfs', set ROOTFS in .env, or pass ROOTFS=... on the command line." >&2; \
		echo "Available root filesystems:" >&2; \
		echo "  buildroot" >&2; \
		echo "  debian" >&2; \
		echo "  all" >&2; \
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

build-rootfs: require-rootfs validate-rootfs require-board require-sdk-volume
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
		-c 'printf "DEBIAN_ARCH=%s\n" "$$(dpkg --print-architecture)"') || { \
			echo "ERROR: Cannot run the linux/arm64 Debian builder." >&2; \
			exit 1; \
		}; \
	arch=$$(printf '%s\n' "$$probe_output" | \
		sed -n 's/^DEBIAN_ARCH=//p' | tail -1); \
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
		-e ROOTFS_HOSTNAME="$(ROOTFS_HOSTNAME)" \
		-e DEBIAN_PACKAGES="$(if $(strip $(DEBIAN_PACKAGES)),$(DEBIAN_PACKAGES),$(DEBIAN_FEATURES))" \
		-e DEBIAN_OVERLAYS="$(DEBIAN_OVERLAYS)" \
		-e DEBIAN_EXTRA_PACKAGES="$(DEBIAN_EXTRA_PACKAGES)" \
		-e WIFIBT_CHIP="$(WIFIBT_CHIP)" \
		-e WIFIBT_SOURCE="$(WIFIBT_SOURCE)" \
		-e WIFIBT_REQUIRED="$(WIFIBT_REQUIRED)" \
		-e DEBIAN_MIRROR="$(DEBIAN_MIRROR)" \
		-e DEBIAN_SECURITY_MIRROR="$(DEBIAN_SECURITY_MIRROR)" \
		-e DEBIAN_ALLOW_ARCHIVE_FALLBACK="$(DEBIAN_ALLOW_ARCHIVE_FALLBACK)" \
		debian-rootfs bash /home/builder/scripts/build_debian.sh

image: require-rootfs require-board validate-rootfs require-sdk-volume
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

verify-image: require-rootfs require-board validate-rootfs require-sdk-volume
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

build-all: require-rootfs require-board validate-rootfs require-sdk-volume
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

list-boards:
	@echo "Available board profiles:"
	@for conf in configs/boards/*.conf; do \
		board=$$(basename "$$conf" .conf); \
		[ "$$board" = "TEMPLATE" ] && continue; \
		desc=$$(grep -E '^BOARD_DESCRIPTION=' "$$conf" | head -1 | cut -d= -f2- | sed 's/^"//' | sed 's/"$$//' ); \
		if [ -n "$$desc" ]; then \
			printf '  %-40s %s\n' "$$board" "$$desc"; \
		else \
			printf '  %s\n' "$$board"; \
		fi; \
	done

new-board:
	@if [ -z "$(strip $(BOARD))" ]; then \
		echo "Usage: make new-board BOARD=<name>" >&2; \
		exit 1; \
	fi
	@if [ -f "configs/boards/$(BOARD).conf" ]; then \
		echo "ERROR: Board profile already exists: configs/boards/$(BOARD).conf" >&2; \
		exit 1; \
	fi
	@cp configs/boards/TEMPLATE.conf "configs/boards/$(BOARD).conf"
	@echo "Created board profile: configs/boards/$(BOARD).conf"
	@echo "Edit the file to set your board's parameters, then run:"
	@echo "  make validate-board BOARD=$(BOARD)"

validate-board: require-board
	SDK_VOLUME=$$(if [ -n "$(SDK_VOLUME)" ]; then echo "$(SDK_VOLUME)"; else echo "rk3588-sdk-validate"; fi) \
		docker compose run --rm --no-deps -T \
		-e BOARD="$(BOARD)" \
		rk3588-build bash -c 'source /home/builder/scripts/lib/common.sh && load_board_profile && echo "Board profile $(BOARD) is valid."'

info:
	@echo "=== Build Environment ==="
	@if [ -f .env ]; then \
		echo "Configuration from .env:"; \
		grep -E '^[A-Z]' .env 2>/dev/null | sed 's/^/  /' || echo "  (empty)"; \
	else \
		echo "  No .env file found"; \
	fi
	@echo ""
	@if [ -n "$(strip $(BOARD))" ] && [ -f "configs/boards/$(BOARD).conf" ]; then \
		echo "Board: $(BOARD)"; \
		desc=$$(grep -E '^BOARD_DESCRIPTION=' "configs/boards/$(BOARD).conf" | head -1 | cut -d= -f2- | sed 's/^"//' | sed 's/"$$//'); \
		if [ -n "$$desc" ]; then echo "  Description: $$desc"; fi; \
		manifest=$$(grep '^SOURCE_MANIFEST=' "configs/boards/$(BOARD).conf" | head -1 | cut -d= -f2- | tr -d '"'); \
		if [ -n "$$manifest" ]; then echo "  Manifest: $$manifest"; fi; \
	else \
		echo "Board: (not set)"; \
	fi
	@echo "SDK Volume: $(if $(SDK_VOLUME),$(SDK_VOLUME),(not set))"
	@echo "Root FS: $(if $(ROOTFS),$(ROOTFS),(not set))"
	@echo "Debian Release: $(DEBIAN_RELEASE)"

clean:
	SDK_VOLUME=$(if $(SDK_VOLUME),$(SDK_VOLUME),rk3588-sdk-clean) docker compose down --remove-orphans

clean-all:
	SDK_VOLUME=$(if $(SDK_VOLUME),$(SDK_VOLUME),rk3588-sdk-clean) docker compose down --remove-orphans --volumes --rmi local
