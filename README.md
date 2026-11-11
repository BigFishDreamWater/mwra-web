# HiCreator · One, two, no three.

一条 27 秒的产品短片落地页：**一次输入，两次点击，没有第三步** —— HiCreator 免费开始。

访问 <https://mwra.cn/> 即可观看；这一版是有声音的，点击页中央的 **Play with sound** 开始播放。

## 预览

纯静态页面，无需构建。本地起一个静态服务器即可（页面用根路径 `/assets`、`/promo`，不能用 `file://` 直接打开）：

```powershell
python -m http.server 8080
# 然后访问 http://127.0.0.1:8080/
```

调试参数：`?t=11.8&still=1` 可以定格到某一帧，用于截图。

## 页面内容

- 主标题：How many steps to promote a brand with influencers?
- 三个步骤：One thing → Two clicks → Three?
- 产品演示窗口：合同审批 → 视频审核，带点击光标、确认戳、彩带动效
- 底部字幕条逐词上浮，`NO` 高亮脉冲
- 结尾大字：HiCreator now free!
- 两张真实截图（REAL UI）证明区

## 声音

- 10 段英文配音（`promo/vo-*.mp3`）通过 Web Audio API 解码后按绝对时间调度
- 氛围垫音与点击 / 风切 / 冲击音效在浏览器里实时合成，不额外依赖音频文件
- 浏览器禁止自动播放，必须点一下才开始；右上角可静音，CC 可关字幕
- 声画时间轴写在构建产物里，改动配音时长需要重新构建，不能只换 mp3

## 技术

原生 HTML / CSS / JavaScript（由 Vite 构建为 `assets/` 下的 hash 资源），无框架、无后端、无外部字体。

```text
index.html                 页面结构与静态文案
assets/promo-*.js|css      构建产物（含时间轴、字幕、音频调度）
assets/*.woff2             本地打包的 Inter / JetBrains Mono
promo/                     10 段配音 + 头像 + 视频封面 + 2 张真实截图
platform/                  YouTube / Instagram 图标
favicon.svg                站点图标
```

> 资源全部使用根路径（`/assets/...`、`/promo/...`），因此必须部署在域名根目录，且这几条路径不能改名。

## 部署

推送 `main` 即触发 GitHub Actions 发布到 GitHub Pages（自定义域 `mwra.cn`），前面再套一层 Cloudflare 代理。

```text
push → Actions → GitHub Pages → Cloudflare CDN → https://mwra.cn
```

详细步骤、Cloudflare 配置与排查见 [DEPLOY.md](DEPLOY.md)。
