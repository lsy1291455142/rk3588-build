import { defineConfig, type DefaultTheme } from 'vitepress'

const nav: DefaultTheme.NavItem[] = [
  { text: '首页', link: '/' },
  { text: '快速开始', link: '/guide/getting-started' },
  { text: '构建流程', link: '/build/pipeline' },
  { text: '板级配置', link: '/boards/profiles' },
  {
    text: 'GitHub',
    link: 'https://github.com/lsy1291455142/rk3588-build',
  },
]

const sidebar: DefaultTheme.Sidebar = [
  {
    text: '开始使用',
    items: [
      { text: '文档首页', link: '/' },
      { text: '快速开始', link: '/guide/getting-started' },
      { text: '环境与参数', link: '/guide/concepts' },
      { text: 'Builder 镜像', link: '/guide/builder' },
      { text: 'SDK 管理', link: '/guide/sdk' },
    ],
  },
  {
    text: '构建与产物',
    items: [
      { text: '流水线总览', link: '/build/pipeline' },
      { text: '阶段说明', link: '/build/stages' },
      { text: '产物与布局', link: '/build/artifacts' },
      { text: '烧录与登录', link: '/build/flash' },
      { text: '校验边界', link: '/build/verification' },
    ],
  },
  {
    text: '板型适配',
    items: [
      { text: '已支持板型', link: '/boards/profiles' },
      { text: '新板检查清单', link: '/boards/new-board' },
    ],
  },
  {
    text: '参考',
    items: [
      { text: '常用命令', link: '/reference/commands' },
      { text: 'CI 与依赖', link: '/reference/ci' },
      { text: 'FAQ', link: '/reference/faq' },
    ],
  },
]

export default defineConfig({
  title: 'RK3588 Build',
  description:
    '基于 Docker 的 RK3588 BSP 构建文档：loader、U-Boot、内核、rootfs 与 GPT 镜像打包。',
  lang: 'zh-CN',
  base: '/rk3588-build/',
  lastUpdated: true,
  cleanUrls: true,
  ignoreDeadLinks: true,
  sitemap: {
    hostname: 'https://lsy1291455142.github.io/rk3588-build/',
  },
  head: [['meta', { name: 'theme-color', content: '#2563eb' }]],
  themeConfig: {
    siteTitle: 'RK3588 Build',
    nav,
    sidebar,
    search: {
      provider: 'local',
      options: {
        translations: {
          button: {
            buttonText: '搜索',
            buttonAriaLabel: '搜索文档',
          },
          modal: {
            noResultsText: '没有找到相关结果',
            resetButtonTitle: '清除查询条件',
            displayDetails: '显示详细列表',
            footer: {
              selectText: '选择',
              navigateText: '切换',
              closeText: '关闭',
            },
          },
        },
      },
    },
    socialLinks: [
      {
        icon: 'github',
        link: 'https://github.com/lsy1291455142/rk3588-build',
      },
    ],
    editLink: {
      pattern:
        'https://github.com/lsy1291455142/rk3588-build/edit/main/docs/:path',
      text: '编辑此页',
    },
    lastUpdated: {
      text: '最后更新',
    },
    outline: {
      label: '本页目录',
      level: [2, 3],
    },
    docFooter: {
      prev: '上一页',
      next: '下一页',
    },
    sidebarMenuLabel: '菜单',
    returnToTopLabel: '返回顶部',
    darkModeSwitchLabel: '外观',
    lightModeSwitchTitle: '切换到浅色模式',
    darkModeSwitchTitle: '切换到深色模式',
    footer: {
      message: 'Docker-based RK3588 BSP build environment',
      copyright: 'Copyright © RK3588 Build contributors',
    },
  },
})
