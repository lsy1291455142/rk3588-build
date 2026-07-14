# configs/

自定义编译配置目录。将 defconfig 文件放置在此目录中。

容器内挂载路径: `/home/builder/configs/` (只读)

## 用法

```bash
# 将自定义 defconfig 复制到此目录
cp my_rk3588_defconfig configs/

# 在容器内使用
make shell
> cd /home/builder/sdk/kernel
> cp /home/builder/configs/my_rk3588_defconfig arch/arm64/configs/
> make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- my_rk3588_defconfig
```
