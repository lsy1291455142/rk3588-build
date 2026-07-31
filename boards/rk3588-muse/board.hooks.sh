#!/usr/bin/env bash
# =============================================================================
# MUSE RK3588 board hooks
# =============================================================================
# Sourced by scripts/lib/common.sh after board profile is loaded.
# Hook functions run in the same shell as the build script, so all build
# variables (KERNEL_DIR, BOARD_DIR, etc.) are available.
#
# Available hooks:
#   pre_build_kernel, post_build_kernel
#   pre_build_uboot, post_build_uboot
#   pre_build_rootfs, post_build_rootfs
#   pre_make_image, post_make_image
#   pre_fetch_sources, post_fetch_sources
#
# AIC8800 USB WiFi/BT driver (FCU761K-L / AIC8800DC) is integrated directly
# into the MUSE kernel fork (MUSEInstitute/kernel, develop-5.10 branch).
# No pre_build_kernel hook is needed — the driver source, Makefile, and
# Kconfig wiring are committed to the kernel repo and pulled in by make fetch.
# =============================================================================
