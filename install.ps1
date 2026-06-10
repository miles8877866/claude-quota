# install.ps1 — claude-quota 一鍵部署 (Windows)
# 用法: 在專案資料夾裡執行
#   powershell -ExecutionPolicy Bypass -File install.ps1
#
# 做三件事:
#   1. 把 skill (SKILL.md + 腳本) 複製到 ~\.claude\skills\claude-quota\
#   2. 把 cmd 啟動器 (cq/cqw/cc/claude1..9.bat) 複製到 ~\.claude\bin\
#   3. 把 ~\.claude\bin 加進使用者 PATH (cmd 與 PowerShell 都能用)

$ErrorActionPreference = 'Stop'
$here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillDst = "$env:USERPROFILE\.claude\skills\claude-quota"
$binDst   = "$env:USERPROFILE\.claude\bin"

Write-Host "claude-quota 部署中..." -ForegroundColor Cyan

# 1) 安裝 skill
New-Item -ItemType Directory -Path $skillDst -Force | Out-Null
foreach ($f in 'SKILL.md','README.md','check-quota.ps1','setup-account.ps1','profile-snippet.ps1') {
    if (Test-Path "$here\$f") { Copy-Item "$here\$f" "$skillDst\$f" -Force }
}
Write-Host "  [1/3] skill -> $skillDst" -ForegroundColor Green

# 2) 安裝 cmd 啟動器
New-Item -ItemType Directory -Path $binDst -Force | Out-Null
if (Test-Path "$here\bin") { Copy-Item "$here\bin\*.bat" $binDst -Force }
Write-Host "  [2/3] 指令 (cq/cqw/cc/claude1..9) -> $binDst" -ForegroundColor Green

# 3) 加進使用者 PATH
$userPath = [Environment]::GetEnvironmentVariable('PATH','User')
if ($userPath -and ($userPath.Split(';') -contains $binDst)) {
    Write-Host "  [3/3] PATH 已含 bin 目錄" -ForegroundColor DarkGray
} else {
    $newPath = if ([string]::IsNullOrEmpty($userPath)) { $binDst } else { $userPath.TrimEnd(';') + ';' + $binDst }
    [Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
    Write-Host "  [3/3] 已將 bin 加入使用者 PATH" -ForegroundColor Green
}

Write-Host ""
Write-Host "完成! 請『重開』終端機 (cmd 或 PowerShell), 然後:" -ForegroundColor Cyan
Write-Host "  claude1   登入第 1 個帳號 (/login -> /exit), claude2/claude3... 換帳號" -ForegroundColor White
Write-Host "  cc 10     第 10 個以上的帳號 (不限數量)" -ForegroundColor White
Write-Host "  cq        查所有帳號額度" -ForegroundColor White
Write-Host "  cqw       持續監測儀表板" -ForegroundColor White
