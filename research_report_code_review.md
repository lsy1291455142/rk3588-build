# RK3588 Build 代码审查报告(冗余性 / 逻辑问题 / 代码优雅度)

审查范围:`scripts/`(含 `lib/`)、`Makefile`、`Dockerfile`、`docker-compose.yml`、`configs/`、`boards/`、根 `README` 与文档。审查基于实际源码逐行核对,所有发现均标注文件与行号,并按严重程度标注 [高]/[中]/[低]。

## 总览

整体工程质量较高:纯构建核心与板型数据解耦(`board-name-free`)、端到端契约测试(`check.sh`)、镜像几何与启动契约都有可执行校验、`set -Eeuo pipefail` + `require_cmd` 守卫贯穿全局。主要问题集中在三类:(1) 镜像/校验两阶段的几何公式与若干归一化逻辑被复制粘贴,有漂移风险;(2) 几处变量默认与格式校验不一致,在非 `make` 直跑脚本时会暴露;(3) 契约测试用源码字面量 `grep` 做断言,脆弱且与 `Dockerfile` 版本号硬耦合。

---

## 一、冗余性(Redundancy)

### R1 [中] 镜像几何公式在 `make_image.sh` 与 `verify_image.sh` 中重复实现
`make_image.sh:59-96` 计算 `IMAGE_SECTORS / BOOT_FIRST_SECTOR / ROOT_FIRST_SECTOR / ROOT_MIB / ROOT_SECTORS / ROOT_LAST_SECTOR / DATA_FIRST_SECTOR / DATA_LAST_SECTOR / DISK_LAST_USABLE_SECTOR`,其中 `ROOT_MIB=$(((ROOTFS_BYTES + 1048575) / 1048576 + 1))` 是核心公式。`verify_image.sh:111-134` 用注释 "Mirror the formulas used by make_image.sh" 原样复制了一遍。两处一旦有一边改了扇区/对齐假设,镜像能构建但校验会失败且极难定位。
优化:抽出 `scripts/lib/disk_geometry.sh`,提供 `compute_partition_layout()`,两脚本共同 `source` 后读取同一组变量。

### R2 [中] 逗号列表归一化在 `resolve_debian_packages` 与 `resolve_debian_overlays` 中逐字重复
`common.sh:322-330` 与 `common.sh:494-502` 的归一化块(`${raw//[[:space:]]/,}` → 替换 `+/`/`;` → 压缩 `,,` → 去首尾逗号 → `none|minbase|off|-` 置空)完全相同。
优化:抽 `normalize_comma_list()` 辅助函数,两处共用,避免两边行为分叉。

### R3 [低] `read_image_magic()` 被定义了两次
`verify_image.sh:219-221` 与 `build_uboot.sh:184-186` 各有 `dd if="$1" bs=1 count=4 status=none` 的相同实现。
优化:移入 `common.sh`。

### R4 [中] `build_debian.sh` 在调用 `resolve_*` 前手工预归一化,属重复且不一致
`build_debian.sh:16-26` 手动把 `DEBIAN_PACKAGES` 的 `none|minbase|off|-` 置空,`:33-43` 对 `DEBIAN_OVERLAYS` 也做了同样处理;但 `resolve_debian_packages`(`common.sh:331-335`)与 `resolve_debian_overlays`(`common.sh:503-507`)本来就做完全相同的归一化。而 `test_debian_qemu.sh` / `verify_image.sh` 只依赖 `resolve_*`、不做预归一化。结果:同一逻辑三处各写一份,且 `build_debian.sh` 的预归一化是冗余代码。
优化:删除 `build_debian.sh` 中的手工 `case` 预归一化,直接调用 `resolve_debian_packages` / `resolve_debian_overlays`(它们已处理 `none|minbase|off|-`)。

### R5 [低] 日志脚手架三处复制
`log_info/warn/error/step` 与颜色变量在 `common.sh:13-28`、`entrypoint.sh:18-21`、`fetch_sources.sh:10-20` 各实现一份(`common.sh` 用 `printf`,另两处用 `echo -e`)。`fetch_sources.sh` 与 `entrypoint.sh` 不 `source common.sh`,故复制有其理由,但风格不一致。
优化:抽出 `lib/log.sh` 由三者共用,统一 `printf` 风格。

### R6 [低] `verify_image.sh` 自实现 `overlay_enabled`,与 `common.sh` 重复
`verify_image.sh:333-339` 的 `overlay_enabled` 与 `common.sh:538-545` 的 `debian_overlay_enabled` 逻辑相同,只是数据源不同(前者读镜像元数据 `DEBIAN_OVERLAYS_META`,后者读运行时 `DEBIAN_OVERLAY_LIST`)。属"平行实现"而非纯重复,但可加注释说明为何不能共用,避免维护者误改其一。

### R7 [低] `ROOTFS_TAR` 产出后未被消费
`build_debian.sh:301-322` 生成 `${VARIANT_OUTPUT}/rootfs.tar`,但下游 `make_image.sh` 只用 `rootfs.ext4` / `rootfs.squashfs`,该 tar 包无人引用,是潜在死产物。

---

## 二、逻辑问题(Logic Issues / Risks)

### L1 [中] `CONSOLE` 缺少格式校验,可能静默生成错误串口配置
`validate_board_profile`(`common.sh:132-235`)把 `CONSOLE` 列为必填(`:179`)但不校验形状。各脚本用 `CONSOLE_SPEED="${CONSOLE#*,}"` 再 `%%[!0-9]*` 提取波特率(`build_debian.sh:66-67`、`verify_image.sh:382-383`)。若某板型写成 `CONSOLE=ttyFIQ0`(无逗号),`CONSOLE_SPEED` 会变成 `ttyFIQ0`,最终生成 `serial-getty` 的 `--keep-baud ttyFIQ0,115200` 这类错误配置而不报错(TEMPLATE 模板要求 `<device>,<baud><parity><bits>`,但代码层未强制)。
优化:在 `validate_board_profile` 中加 `[[ "${CONSOLE}" == *,*[0-9]* ]]` 之类校验,要求含逗号且逗号后有数字。

### L2 [中] `ROOTFS_USERNAME` 默认值在 Debian 路径不一致
`verify_image.sh:46` 与 `test_debian_qemu.sh:23-24` 用 `ROOTFS_USERNAME="${ROOTFS_USERNAME:-rk3588}"`。但 Debian 镜像实际用 `user`(`Makefile:38` `ROOTFS_USERNAME ?= user`、`build_debian.sh:62-63`)。经 `make` 调用时该变量会被传入,所以正常流程没问题;但若脱离 `make` 直跑脚本且未设 `ROOTFS_USERNAME`,Debian 路径会去 `/etc/passwd` 里找 `rk3588` 而误报 "lacks user"。
优化:Debian 相关脚本的回退改为 `:-user`,或根据 `ROOTFS` 推导默认用户名。

### L3 [中] Debian 构建缺少 binfmt 预检,且有用探针位置靠后
`build_debian.sh:52-54` 要求 root 且 `dpkg --print-architecture=arm64`,随后大量 `chroot`(`:190-217`)依赖 ARM64 binfmt/qemu 模拟;但 `debian-preflight`(`Makefile:607-622`)只检查架构,不检查 binfmt 是否已注册。在 x86_64 上若漏跑 `make register-arm64-binfmt`,`chroot useradd`(`:190`)会以难以理解的 exec format 错误直接失败。此外本该提前报警的 `chroot "${ROOT_DIR}" /bin/true`(`:216`)排在第一个 `chroot` 之后,起不到早期守护作用。
优化:`debian-preflight` 增加 binfmt/qemu 注册检测;把 `/bin/true` 探针移到任何写操作 `chroot` 之前。

### L4 [中,潜伏] `build_kernel.sh` 全局导出 `GIT_DIR`/`GIT_WORK_TREE`
`build_kernel.sh:119-120` 为让 Rockchip make.sh 的 `git` 探针指向内核树,导出 `GIT_DIR` 与 `GIT_WORK_TREE`。`GIT_DIR` 会覆盖后续所有 `git -C <repo>` 的自动发现。当前 `build_kernel` 在导出后只查询内核版本(`git_revision "${KERNEL_DIR}"`),故无实际 bug;但若将来在同一脚本内对 u-boot/rkbin/buildroot 调 `git_revision`,会错误返回内核版本。
优化:仅在调用 `make` 的子 shell 内临时 `export`,或显式传 `env GIT_DIR=... GIT_WORK_TREE=... make ...`,避免污染全局环境。

### L5 [低] `.scmversion` 缓存不随内核版本刷新
`build_kernel.sh:99-106` 仅 `if [ ! -e "${KERNEL_SCMVERSION_FILE}" ]` 时生成 `.scmversion`。若两次构建间切换了内核 SDK 版本,缓存文件不会更新,导致 LOCALVERSION/内核版本后缀失真。
优化:写入时同时记录内核 `git rev-parse`,下次构建比对,不一致则重建。

### L6 [低] `qemu_smoke.py` 的 `BOOT_ERROR_PATTERNS` 过宽,可能误报
`scan_serial_log`(`qemu_smoke.py:240-247`)把 `BOOT_ERROR_PATTERNS`(`\berror\b`、`\bfailed\b`)应用到整段串口日志(含 guest 自检命令输出),某些内核/服务正常日志含 "error"/"failed" 单词会触发假失败。
优化:把扫描范围限定到内核启动阶段(登录标记之前),或收窄关键词(如 `error:` 带冒号、具体子系统前缀)。

### L7 [低] `reserve_tcp_port` 释放后即存在端口复用竞态
`qemu_smoke.py:65-68` 绑定 `127.0.0.1:0` 取端口后立即关闭 socket,到 QEMU 用 `hostfwd` 绑定之间存在短暂窗口,端口可能被占用。
优化:持有该 socket 直到 QEMU 启动,或让 QEMU 自行选择端口再从日志解析。

### L8 [低] `check.sh` 的 `expect_failure` 自测依赖 `safe_reset_dir /tmp /tmp`
`check.sh:557-559` 中 `safe_reset_dir /tmp /tmp` 期望失败(目标等于父目录)。`safe_reset_dir` 确有 `target == parent` 守卫(`common.sh:424-425`),逻辑成立,但用 `/tmp` 这类全局路径做单测不够隔离,建议用 `mktemp -d` 构造父子目录。

---

## 三、代码优雅度(Elegance / Maintainability)

### E1 [中] 契约测试用源码字面量 `grep` 断言,极度脆弱
`check_kernel_contract`(`check.sh:92-142`)、`check_uboot_boot_contract_guard`(`check.sh:506-545`)、`check_qemu_smoke_contract`(`check.sh:226-260`)大量 `grep -Fq` 匹配脚本里的具体字符串(如 `'bash ./make.sh "${UBOOT_BOARD}" "CROSS_COMPILE=${CROSS_COMPILE}"'`、`'kernel_source_view=symlink-clean-v1'`)。任何无害重构(改名、改格式)都会让 CI 失败。项目刻意采用"可执行契约"哲学,此设计有其价值,但建议对热点项(如 U-Boot 契约)改用更稳定的行为断言(如 `declare -F validate_extlinux_boot_contract` 存在性、生成产物含特定标记),降低维护成本。

### E2 [中] 契约测试中硬写版本号,与 `Dockerfile` 漂移耦合
`check_manifests:87` 写死 `revision="refs/tags/2025.02.15"`;`check_uboot_boot_contract_guard:538-539` 写死 `ARG PYTHON2_VERSION=2.7.18` 与 `ARG PYELFTOOLS_PY2_VERSION=0.27`,与 `Dockerfile` 的 `ARG` 完全镜像。Buildroot 标签或 Python2 版本一升级,契约测试即红,却与功能无关。
优化:版本号从 `Dockerfile`/单一版本文件读取后再比对,或只校验"存在该 ARG"而非具体值。

### E3 [中] 凭据默认值双层设置,易混淆
`build_buildroot.sh:23-24` 自己默认 `rk3588/rk3588`,`build_debian.sh:62-63` 自己默认 `user/password`,随后都调用 `validate_rootfs_credentials`(`common.sh:273-287`),而该函数内部又默认 `user/password`。两层默认值中,`validate_rootfs_credentials` 的 `:-user` 对构建路径是死代码(调用前已被预设)。
优化:凭据默认集中到 `validate_rootfs_credentials` 一处,构建脚本只负责把板级/CLI 值透传,不再各自预设。

### E4 [低] 单文件偏大,可按职责拆分
`common.sh`(677 行)、`check.sh`(616)、`verify_image.sh`(425)、`build_debian.sh`(395)各自内聚但偏重。建议把 `common.sh` 拆为 `disk_geometry.sh`、`debian_helpers.sh`,`check.sh` 各 `check_*` 可按文件分散,提升可读性。

### E5 [低] `enable_unit` 回退实现偏长
`build_debian.sh:220-261` 的 `enable_unit` 是 40 行 systemctl 回退,逻辑正确但可读性与主流程割裂。建议抽成独立辅助文件并注明"仅在 systemctl 不可用时作为最后手段"。

### E6 [低] 模板展开重复 9 次替换
`expand_overlay_template_text`(`common.sh:548-565`)连续 9 行 `${content//@X@/...}`。可用 token→值 的关联数组循环处理,更紧凑且易扩展。

### E7 [低] 元数据写入混入复杂内联表达式
`build_debian.sh:388` 把 `network_stack=$(if ...; then ...; elif ...; fi)` 直接写在 `write_common_metadata` 的 `printf` 参数里,可读性差。建议先算入变量 `NETWORK_STACK` 再传入。

### E8 [低] 板型 `check.sh` 用 `#!/bin/sh` 却用 bash 数组
如 `boards/rk3588-cokepi-plus-lp4-v10/check.sh:1` 声明 `#!/bin/sh`,但函数内用 `local -a shared_markers=()`(bash 数组,`dash` 不支持)。该文件是被 `check.sh`(bash) `source` 的,所以能跑,但 shebang 有误导性。
优化:改为 `#!/usr/bin/env bash`。

### E9 [低] 错误信息中的命令替换每次加载都执行
`common.sh:106` 的 `require_file` 提示串里内嵌 `$(ls ...|sed...|grep -v...|tr...)`,该替换在每次 `load_board_profile` 调用时(即便成功)都会执行。
优化:仅在失败分支惰性计算可用板型列表。

---

## 优先修复建议(按性价比排序)

1. [中] R1 + R2:抽取 `disk_geometry.sh` 与 `normalize_comma_list`,消除镜像/校验几何公式与包列表归一化的复制——这是最可能引发"能构建却校验失败"的隐患。
2. [中] R4 + E3:删除 `build_debian.sh` 对 `DEBIAN_PACKAGES`/`DEBIAN_OVERLAYS` 的冗余预归一化;凭据默认集中到 `validate_rootfs_credentials`。
3. [中] L1 + L3:补 `CONSOLE` 格式校验;在 `debian-preflight` 增加 binfmt 检测,并把 `/bin/true` 探针前移——直接提升非标准环境的排错体验。
4. [中] E2:契约测试去硬版本号,从 `Dockerfile` 读取,避免版本升级误伤 CI。
5. [低] L4、L5、L6、L7、R3、R7 等按余力处理。

## 限制

- 未在真实 Docker 环境中端到端跑构建,结论基于静态阅读与跨脚本一致性推导;L3/L4/L5 等"潜伏"问题建议以一次 `make build-all` + `make test-debian-all` 实测佐证。
- `boards/` 下各 `check.sh` 仅抽样核对了 CokePi Plus,其余板型钩子未逐一通读。
- 性能类问题(如 E9 的每次加载 `ls`)在构建频率下影响可忽略,仅作整洁度建议。

## 参考文件(本次审查主要依据)

- `scripts/lib/common.sh`、`scripts/lib/bootloader_layouts.sh`
- `scripts/build_kernel.sh`、`scripts/build_uboot.sh`、`scripts/build_buildroot.sh`、`scripts/build_debian.sh`
- `scripts/make_image.sh`、`scripts/verify_image.sh`、`scripts/test_debian_qemu.sh`、`scripts/lib/qemu_smoke.py`
- `scripts/check.sh`、`scripts/fetch_sources.sh`、`scripts/import_local_sdk.sh`
- `Makefile`、`Dockerfile`、`docker-compose.yml`、`boards/TEMPLATE/board.conf`
