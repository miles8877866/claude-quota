# check-quota.ps1 — Claude 多帳號額度查詢 (Windows 版)
# 用法: powershell -ExecutionPolicy Bypass -File check-quota.ps1   (或在 profile 設 cq 函式)
#
# 與 Mac 版差異:
#   - Mac 從 Keychain 讀 token；Windows 直接讀 <config_dir>\.credentials.json
#   - token 過期時「不」自動刷新 (refreshToken 是單次性, 會跟 Claude Code 搶), 只標示需重新啟動
#
# 預設每次自動偵測 .claude / .claude1..9 / .claude-max-* (標籤=目錄名); 建 quota-accounts.override.json 可自訂覆蓋
#
# 持續監測: .\check-quota.ps1 -Watch            (預設每 60 秒刷新)
#           .\check-quota.ps1 -Watch -Interval 30
param(
    [switch]$Watch,
    [int]$Interval = 15,  # watch 刷新秒數 (輪詢制: 每 tick 只查 1 個帳號, 故可較勤)
    [int]$MaxAge = 90     # 快取秒數: 這麼短時間內已查過的帳號就讀快取, 不再打 API
)

$ErrorActionPreference = 'Stop'
$HomeDir = $env:USERPROFILE
$Config  = Join-Path $HomeDir '.claude\quota-accounts.override.json'
$CacheFile = Join-Path $HomeDir '.claude\.quota-cache.json'

# 讀快取 (label -> @{week, five, resets_at, ts})
$Cache = @{}
if (Test-Path $CacheFile) {
    try {
        (Get-Content $CacheFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object {
            $Cache[$_.Name] = @{
                week = [int]$_.Value.week; five = [int]$_.Value.five
                resets_at = [string]$_.Value.resets_at; ts = [int64]$_.Value.ts
            }
        }
    } catch {}
}

function Get-CredPath([string]$dir) { Join-Path $dir '.credentials.json' }

# --- 自動偵測帳號 (無設定檔時) ---
function Find-Accounts {
    $found = @()
    # 主帳號 .claude + 任意數量的 .claude<數字> 與 .claude-max-* (不限上限)
    $candidates = @(Join-Path $HomeDir '.claude')
    Get-ChildItem -Path $HomeDir -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\.claude(\d+|-max-.+)$' } |
        Sort-Object { ($_.Name -replace '\D', '0') -as [int] }, Name |
        ForEach-Object { $candidates += $_.FullName }

    foreach ($dir in $candidates) {
        $cred = Get-CredPath $dir
        if (Test-Path $cred) {
            # 標籤 = 目錄名去掉開頭的點 (對齊切帳號指令 claude1/claude2)
            $label = (Split-Path $dir -Leaf) -replace '^\.', ''
            $found += [pscustomobject]@{ dir = $dir; label = $label }
        }
    }
    return $found
}

# --- 取得帳號清單 ---  (@() 強制陣列, 避免單帳號被 PS 拆成純物件)
# 預設每次自動偵測 (新登入的帳號會自動出現)。
# 若要自訂標籤/順序, 建立 quota-accounts.json 即可覆蓋自動偵測。
if (Test-Path $Config) {
    $accounts = @(Get-Content $Config -Raw | ConvertFrom-Json)
} else {
    $accounts = @(Find-Accounts)
}

if (-not $accounts -or $accounts.Count -eq 0) {
    Write-Host "找不到任何已登入的帳號。先用 setup-account.ps1 登入各帳號。" -ForegroundColor Yellow
    exit 1
}

# --- 工具函式 ---
function Read-Token([string]$dir) {
    $cred = Get-CredPath $dir
    if (-not (Test-Path $cred)) { return $null }
    try {
        $d = Get-Content $cred -Raw | ConvertFrom-Json
        return $d.claudeAiOauth
    } catch { return $null }
}

function Get-Usage([string]$token) {
    $headers = @{
        'Authorization'  = "Bearer $token"
        'anthropic-beta' = 'oauth-2025-04-20'
    }
    # 額度 API 有限流; 遇 429 退避重試, 回傳 HTTP 狀態以利分辨原因 (429 限流 vs 401 失效)
    for ($try = 0; $try -lt 3; $try++) {
        try {
            $r = Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' `
                -Headers $headers -TimeoutSec 15 -ErrorAction Stop
            return @{ ok = $true; data = $r }
        } catch {
            $code = 0
            try { $code = [int]$_.Exception.Response.StatusCode.value__ } catch {}
            if ($code -eq 429 -and $try -lt 2) { Start-Sleep -Seconds (2 + $try * 2); continue }
            return @{ ok = $false; code = $code }
        }
    }
    return @{ ok = $false; code = 429 }
}

function Bar([int]$pct) {
    $filled = [math]::Floor($pct / 5)
    $empty  = 20 - $filled
    $color  = if ($pct -ge 80) { 'Red' } elseif ($pct -ge 50) { 'Yellow' } else { 'Green' }
    return @{ text = ([char]9608).ToString() * $filled + ([char]9617).ToString() * $empty; color = $color }
}

# --- 主程式 (─Watch 時包成持續刷新迴圈) ---
do {

if ($Watch) { Clear-Host }

$hour = [int](Get-Date).ToString('HH')
$peak = if ($hour -ge 5 -and $hour -lt 22) { "離峰 x2" } else { "尖峰" }
$stamp = (Get-Date).ToString('HH:mm:ss')

Write-Host ""
Write-Host "Claude 帳號額度  " -NoNewline -ForegroundColor White
Write-Host "$peak  " -NoNewline -ForegroundColor DarkGray
Write-Host "@$stamp" -ForegroundColor DarkGray
Write-Host ([string]([char]0x2500) * 56) -ForegroundColor DarkGray

$bestLabel = ''
$bestWeek  = 999
$resetStr  = ''
$nowMs     = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

$nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

# Watch 模式: 輪詢制 — 這一輪只刷新「最舊」的 1 個帳號, 其餘讀快取。
# 每個 tick 只打 1 次 API, 持續監控也不會被限流。
$refreshTarget = $null
if ($Watch) {
    $oldestTs = [int64]::MaxValue
    foreach ($a in $accounts) {
        $c = $Cache[$a.label]
        $ts = if ($c) { [int64]$c.ts } else { 0 }
        if ($ts -lt $oldestTs) { $oldestTs = $ts; $refreshTarget = $a.label }
    }
    # 若最舊的也還很新 (未超過 MaxAge), 這輪不打 API, 純顯示快取
    if ($oldestTs -ne 0 -and ($nowEpoch - $oldestTs) -lt $MaxAge) { $refreshTarget = $null }
}

foreach ($acct in $accounts) {
    $label = if ($acct.label) { $acct.label } else { '?' }
    $oauth = Read-Token $acct.dir

    if (-not $oauth -or -not $oauth.accessToken) {
        Write-Host ("  {0,-12} token 取不到" -f $label) -ForegroundColor DarkGray
        continue
    }

    $cached = $Cache[$label]
    $week = $null; $five = $null; $resISO = ''; $suffix = ''

    if ($cached -and ($nowEpoch - $cached.ts) -lt $MaxAge) {
        # 快取夠新 -> 直接用, 完全不打 API
        $week = $cached.week; $five = $cached.five; $resISO = $cached.resets_at
        $suffix = "(快取)"
    }
    elseif ($oauth.expiresAt -and [int64]$oauth.expiresAt -lt $nowMs) {
        Write-Host ("  {0,-12} token 已過期 -> 啟動一次該帳號刷新 ($($acct.label) claude)" -f $label) -ForegroundColor DarkGray
        continue
    }
    elseif ($Watch -and $refreshTarget -and $label -ne $refreshTarget) {
        # 這一輪輪不到它: 有快取就顯示(可能略舊), 沒有就標示等待輪詢
        if ($cached) {
            $week = $cached.week; $five = $cached.five; $resISO = $cached.resets_at
            $suffix = "(快取)"
        } else {
            Write-Host ("  {0,-12} 等待輪詢..." -f $label) -ForegroundColor DarkGray
            continue
        }
    }
    else {
        $res = Get-Usage $oauth.accessToken
        if ($res.ok) {
            $d = $res.data
            $week = [int]($d.seven_day.utilization)
            $five = [int]($d.five_hour.utilization)
            $resISO = [string]$d.seven_day.resets_at
            $Cache[$label] = @{ week = $week; five = $five; resets_at = $resISO; ts = $nowEpoch }
            Start-Sleep -Milliseconds 600   # 帳號間小延遲, 避免連打觸發 429
        }
        elseif ($cached) {
            # 查詢失敗(多半是 429) 但有舊快取 -> 顯示上次數值, 不報錯卡住
            $week = $cached.week; $five = $cached.five; $resISO = $cached.resets_at
            $ageMin = [int](($nowEpoch - $cached.ts) / 60)
            $suffix = "(限流→快取 ${ageMin}分前)"
        }
        else {
            $msg = switch ($res.code) {
                429     { "查詢太頻繁 (429)，稍候再試 (非 token 問題)" }
                401     { "token 失效 -> 啟動一次該帳號刷新" }
                0       { "連線/逾時失敗" }
                default { "查詢失敗 (HTTP $($res.code))" }
            }
            Write-Host ("  {0,-12} {1}" -f $label, $msg) -ForegroundColor DarkGray
            continue
        }
    }

    if ($resISO -and -not $resetStr) {
        try { $resetStr = ([datetimeoffset]$resISO).ToLocalTime().ToString('MM/dd HH:mm') } catch {}
    }
    if ($week -lt $bestWeek) { $bestWeek = $week; $bestLabel = $label }

    $b = Bar $week
    Write-Host ("  {0,-12} " -f $label) -NoNewline -ForegroundColor White
    Write-Host $b.text -NoNewline -ForegroundColor $b.color
    Write-Host ("  週:{0,3}%  5h:{1,3}%  {2}" -f $week, $five, $suffix)
}

# 寫回快取
try { ($Cache | ConvertTo-Json) | Set-Content -Path $CacheFile -Encoding utf8 } catch {}

Write-Host ([string]([char]0x2500) * 56) -ForegroundColor DarkGray
if ($resetStr) { Write-Host ("  週重置: {0} (本地時間)" -f $resetStr) -ForegroundColor DarkGray }
if ($bestLabel) {
    Write-Host ("  -> 最空: {0} (週 {1}%)" -f $bestLabel, $bestWeek) -ForegroundColor Green
}
Write-Host ""

if ($Watch) {
    Write-Host ("  每 {0} 秒輪詢刷新 1 帳號 (不會被限流), Ctrl+C 結束" -f $Interval) -ForegroundColor DarkGray
    Start-Sleep -Seconds $Interval
}

} while ($Watch)
