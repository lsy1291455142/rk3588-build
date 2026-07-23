# 设计：纯构建核心 + 插件化 + 板子为单元

目标：构建核心（scripts/Makefile/Dockerfile）只做通用引擎，不认识任何具体板子/SoC；
一切差异化是插件；一个板子的全部关切聚合在一处，新增板子 = 丢一个目录。

## 实施状态（已完成）

- **Phase 1（check.sh 解耦）**：已落地。各板子携带 `boards/<board>/check.sh` 自检钩子；
  `scripts/check.sh` 遍历 `boards/*/check.sh` 调用 `board_check`，删除了
  `check_cokepi_board_contract` / `check_rock5c_source_contract` 等硬编码函数与 `run_check`
  里的板名分支。core 不再出现具体板名。
- **Phase 2（SoC 特性外移）**：已落地。`qemu_smoke.py` 的 initcall 黑名单与 `serial-getty`
  屏蔽改由 `configs/soc/<soc>.conf`（经 `board.conf` 的 `SOC=`）提供；`test_debian_qemu.sh`
  透传 `--initcall-blacklist` / `--serial-getty-mask`。
- **Phase 3（单目录聚合）**：已落地。一个板子的全部资产聚到 `boards/<board>/`
  （`board.conf` / `kernel.config` / `rootfs/` / `check.sh`）；`common.sh`、`build_kernel.sh`、
  `Makefile`（`new-board`/`list-boards`/`use-board`/`info` 等）、`TEMPLATE` 与本文档均已切换。
- **Phase 4（模式目录查表）**：已落地。`build_debian.sh` 用 `ROOTFS_MODE`→目录映射
  （`rootfs_mode_overlay_dir()`），去掉写死路径。

## 当前不合理点（原始问题，均已修复）

1. `scripts/check.sh` 写死板子契约：`check_cokepi_board_contract`(108)/`check_rock5c_source_contract`(79)
   及 `check_debian_features` 内大量硬编码板名路径(411-506)，主流程 `run_check "CokePi.."`(638)。
2. `scripts/lib/qemu_smoke.py` 写死 Rockchip SoC 假设：`QEMU_INITCALL_BLACKLIST`(34) 与
   `serial-getty@ttyFIQ0` 屏蔽(270) —— SoC 族耦合，非板子。
3. `scripts/build_debian.sh` 写死 `.../ro-overlay/overlay`(314) —— 模式耦合。
4. 板子资产散在 `configs/boards/`、`configs/kernel/`、`rootfs/debian/boards/` 三处。

## 目标结构

```
boards/<board>/
  board.conf        # 原 configs/boards/<board>.conf
  kernel.config     # 原 configs/kernel/<board>.config
  rootfs/           # 原 rootfs/debian/boards/<board>/
  check.sh          # 板子自检钩子（新增）
configs/soc/<soc>.conf   # SoC 特性：QEMU 黑名单/串口 getty 等
```

核心只认 `BOARD_DIR=boards/<board>`，按 `SOC=` 解析 `configs/soc/<soc>.conf`。

## 分阶段迁移

- **Phase 1（check.sh 解耦）**：各板子加 `check.sh` 自检钩子；`check.sh` 遍历板子目录调用，
  删掉 `check_cokepi_board_contract` / `check_rock5c_source_contract` 等硬编码函数，相关
  断言移入对应钩子。core 不出现具体板名。
- **Phase 2（SoC 特性外移）**：`qemu_smoke.py` 的黑名单/`ttyFIQ0` 改由
  `configs/soc/<soc>.conf`（经 board.conf 的 `SOC=`）提供；`test_debian_qemu.sh` 传递。
- **Phase 3（单目录聚合）**：把 conf/kernel frag/rootfs 聚到 `boards/<board>/`，更新所有引用
  （common.sh、build_kernel.sh、Makefile new-board、TEMPLATE、docs）。
- **Phase 4（模式目录查表）**：`build_debian.sh` 用 `ROOTFS_MODE`→目录映射，去掉写死路径。

每阶段后用 `make check` / 对 cokepi 跑 `build-rootfs`+`image`+`test-debian-qemu` 验证。
