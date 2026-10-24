<#
.SYNOPSIS
    把 mwra.cn 的 Cloudflare 配置调整为「全站代理 + 严格 SSL + 清缓存」。

.DESCRIPTION
    适配 GitHub Pages 源站：
      1. SSL/TLS 模式设为 Full (strict)  —— 必须，Flexible 会导致 301 死循环
      2. 打开 Always Use HTTPS / 自动 HTTPS 重写 / Brotli / HTTP/3，关掉 Rocket Loader
      3. 把 mwra.cn 的 A 记录与 www 的 CNAME 全部改成 Proxied（橙云）
      4. 清空整个 zone 的缓存

.PARAMETER ApiToken
    Cloudflare API Token，权限需要：
      Zone -> Zone -> Read
      Zone -> DNS  -> Edit
      Zone -> Zone Settings -> Edit
      Zone -> Cache Purge -> Purge

.PARAMETER ZoneName
    根域名，默认 mwra.cn。

.PARAMETER DryRun
    只打印将要执行的操作，不真正修改。

.EXAMPLE
    $env:CF_API_TOKEN = "xxxx"
    .\scripts\setup-cloudflare.ps1 -ApiToken $env:CF_API_TOKEN -DryRun
    .\scripts\setup-cloudflare.ps1 -ApiToken $env:CF_API_TOKEN
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ApiToken,
    [string]$ZoneName = 'mwra.cn',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
if ($ApiToken.Trim() -notmatch '^[A-Za-z0-9_\-]{20,100}$') {
    throw "ApiToken 格式不对：应是 40 位左右的字母/数字/-/_（API Token），不是 Global API Key。"
}

$base = 'https://api.cloudflare.com/client/v4'
$headers = @{
    Authorization  = "Bearer $ApiToken"
    'Content-Type' = 'application/json'
}

function Invoke-Cf {
    param(
        [string]$Method,
        [string]$Path,
        $Body
    )
    $params = @{
        Uri             = "$base$Path"
        Method          = $Method
        Headers         = $headers
        UseBasicParsing = $true
        TimeoutSec      = 30
    }
    if ($null -ne $Body) { $params.Body = ($Body | ConvertTo-Json -Depth 8 -Compress) }
    try {
        $resp = Invoke-RestMethod @params
    }
    catch {
        $ex = $_.Exception.Response
        if ($ex) {
            $sr = New-Object System.IO.StreamReader($ex.GetResponseStream())
            throw "Cloudflare API $Method $Path -> HTTP $([int]$ex.StatusCode): $($sr.ReadToEnd())"
        }
        throw "Cloudflare API $Method $Path -> $($_.Exception.Message)"
    }
    if (-not $resp.success) {
        throw "Cloudflare API 失败: $($resp.errors | ConvertTo-Json -Compress)"
    }
    return $resp.result
}

Write-Host "== 1. 查找 zone: $ZoneName" -ForegroundColor Cyan
$zones = Invoke-Cf -Method GET -Path "/zones?name=$ZoneName"
if (-not $zones -or $zones.Count -eq 0) {
    throw "找不到 zone '$ZoneName'。请确认 token 有 Zone:Read 权限，且域名确实在该账号下。"
}
$zoneId = $zones[0].id
Write-Host "   zone id = $zoneId  (status: $($zones[0].status))"

Write-Host "`n== 2. 安全 / 性能开关" -ForegroundColor Cyan
$settings = [ordered]@{
    ssl                      = 'strict'   # Full (strict)
    always_use_https         = 'on'
    automatic_https_rewrites = 'on'
    brotli                   = 'on'
    http3                    = 'on'
    rocket_loader            = 'off'      # 本站 JS 全内联，Rocket Loader 会打乱执行顺序
    min_tls_version          = '1.2'
}
foreach ($key in $settings.Keys) {
    $value = $settings[$key]
    if ($DryRun) {
        Write-Host "   [dry-run] $key = $value"
        continue
    }
    $r = Invoke-Cf -Method PATCH -Path "/zones/$zoneId/settings/$key" -Body @{ value = $value }
    Write-Host "   $key = $($r.value)"
}

Write-Host "`n== 3. 打开橙云代理" -ForegroundColor Cyan
$records = Invoke-Cf -Method GET -Path "/zones/$zoneId/dns_records?per_page=100"
$targets = @($records | Where-Object {
        ($_.name -eq $ZoneName -or $_.name -eq "www.$ZoneName") -and
        ($_.type -in @('A', 'AAAA', 'CNAME'))
    })

if ($targets.Count -eq 0) {
    Write-Warning "没有找到 $ZoneName / www.$ZoneName 的 A/CNAME 记录，请先确认 DNS 面板。"
}
foreach ($rec in $targets) {
    $label = "$($rec.name)  $($rec.type)  $($rec.content)".PadRight(58)
    if ($rec.proxied) {
        Write-Host "   $label 已代理"
        continue
    }
    if ($DryRun) {
        Write-Host "   [dry-run] $label -> proxied"
        continue
    }
    try {
        $null = Invoke-Cf -Method PATCH -Path "/zones/$zoneId/dns_records/$($rec.id)" -Body @{ proxied = $true }
        Write-Host "   $label -> proxied" -ForegroundColor Green
    }
    catch {
        Write-Warning "   $label 代理失败: $($_.Exception.Message)"
    }
}

Write-Host "`n== 4. 清空缓存" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "   [dry-run] purge_everything"
}
else {
    $null = Invoke-Cf -Method POST -Path "/zones/$zoneId/purge_cache" -Body @{ purge_everything = $true }
    Write-Host "   缓存已清空" -ForegroundColor Green
}

Write-Host "`n== 5. 自检" -ForegroundColor Cyan
Start-Sleep -Seconds 5
try {
    $r = Invoke-WebRequest -Uri "https://$ZoneName/" -UseBasicParsing -TimeoutSec 25 -MaximumRedirection 5
    Write-Host ("   https://{0}/ -> {1}  server={2}  cf-ray={3}" -f $ZoneName, $r.StatusCode, $r.Headers['Server'], $r.Headers['CF-RAY'])
}
catch {
    Write-Warning "   自检失败: $($_.Exception.Message)（改动可能仍在生效，稍后重试）"
}

Write-Host "`n完成。若 server 仍不是 cloudflare，请稍等 1-2 分钟后重试。" -ForegroundColor Cyan
