# 名为热爱 · A Study in Fire

一封写给所有不肯熄灭的人的单页情书。

页面以「名为热爱」为主题，用燃烧的余烬、巨大的排印和一段可以亲手点亮的仪式，讲述热爱的三种形状：点燃、抵达、回响。

## 预览

无需安装依赖，直接在浏览器中打开 `index.html` 即可。

```text
index.html
```

## 特点

- 单文件实现，CSS 与 JavaScript 全部内联，可离线打开
- 深色余烬视觉、发光轨道与 Canvas 火星粒子
- 滚动进度、分段入场动画与数字排印
- 「按住 · 点燃」交互仪式，支持鼠标、触摸与键盘
- 点燃瞬间迸出火焰粒子：火舌从圆里窜起、被热风拨动，最后留一簇长明的余烬
- 响应式布局，适配桌面与移动端
- 支持 `prefers-reduced-motion`，自动减少动效

## 技术

原生 HTML / CSS / JavaScript，无框架、无外部字体、无构建步骤。

## 部署

推送 `main` 即触发 GitHub Actions 发布到 GitHub Pages（自定义域 `mwra.cn`），前面再套一层 Cloudflare 代理。

```text
push → Actions → GitHub Pages → Cloudflare CDN → https://mwra.cn
```

详细步骤、Cloudflare 配置与排查见 [DEPLOY.md](DEPLOY.md)。

## 目录

```text
.
├── .github/workflows/deploy-pages.yml   # CI：发布到 GitHub Pages
├── scripts/setup-cloudflare.ps1         # 一键配置 Cloudflare 代理
├── DEPLOY.md                            # 部署说明
├── index.html
└── README.md
```
