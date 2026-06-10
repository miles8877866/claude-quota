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
    [int]$Interval = 60
)

$ErrorActionPreference = 'Stop'
$HomeDir = $env:USERPROFILE
$Config  = Join-Path $HomeDir '.claude\quota-accounts.override.json'

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
    try {
        $headers = @{
            'Authorization'  = "Bearer $token"
            'anthropic-beta' = 'oauth-2025-04-20'
        }
        return Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' `
            -Headers $headers -TimeoutSec 15 -ErrorAction Stop
    } catch { return $null }
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

foreach ($acct in $accounts) {
    $label = if ($acct.label) { $acct.label } else { '?' }
    $oauth = Read-Token $acct.dir

    if (-not $oauth -or -not $oauth.accessToken) {
        Write-Host ("  {0,-12} token 取不到" -f $label) -ForegroundColor DarkGray
        continue
    }

    # 本地先判斷過期 (不自己刷新, 只提示)
    if ($oauth.expiresAt -and [int64]$oauth.expiresAt -lt $nowMs) {
        Write-Host ("  {0,-12} token 已過期 -> 啟動一次該帳號刷新 ($($acct.label) claude)" -f $label) -ForegroundColor DarkGray
        continue
    }

    $d = Get-Usage $oauth.accessToken
    if (-not $d) {
        Write-Host ("  {0,-12} 查詢失敗 (token 可能已失效)" -f $label) -ForegroundColor DarkGray
        continue
    }

    $week = [int]($d.seven_day.utilization)
    $five = [int]($d.five_hour.utilization)

    if ($d.seven_day.resets_at -and -not $resetStr) {
        try {
            $t = ([datetimeoffset]$d.seven_day.resets_at).ToLocalTime()
            $resetStr = $t.ToString('MM/dd HH:mm')
        } catch {}
    }

    if ($week -lt $bestWeek) { $bestWeek = $week; $bestLabel = $label }

    $b = Bar $week
    Write-Host ("  {0,-12} " -f $label) -NoNewline -ForegroundColor White
    Write-Host $b.text -NoNewline -ForegroundColor $b.color
    Write-Host ("  週:{0,3}%  5h:{1,3}%" -f $week, $five)
}

Write-Host ([string]([char]0x2500) * 56) -ForegroundColor DarkGray
if ($resetStr) { Write-Host ("  週重置: {0} (本地時間)" -f $resetStr) -ForegroundColor DarkGray }
if ($bestLabel) {
    Write-Host ("  -> 最空: {0} (週 {1}%)" -f $bestLabel, $bestWeek) -ForegroundColor Green
}
Write-Host ""

if ($Watch) {
    Write-Host ("  每 {0} 秒刷新, Ctrl+C 結束" -f $Interval) -ForegroundColor DarkGray
    Start-Sleep -Seconds $Interval
}

} while ($Watch)
