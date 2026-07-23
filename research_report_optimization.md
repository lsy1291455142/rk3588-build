# RK3588 Build 代码审查优化实施报告

本报告的优化对象为 `research_report_code_review.md`(下简称"审查报告")。工作区在交接前已由一次前期会话落地了审查报告中大部分条目(R1、R2、R3 的 build_uboot 副本、R4、R5、R6、E6、L1、E9,以及新建的 `scripts/lib/disk_geometry.sh` 与 `scripts/lib/log.sh`)。本会话在其基础上补全了**所有剩余的、可安全落地的条目**,并对少数需权衡的条目做出明确决策。所有改动均通过 `bash -n` / `python3 -m py_compile` 语法校验,并在容器 Bash(5.1)下验证了 `set -u` 下的空数组展开行为。

## 已实施的改动(对照审查报告条目)

下表汇总本次新增实施(含前期会话已完成、本次复核确认的条目)。"报告条目"列对应审查报告中的编号。

| 报告条目 | 文件 | 改动 | 修改原因 |
| --- | --- | --- | --- |
| R3 [低] | `scripts/verify_image.sh` | 删除与 `common.sh` 重复的 `read_image_magic()` 本地定义,统一调用 `common.sh` 中的单一定义 | 消除"同一函数两份实现",避免后续只有一边更新导致校验与构建语义漂移 |
| E5 [低] | `scripts/lib/enable_unit.sh`(新)、`scripts/lib/common.sh`、`scripts/build_debian.sh` | 将 40 行 `enable_unit` 回退抽成独立辅助文件,由 `common.sh` 统一 `source`;从 `build_debian.sh` 删除内联实现,并注明"仅 systemctl 不可用时作最后手段" | 主流程与回退逻辑解耦,提升可读性;插件(overlay `plugin.sh`)仍通过 `common.sh` 拿到该函数,行为不变 |
| E3 [中] | `scripts/build_debian.sh`、`scripts/build_buildroot.sh` | 删除两处对 `ROOTFS_USERNAME`/`ROOTFS_PASSWORD` 的 `:-` 预设,凭据默认完全交给 `validate_rootfs_credentials()`,并同步更新 `docs/how-it-works/pipeline.md` | 凭据默认值集中到一处,消除三层默认值的死代码与不一致风险(`validate_rootfs_credentials` 的 `:-user` 此前对构建路径是死代码) |
| L2 [中] | `scripts/test_debian_qemu.sh` | Debian QEMU 冒烟测试的回退默认值由 `rk3588` 改为 `user`,与 Debian 镜像实际账号一致 | 脱离 `make` 直跑该脚本且未设 `ROOTFS_USERNAME` 时,不再去镜像里找不存在的 `rk3588` 而误报 |
| L3 [中] | `scripts/build_debian.sh`、`Makefile` | 把 `chroot ... /bin/true` 可执行性探针从"写操作之后"前移到第一个写 `chroot`(useradd)之前;`debian-preflight` 增加 ARM64 binfmt/qemu 注册检测,未注册时给出明确提示与 `make register-arm64-binfmt` 指引 | 在 x86_64 上若漏跑 `register-arm64-binfmt`,`chroot` 失败从"难懂的 exec format"提前为清晰报错;preflight 直接守卫 binfmt |
| L4 [中,潜伏] | `scripts/build_kernel.sh` | 不再全局 `export GIT_DIR`/`GIT_WORK_TREE`,改为组装 `KERNEL_GIT_ENV` 数组并仅前缀到各 `make` 调用 | 避免污染全局环境,使将来在同一脚本内对 u-boot/rkbin/buildroot 调 `git_revision` 时错误返回内核版本 |
| L5 [低] | `scripts/build_kernel.sh` | `.scmversion` 生成时一并记录内核 `git rev-parse` 到 `.scmrevision`;再次构建时比对,不一致则重建 | 切换 SDK 内核版本后缓存不刷新导致 LOCALVERSION/内核后缀失真的隐患 |
| L6 [低] | `scripts/lib/qemu_smoke.py` | `scan_serial_log` 把宽泛的 `BOOT_ERROR_PATTERNS`(`\berror\b`、`\bfailed\b`)的扫描范围限制到登录标记之前的"内核启动阶段",`FATAL_PATTERNS` 仍扫描整段日志 | 避免 guest 自检命令输出中的 "error"/"failed" 单词触发假失败 |
| L7 [低] | `scripts/lib/qemu_smoke.py` | `reserve_tcp_port()` 返回端口与已绑定 socket;QEMU 启动(spawn)后立刻 `close()` 释放保留,并在保留 socket 上设置 `SO_REUSEADDR` | 持有 socket 直到 QEMU 接管端口,消除"释放端口到 QEMU 绑定之间"的端口复用竞态 |
| L8 [低] | `scripts/check.sh` | 单测 `safe_reset_dir /tmp /tmp` 改为 `mktemp -d` 构造的父子隔离目录触发 `target == parent` 守卫 | 不再用全局 `/tmp` 做单测,测试隔离更干净 |
| E2 [中] | `scripts/check.sh` | `check_manifests` 不再硬编码 `revision="refs/tags/2025.02.15"`,改为断言每个非板型拥有的 manifest 都 pin 同一个 `refs/tags/*` 的 Buildroot 修订;`check_uboot_boot_contract_guard` 不再硬编码 `PYTHON2_VERSION=2.7.18`/`PYELFTOOLS_PY2_VERSION=0.27`,改为断言 `ARG PYTHON2_VERSION=`/`ARG PYELFTOOLS_PY2_VERSION=` 存在 | 版本号从 Dockerfile/manifest 升级时,契约测试不再无辜变红,同时仍守住"必须定义 ARG / 必须 pin 同一 Buildroot tag"的实质约束 |
| E7 [低] | `scripts/build_debian.sh` | `write_common_metadata` 中内联的 `network_stack=$(if ...; fi)` 表达式提前算入 `NETWORK_STACK` 变量再传入 | 元数据写入调用可读性提升,表达式与调用解耦 |
| E8 [低] | `boards/rk3588-cokepi-plus-lp4-v10/check.sh` | shebang `#!/bin/sh` 改为 `#!/usr/bin/env bash` | 该文件使用 `local -a shared_markers=()`(bash 数组),`dash` 不支持,shebang 此前有误导性(虽被 bash 的 check.sh `source`,但声明应一致) |

## 前期会话已完成、本次复核确认保持的条目

R1(`disk_geometry.sh` + `make_image.sh`/`verify_image.sh` 共用 `compute_partition_layout`)、R2(`normalize_comma_list` 抽出并被两处 resolver 共用)、R3 的 build_uboot 副本删除、R4(`build_debian.sh` 删除对 `DEBIAN_PACKAGES`/`DEBIAN_OVERLAYS` 的冗余预归一化)、R5(`log.sh` 由 `common.sh`/`entrypoint.sh`/`fetch_sources.sh` 共用)、R6(`verify_image.sh` 的 `overlay_enabled` 加注释说明为何不能与 `common.sh` 共用)、E6(`expand_overlay_template_text` 改为关联数组循环)、E9(`require_file` 的可用板型列表在失败分支惰性计算)、L1(`validate_board_profile` 增加 `CONSOLE` 格式校验)。这些条目在当前代码中已正确落地,本次未做破坏性改动。

## 经权衡后刻意保留/部分实施的条目

E1 [中](契约测试用源码字面量 `grep` 断言):审查报告本身明确指出项目"刻意采用可执行契约哲学,此设计有其价值",并仅将其作为权衡性建议。因此**保留契约测试的实质行为断言**(这些 grep 真实编码了构建契约),仅把其中可安全去耦合的子集(版本号硬编码)通过 E2 解决。若强行改写为宽松断言会削弱"可执行契约"这一核心验证机制,与"不破坏原有架构与核心逻辑"的要求冲突,故该项刻意不改动,仅以 E2 覆盖其可落地部分。

E4 [低](按职责拆分 `common.sh`):已落实最具价值的拆分——`disk_geometry.sh` 与 `log.sh` 已抽出。将 Debian 相关辅助函数再拆为 `debian_helpers.sh` 属于纯美化、且涉及更多 `source` 编排与回归风险,性价比低,本次保留 `common.sh` 现状(本已内聚),不强行拆分。

R7 [低](Debian `rootfs.tar` 产出未被 `make_image.sh` 消费):该 tar 包在 `docs/how-it-works/pipeline.md`、`architecture.md`、`quick-start.md` 中均被列为 Debian 路径的中间产物,Buildroot 路径也同样产出 `rootfs.tar`。删除生成会破坏文档一致性且无明确收益,故**保留生成**,将其视为文档化的中间产物而非死代码。

## 验证

- 所有受影响的 bash 脚本通过 `bash -n` 语法检查;`qemu_smoke.py` 通过 `python3 -m py_compile`。
- `build_kernel.sh` 的 `"${KERNEL_GIT_ENV[@]}" make ...` 在 `set -u` 下空数组展开已验证为安全(容器 Bash 5.1)。
- `enable_unit` 现仅定义一次(位于 `lib/enable_unit.sh`),`check.sh` 中的三处 `enable_unit() { :; }` 为有意的单测桩覆盖,不影响真实构建路径。
- `Makefile` 的 `debian-preflight` 新增 binfmt 守卫,`--entrypoint /bin/true debian-rootfs` 在 binfmt 未注册时会以非零退出并给出明确修复指引。

## 限制

- 改动基于静态阅读与跨脚本一致性推导,未在真实 Docker 环境中端到端跑 `make build-all` + `make test-debian-all`(环境受限)。建议以一次完整构建实测佐证 L3/L4/L5 等运行期行为。
- 各 `boards/<board>/check.sh` 仅抽样核对了 CokePi Plus(E8 已修其 shebang);其余板型钩子未逐一通读。
- E1 出于保护"可执行契约"核心机制的考虑刻意未改,已在上方说明。
