---
layout: home
title: 文档
description: 在 Docker 里用 Rockchip BSP 打出可烧录的 RK3588 GPT 系统镜像。

hero:
  name: rk3588-build
  text: RK3588 整盘镜像构建
  tagline: 用厂商 SDK + Docker 打出 loader / U-Boot / Kernel / rootfs 拼好的 GPT 镜像。不是发行版，也不是 BSP 本体。
  actions:
    - theme: brand
      text: 第一次构建
      link: /usage/quick-start
    - theme: alt
      text: 这是什么
      link: /intro/what-is
    - theme: alt
      text: 源码仓库
      link: https://github.com/lsy1291455142/rk3588-build

features:
  - title: 先跑通一条板
    details: 公开源走 ROCK 5C + Debian 13；本地 SDK 走 CokePi 或自备 BSP。
  - title: 三个开关
    details: SDK_VOLUME / BOARD / ROOTFS 都必须显式指定，写进 .env 或命令行。
  - title: 产物是整盘镜像
    details: output/<board>/ 下有 .img.zst，可直接 dd 到 SD 或 eMMC。
---

从这里开始：

1. [这是什么 / 不是什么](/intro/what-is)
2. [第一次构建（ROCK 5C）](/usage/quick-start)
3. [烧录与串口登录](/usage/flash-and-boot)
4. [构建为什么按这个顺序](/how-it-works/pipeline)
