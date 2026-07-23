---
layout: home

hero:
  name: rk3588-build
  text: RK3588 全系统镜像构建
  tagline: 在 Docker 里用厂商 BSP 打出可烧录的 GPT 系统镜像，一条命令完成从源码到烧录文件。
  actions:
    - theme: brand
      text: 快速上手
      link: /usage/quick-start
    - theme: alt
      text: 这是什么
      link: /intro/what-is

features:
  - title: 完全容器化
    details: 宿主机只需 Docker 和 Make。交叉工具链、QEMU、Rockchip 专有工具全部封装在镜像里。
  - title: 版本可复现
    details: 每个 SDK 用 repo manifest 锁定四个组件的 Git commit，板级 profile 可强制校验（如 ROCK 5C 锁定全部四个组件）。
  - title: 双 rootfs 支持
    details: Buildroot 最小化系统或 Debian 11/12/13 完整系统，同一套镜像组装和校验逻辑；另支持 ro-overlay 只读根。
  - title: QEMU 冒烟测试
    details: 无需真实硬件，在 QEMU virt 里验证串口登录、systemd 健康、SSH 密码登录与首启扩容。
---
