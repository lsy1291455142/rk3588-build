---
layout: home
title: RK3588 Docker 构建环境
description: 基于 Docker 的 RK3588 BSP 构建文档：loader、U-Boot、内核、rootfs 与可烧录 GPT 镜像。

hero:
  name: RK3588 Build
  text: Docker 中完成整盘系统镜像
  tagline: 管理构建流程与板级配置，在容器中编译 loader / U-Boot / Kernel / rootfs，并打包为可直接写入 SD / eMMC 的 GPT raw 镜像。
  actions:
    - theme: brand
      text: 快速开始
      link: /guide/getting-started
    - theme: alt
      text: 构建流程
      link: /build/pipeline
    - theme: alt
      text: 查看仓库
      link: https://github.com/lsy1291455142/rk3588-build

features:
  - title: 可复现的 builder
    details: Ubuntu 22.04 工具链镜像 + Docker volume 接入 SDK，宿主机无需预装交叉编译器。
  - title: 板级 profile 驱动
    details: 通过 configs/boards/*.conf 固定 DTB、U-Boot、串口与镜像几何，新增板型只需复制改字段。
  - title: 整盘 GPT 产物
    details: 输出 Image、loader、rootfs 与 .img.zst，附带离线校验与可选 QEMU 冒烟测试。
---

## 按任务阅读

<div class="rk-doc-grid">
  <section class="rk-doc-card">
    <h3>开始使用</h3>
    <p>准备 Docker，选定板型与 rootfs，跑通第一条构建路径。</p>
    <ul>
      <li><a href="./guide/getting-started.html">快速开始</a></li>
      <li><a href="./guide/concepts.html">环境与三个核心参数</a></li>
      <li><a href="./guide/builder.html">Builder 镜像</a></li>
      <li><a href="./guide/sdk.html">SDK 拉取与本地导入</a></li>
    </ul>
  </section>
  <section class="rk-doc-card">
    <h3>构建与打包</h3>
    <p>理解各阶段职责，查看产物目录、分区布局与烧录方式。</p>
    <ul>
      <li><a href="./build/pipeline.html">流水线总览</a></li>
      <li><a href="./build/stages.html">阶段说明</a></li>
      <li><a href="./build/artifacts.html">产物与布局</a></li>
      <li><a href="./build/flash.html">烧录与默认登录</a></li>
    </ul>
  </section>
  <section class="rk-doc-card">
    <h3>板型适配</h3>
    <p>已支持板型字段说明，以及新硬件检查清单。</p>
    <ul>
      <li><a href="./boards/profiles.html">已支持板型</a></li>
      <li><a href="./boards/new-board.html">新板检查清单</a></li>
    </ul>
  </section>
  <section class="rk-doc-card">
    <h3>参考</h3>
    <p>命令速查、CI 行为，以及校验能力边界。</p>
    <ul>
      <li><a href="./reference/commands.html">常用命令</a></li>
      <li><a href="./reference/ci.html">CI 与依赖更新</a></li>
      <li><a href="./build/verification.html">校验边界</a></li>
      <li><a href="./reference/faq.html">FAQ</a></li>
    </ul>
  </section>
</div>

## 能得到什么 / 不包含什么

| 会产出 | 不包含 |
|---|---|
| Kernel `Image`、指定 DTB、`modules.tar` | 桌面环境 |
| Rockchip loader（`idblock.img` / `download-loader.bin`）、`uboot.img` | Mali / MPP / RKNPU 用户态 |
| Buildroot 或 Debian rootfs | Rockchip `update.img` |
| FAT32 boot + extlinux、ext4 rootfs | SPI NAND 布局 |
| 4 GiB GPT raw image、`.img.zst`、SHA256、离线校验 | 真实硬件 bring-up 保证 |

本仓库管理的是**构建流程与板级配置**，不是厂商 BSP 本体。SDK 通过独立 Docker volume 接入；CokePi 等无法公开拉取的 SDK 使用本地导入。

离线校验只证明镜像结构与内容一致；串口启动与板级功能仍需在硬件上确认。
