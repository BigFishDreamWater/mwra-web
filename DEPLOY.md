# 部署：GitHub → Actions → Pages → Cloudflare

## 架构

```
git push origin main
        │
        ├─ GitHub Actions  .github/workflows/deploy-pages.yml
        │     ├─ checkout
        │     ├─ 归档 _site/（剔除 .git / .github）
        │     └─ actions/deploy-pages → 发布到 GitHub Pages
        │
        └─ GitHub Pages（源站，自定义域 mwra.cn，Let's Encrypt 证书）
                │
                └─ Cloudflare（橙云代理：CDN / TLS 1.3 / HTTP/3 / WAF）
                        │
                        └─ 访客  https://mwra.cn
```

## 现状（已全部打通）

| 环节 | 状态 | 说明 |
| --- | --- | --- |
| Actions 工作流 | ✅ | `deploy-pages.yml`，push `main` 自动发布 |
| Pages 构建源 | ✅ | GitHub Actions（不是 branch 构建） |
| 自定义域 | ✅ | `mwra.cn`，证书已签发，强制 HTTPS 已开 |
| 站点 | ✅ | https://mwra.cn → 200，`server: cloudflare` |
| Cloudflare 代理 | ✅ | 4 条 A + www CNAME 全部橙云，SSL = Full (strict) |
| www | ✅ | 301 → `https://mwra.cn/`，边缘证书正常 |

实测返回头：

```
HTTP/1.1 200 OK
Server: cloudflare
CF-RAY: ...-AMS
cf-cache-status: DYNAMIC
alt-svc: h3=":443"; ma=86400
```

## Cloudflare 侧已生效的配置

| 项 | 值 | 为什么 |
| --- | --- | --- |
| SSL/TLS 模式 | **Full (strict)** | Flexible 会导致 GitHub 301 回 HTTPS → 无限重定向 |
| Always Use HTTPS | on | http 自动 301 到 https |
| Automatic HTTPS Rewrites | on | 混合内容自动升级 |
| Brotli | on | 压缩 |
| HTTP/3 | on | QUIC 加速 |
| Min TLS | 1.2 | 兼容性下限 |
| Rocket Loader | off | 本站 JS 全内联，它会把脚本执行顺序打乱 |
| 边缘缓存 | 默认 | HTML 不缓存（`cf-cache-status: DYNAMIC`），改完刷新即生效 |

改配置的脚本在 `scripts/setup-cloudflare.ps1`，可重复执行（幂等）：

```powershell
$env:CF_API_TOKEN = "你的 token"
powershell -ExecutionPolicy Bypass -File .\scripts\setup-cloudflare.ps1 -ApiToken $env:CF_API_TOKEN -DryRun
powershell -ExecutionPolicy Bypass -File .\scripts\setup-cloudflare.ps1 -ApiToken $env:CF_API_TOKEN
```

Token 需要：Zone→Read、DNS→Edit、Zone Settings→Edit、Cache Purge→Purge。
（`-ExecutionPolicy Bypass` 是因为 Windows 默认禁止运行未签名脚本。）

> 不建议把 token 写进仓库或工作流文件；要接自动清缓存，用 GitHub Secrets。

## 更新时效

GitHub Pages 给 HTML 发 `Cache-Control: max-age=600`，但 Cloudflare 默认不缓存 HTML，所以 **push 完成后刷新就能看到新版本**。

如果以后给静态资源（图片/字体）加了强缓存，或者开了 Cache Everything，再考虑二选一：
- 工作流里已内置可选的 purge 步骤：配 `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ZONE_ID` 两个 repo secret 就会自动清缓存；
- 或手动 Cloudflare → Caching → Purge Everything。

## GitHub 侧是怎么配的（备查）

- Pages 构建源：`PUT /repos/{owner}/{repo}/pages` → `{"build_type":"workflow"}`（仓库设置里也能点：Settings → Pages → Source: GitHub Actions）
- 自定义域：同一接口带 `"cname":"mwra.cn"`；注意 PATCH 会 404，必须用 PUT
- 首次部署必须重新触发一次（`workflow_dispatch`），否则自定义域会一直 404

## 日常发布

```powershell
git add -A
git commit -m "update"
git push
```

约 30–60 秒后 Actions 跑完，强刷即可。回滚：`git revert <commit>` 再 push。

## 排查清单

| 现象 | 原因 / 处理 |
| --- | --- |
| 526 Invalid SSL certificate | SSL 模式不是 Full (strict)，或 GitHub 侧证书没签好 |
| 重定向次数过多 | SSL 模式是 Flexible，改成 Full (strict) |
| 页面交互失效、样式错乱 | Rocket Loader 劫持内联脚本，关掉 |
| 改了代码线上不变 | 检查 Actions 是否成功；再 Purge Everything |
| 本地 DNS 还指向 185.199.108.153 | 本机缓存，`ipconfig /flushdns`（需管理员）或等 TTL 过期 |
| 页面里多了一个 `static.cloudflareinsights.com` 脚本 | Cloudflare Web Analytics 自动注入，控制台 Web Analytics 里可关 |
| 访问跳回 github.io | Pages 设置里的自定义域丢了，重新设 `mwra.cn` |

## 备选：Cloudflare Pages

不想要「GitHub Pages 源站 + Cloudflare 代理」这层套娃的话，可以直接用 Cloudflare Pages：
连同一个仓库 → 构建命令留空、输出目录 `/` → 自带全球 CDN、自动 HTTPS、预览部署。
DNS 上把 `mwra.cn` 的 A 换成指向 `<project>.pages.dev` 的 CNAME，GitHub Pages 停用即可。
代价是发布链绑死在 Cloudflare；现在这套的好处是 GitHub 是唯一事实源，Cloudflare 只是可随时摘掉的加速层。
