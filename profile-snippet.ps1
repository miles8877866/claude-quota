# ===== Claude 多帳號管理 (貼到 PowerShell $PROFILE) =====
# 安裝: notepad $PROFILE  然後把下面內容貼進去, 重開終端機生效
# 腳本路徑 (skill 安裝位置)
$ClaudeQuotaScript = "$HOME\.claude\skills\claude-quota\check-quota.ps1"

# 用指定帳號目錄跑 claude, 跑完還原環境變數 (模擬 Mac alias 的單次行為)
function Use-ClaudeAccount {
    param([string]$Dir, [Parameter(ValueFromRemainingArguments = $true)]$Rest)
    $old = $env:CLAUDE_CONFIG_DIR
    $env:CLAUDE_CONFIG_DIR = $Dir
    try { claude @Rest } finally { $env:CLAUDE_CONFIG_DIR = $old }
}

# 切帳號代號: c1 = 主帳號(.claude), c2 = .claude2, ... 依你帳號數量增減
function c1 { Use-ClaudeAccount "$HOME\.claude"  @args }
function c2 { Use-ClaudeAccount "$HOME\.claude2" @args }
function c3 { Use-ClaudeAccount "$HOME\.claude3" @args }
function c4 { Use-ClaudeAccount "$HOME\.claude4" @args }
function c5 { Use-ClaudeAccount "$HOME\.claude5" @args }

# 查所有帳號額度 (一次快照)
function cq { powershell -NoProfile -ExecutionPolicy Bypass -File $ClaudeQuotaScript }
# 持續監測所有帳號 (儀表板, 預設每 60 秒刷新; cqw 30 改間隔)
function cqw { param([int]$Interval = 60) powershell -NoProfile -ExecutionPolicy Bypass -File $ClaudeQuotaScript -Watch -Interval $Interval }
# 用量估值 (ccusage 風格, 讀對話 log 算各模型等值美元; 需 python)
function cu { python "$HOME\.claude\skills\claude-quota\ccusage.py" @args }
# ===== Claude 多帳號管理 結束 =====
