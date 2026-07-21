# patches/

可选的本地补丁目录。容器内以只读方式挂载到 `/home/builder/patches/`。

## 建议结构

```
patches/
├── kernel/
│   ├── 0001-fix-xxx.patch
│   └── 0002-add-yyy.patch
├── u-boot/
│   └── 0001-custom-board.patch
└── buildroot/
    └── 0001-tweak-config.patch
```

目录名对应 SDK 组件名，非强制但建议保持一致。

## 用法

构建脚本不会自动应用补丁。进入容器后按需手动应用：

```bash
make shell SDK_VOLUME=<volume>

# 应用内核补丁
cd /home/builder/sdk/kernel
git am /home/builder/patches/kernel/0001-fix-xxx.patch

# 应用 U-Boot 补丁
cd /home/builder/sdk/u-boot
git am /home/builder/patches/u-boot/0001-custom-board.patch
```

应用后正常执行 `make build-kernel` / `make build-uboot`，补丁会被编译进产物。

## 注意

- 补丁直接修改 SDK volume 里的源码，容器退出后仍然保留
- 要撤销补丁：`cd /home/builder/sdk/kernel && git reset --hard HEAD~N`（N = 补丁数）
- 长期维护的板级差异优先写入 `configs/boards/` 的 profile 字段和可复现的 SDK commit 锁定
- 补丁目录适合临时试验、调试修复或尚未上游化的修改
