import { defineConfig, type DefaultTheme } from 'vitepress'

const nav: DefaultTheme.NavItem[] = [
  { text: '简介', link: '/intro/what-is' },
  { text: '快速上手', link: '/usage/quick-start' },
  { text: '工作原理', link: '/how-it-works/architecture' },
  { text: '板型', link: '/boards/supported' },
  {
    text: '仓库',
    link: 'https://github.com/lsy1291455142/rk3588-build',
  },
]

const sidebar: DefaultTheme.Sidebar = [
  {
    text: '简介',
    items: [
      { text: '这是什么', link: '/intro/what-is' },
      { text: '环境要求', link: '/intro/requirements' },
    ],
  },
  {
    text: '使用',
    items: [
      { text: '第一次构建', link: '/usage/quick-start' },
      { text: '日常构建', link: '/usage/daily-build' },
      { text: '烧录与启动', link: '/usage/flash-and-boot' },
      { text: 'Debian 功能集', link: '/usage/debian-features' },
      { text: 'SDK 从哪来', link: '/usage/sdk' },
    ],
  },
  {
    text: '工作原理',
    items: [
      { text: '架构与目录', link: '/how-it-works/architecture' },
      { text: '构建流水线', link: '/how-it-works/pipeline' },
      { text: '磁盘与启动契约', link: '/how-it-works/boot-contract' },
    ],
  },
  {
    text: '板型',
    items: [
      { text: '已支持板型', link: '/boards/supported' },
      { text: '新增板型', link: '/boards/add-board' },
    ],
  },
  {
    text: '参考',
    items: [
      { text: 'Make 目标', link: '/reference/make-targets' },
      { text: '变量与 .env', link: '/reference/variables' },
      { text: '排错', link: '/reference/troubleshooting' },
    ],
  },
]

export default defineConfig({
  title: 'rk3588-build',
  description: '在 Docker 里用厂商 BSP 打出可烧录的 RK3588 GPT 系统镜像。',
  lang: 'zh-CN',
  base: '/rk3588-build/',
  lastUpdated: true,
  cleanUrls: true,
  ignoreDeadLinks: true,
  sitemap: {
    hostname: 'https://lsy1291455142.github.io/rk3588-build/',
  },
  head: [['meta', { name: 'theme-color', content: '#1f6feb' }]],
  themeConfig: {
    siteTitle: 'rk3588-build',
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
            noResultsText: '没有结果',
            resetButtonTitle: '清空',
            displayDetails: '显示详情',
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
      text: '在 GitHub 上编辑',
    },
    lastUpdated: { text: '更新于' },
    outline: { label: '本页', level: [2, 3] },
    docFooter: { prev: '上一页', next: '下一页' },
    sidebarMenuLabel: '目录',
    returnToTopLabel: '回到顶部',
    darkModeSwitchLabel: '主题',
    lightModeSwitchTitle: '浅色',
    darkModeSwitchTitle: '深色',
    footer: {
      message: '源码与 issues: github.com/lsy1291455142/rk3588-build',
    },
  },
})
