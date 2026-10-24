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

## 现状

| 环节 | 状态 |
| --- | --- |
| Actions 工作流 | ✅ 已提交（`deploy-pages.yml`） |
| Pages 构建源 | ✅ GitHub Actions（不是 branch 构建） |
| 自定义域 | ✅ `mwra.cn`，证书已签发，强制 HTTPS 已开 |
| 站点可访问 | ✅ https://mwra.cn 返回 200 |
| Cloudflare 代理 | ⬜ **还差这一步**（4 条 A + www CNAME 目前是 DNS only） |

> 现在若直接开橙云而不先改 SSL 模式，大概率白屏 + 526 / 重定向循环。按下面顺序来。

---

## 第 1 步：开 Cloudflare 代理

### 方式 A · 脚本（推荐，一次配完）

1. Cloudflare → My Profile → API Tokens → **Create Token** → Custom token
2. 权限按这个给（Zone Resources 选 `mwra.cn`）：

   | 类型 | 权限 |
   | --- | --- |
   | Zone | Zone → Read |
   | Zone | DNS → Edit |
   | Zone | Zone Settings → Edit |
   | Zone | Cache Purge → Purge |

3. 运行：

```powershell
$env:CF_API_TOKEN = "粘贴 token"
.\scripts\setup-cloudflare.ps1 -ApiToken $env:CF_API_TOKEN -DryRun   # 先看要改什么
.\scripts\setup-cloudflare.ps1 -ApiToken $env:CF_API_TOKEN           # 真正执行
```

脚本会做四件事：SSL 改 **Full (strict)** → 打开 HTTPS/Brotli/HTTP3、关掉 Rocket Loader → 把 apex 与 www 记录改成 Proxied → 清空缓存。

> API Token 建议只存在当前终端的环境变量里，用完 `Remove-Item Env:\CF_API_TOKEN`。

### 方式 B · 控制台手点（3 处）

1. **SSL/TLS → Overview** → 模式选 **Full (strict)**
2. **DNS → Records** → 勾选 4 条 `A` + 那条 `www` CNAME → **Edit** → Proxy status 改 **Proxied**（橙云）
3. **SSL/TLS → Edge Certificates** → 打开 Always Use HTTPS、Automatic HTTPS Rewrites、Brotli、HTTP/3
4. **Caching → Configuration → Purge Everything**

改完验证：

```powershell
curl.exe -I https://mwra.cn
# 期望：HTTP/2 200，server: cloudflare，带 cf-ray 头
```

`server` 还是 `GitHub.com` 说明橙云没生效或还在传播，等 1–2 分钟再看。

---

## 第 2 步（可选）：部署后自动清缓存

单文件站点最容易踩的坑是「改完 push 了，刷新还是旧页面」——HTML 被 Cloudflare 边缘缓存了。

把 cache purge 接进流水线（工作流里已经写好这一步，缺 secret 会自动跳过）：

1. Cloudflare → My Profile → API Tokens → 建一个只有 **Cache Purge → Purge** 的 token
2. GitHub 仓库 → Settings → Secrets and variables → Actions → New repository secret
   - `CLOUDFLARE_API_TOKEN` = 上面那个 token
   - `CLOUDFLARE_ZONE_ID` = 在 Cloudflare 域名概览页右下角能看到的 Zone ID
3. 之后再 push，部署完成会自动 `purge_everything`

不想给 token 也行，换规则方案：**Caching → Cache Rules** → 新建一条
`http.request.uri.path eq "/"` → **Bypass cache**。代价是首页每次都回源。

---

## 为什么必须是 Full (strict)

| 模式 | 结果 |
| --- | --- |
| Flexible | Cloudflare 用 HTTP 回源，GitHub Pages 强制 301 到 HTTPS → **无限重定向** |
| Full | 能用，但不校验源站证书 |
| **Full (strict)** | ✅ GitHub Pages 本来就有合法的 Let's Encrypt 证书，严格校验也能过 |

证书顺序很重要：**先让 GitHub 把证书签发好，再开橙云**。反过来会出现 526（Cloudflare 连不上合法源站证书）。本站证书已签发（`mwra.cn`，2027-01 到期），这一点已经满足。

---

## 日常发布

```powershell
git add -A
git commit -m "update"
git push
```

push 后去 **Actions** 页看 `Deploy to GitHub Pages` 跑完（约 30–60 秒），然后强刷页面。
回滚：`git revert <commit>` 再 push，或 Actions 里对旧的运行点 **Re-run**。

---

## 排查清单

| 现象 | 原因 / 处理 |
| --- | --- |
| 526 Invalid SSL certificate | SSL 模式不是 Full (strict)，或 GitHub 证书还没签发 |
| 重定向次数过多 | SSL 模式是 Flexible，改成 Full (strict) |
| 页面结构错乱、交互失效 | Rocket Loader 会劫持内联 `<script>`，关掉它（本站 JS 全部内联） |
| 改了代码线上不变 | CDN 缓存，用上面第 2 步的 purge，或临时 Development Mode |
| 访问回到 github.io 地址 | Pages 设置里的自定义域没保存成功，检查 Settings → Pages |
| www 打不开 / 证书报错 | Cloudflare 边缘证书已覆盖 `*.mwra.cn`；若源站证书不含 www，可加一条 Redirect Rule 把 www 301 到 apex |

---

## 另一条更省事的路：Cloudflare Pages

如果以后不想要「GitHub Pages 源站 + Cloudflare 代理」这层套娃，可以直接用 **Cloudflare Pages**：
连接同一个仓库 → 构建命令留空、输出目录填 `/` → 它自带全球 CDN、自动 HTTPS、预览部署、每次 push 自动清缓存。
DNS 上把 `mwra.cn` 的 A 记录换成一个 CNAME 指向 `<project>.pages.dev` 即可，GitHub Pages 可以停用。
代价是把发布链绑定在 Cloudflare 上；现在这套方案的好处是「GitHub 是唯一事实源，Cloudflare 只是加速层，随时能摘掉」。
