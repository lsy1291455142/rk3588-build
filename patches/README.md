# patches/

可选的本地补丁目录。将需要应用到 SDK 源码的补丁放在此目录；容器内以只读方式挂载到 `/home/builder/patches/`。

## 建议结构

```text
patches/
├── kernel/
│   ├── 0001-fix-xxx.patch
│   └── 0002-add-yyy.patch
├── u-boot/
│   └── 0001-custom-board.patch
└── buildroot/
```

## 用法

构建脚本不会自动应用补丁。进入容器后按需手动应用：

```bash
make shell
cd /home/builder/sdk/kernel
git am /home/builder/patches/kernel/*.patch
```

长期维护的板级差异优先写入 `configs/boards/` 与可复现的 SDK 提交锁定；补丁目录适合临时试验或尚未上游化的修改。
