# setup-account.ps1 — 為某個帳號建立獨立 config 目錄並登入 (Windows 版)
# 用法: powershell -ExecutionPolicy Bypass -File setup-account.ps1 2
#       數字 2 = 第二個帳號, 會建立 ~\.claude2 並開瀏覽器登入

param(
    [Parameter(Mandatory = $true)]
    [int]$N
)

$dir = Join-Path $env:USERPROFILE ".claude$N"
if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir | Out-Null
    Write-Host "已建立 $dir" -ForegroundColor Green
} else {
    Write-Host "$dir 已存在" -ForegroundColor DarkGray
}

Write-Host "用第 $N 個帳號登入 (瀏覽器會開啟, 請登入『不同的』Claude 帳號)..." -ForegroundColor Cyan
$env:CLAUDE_CONFIG_DIR = $dir
claude   # 進去後若未登入會提示 /login; 或直接執行登入流程
