# patches/

本地补丁目录。将需要应用到 SDK 源码的补丁文件放置在此目录中。

容器内挂载路径: `/home/builder/patches/` (只读)

## 目录结构建议

```
patches/
├── kernel/          # 内核补丁
│   ├── 0001-fix-xxx.patch
│   └── 0002-add-yyy.patch
├── u-boot/          # U-Boot 补丁
│   └── 0001-custom-board.patch
└── buildroot/       # Buildroot 补丁
```

## 用法

```bash
# 在容器内应用补丁
make shell
> cd /home/builder/sdk/kernel
> git am /home/builder/patches/kernel/*.patch
```
