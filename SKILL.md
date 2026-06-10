---
name: claude-quota
description: "Windows 版 Claude 多帳號額度管理。查所有帳號剩餘額度、切換帳號、持續監測儀表板、用量估值(ccusage 風格)、設定多帳號環境。當使用者說「cq」「額度」「quota」「剩多少」「帳號額度」「換帳號」「切帳號」「switch account」「設定多帳號」「setup multi account」「哪個帳號最空」「監測帳號」「watch quota」「cu」「用量」「花多少」「估值」「ccusage」「各模型用量」時觸發。適用 Claude Pro / Max / Team 帳號，在 Windows + PowerShell 環境執行。"
---

# claude-quota (Windows)

Windows + PowerShell 上的 Claude 多帳號額度管理。每個帳號用獨立 `CLAUDE_CONFIG_DIR` 目錄登入，靠 PowerShell 函式切換、用腳本讀各帳號 token 查 Anthropic 額度 API。

腳本位置（安裝後）：`~\.claude\skills\claude-quota\`
- `check-quota.ps1` — 查額度 / 持續監測
- `setup-account.ps1` — 建目錄並登入某帳號
- `profile-snippet.ps1` — 切帳號函式 (c1/c2…/cq/cqw)

## 何時做什麼

### 使用者說「cq」「額度」「剩多少」 → 查一次
跑：
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ~\.claude\skills\claude-quota\check-quota.ps1
```
拿到數據後，**一定要列成表格**給使用者看（他不看終端機 raw output）：

| 帳號 | 週額度 | 5h 額度 | 週重置 | 狀態 |
|------|--------|---------|--------|------|
| c1 | X% | X% | MM/DD HH:MM | 🟢/🟡/🔴 |

狀態：🟢 0–30%　🟡 31–69%　🔴 70%+
最後加一行：建議下次開新 session 用最空的帳號。

若某帳號顯示「token 已過期」，告訴使用者啟動一次該帳號（例：`c2` 進去再退出）讓 Claude Code 自動刷新 token，下次就查得到。

### 使用者說「監測」「watch」「持續看」 → 儀表板模式
**先分清楚要監控什麼**：
- **持續監控「用量」(token/估值)** → 用 `cu --watch`（讀本機 log，無 API 限流，可高頻刷新）：
  ```powershell
  python ~\.claude\skills\claude-quota\ccusage.py --watch --interval 30
  ```
- **持續監控「剩餘額度 %」** → `cqw` / `-Watch`（打額度 API）：
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File ~\.claude\skills\claude-quota\check-quota.ps1 -Watch
  ```
  額度 API 限流嚴格，故此模式用**輪詢制**：每 tick 只查 1 個帳號(最舊的)，其餘讀快取，不會被限流。預設 15 秒/tick。

提醒：額度 API 不能高頻輪詢；要「持續監控用量」優先建議 `cu --watch`（本機、無限流）。

### 使用者說「用量」「花多少」「估值」「cu」「ccusage」 → 用量估值
```powershell
python ~\.claude\skills\claude-quota\ccusage.py --by-account
```
讀各帳號對話 log（projects/**/*.jsonl）的真實 token 數 × API 單價，估算各模型「等值美元」。
`--days N` 限近 N 天。提醒使用者：訂閱是月費吃到飽，此為「照 API 計費的等值」估算，不是實際扣款。
拿到輸出後列成表格（模型 / 輸入 / 輸出 / 估值）給使用者看，並指出花最多的模型與帳號。

### 使用者說「換帳號」「切帳號」 → 說明切換方式
切換靠 `$PROFILE` 裡的函式：`c1`=主帳號、`c2`=`.claude2`、`c3`=`.claude3`…
打 `c2` 就用第二個帳號開 Claude，跑完自動還原環境變數。不用登入登出。

### 使用者說「設定多帳號」「setup」 → 帶他設定
**Step 1 — 每個帳號建目錄並登入**（數字改 2、3、4、5…）：
```powershell
~\.claude\skills\claude-quota\setup-account.ps1 2
```
會建立 `~\.claude2` 並開瀏覽器，登入「不同的」Claude 帳號。

**Step 2 — 設定切帳號函式**：把 `profile-snippet.ps1` 內容貼進 `$PROFILE`（`notepad $PROFILE`），重開終端機。提供 `c1`~`c5`、`cq`、`cqw`。

**Step 3 — 用法**：`cq` 查額度、`cqw` 持續監測、`c2` 切第二個帳號。

## 原理與安全

`check-quota.ps1` 內部：
1. 讀各帳號 `<config_dir>\.credentials.json` 的 `claudeAiOauth.accessToken`（不印出、不寫 log）
2. 帶 `anthropic-beta: oauth-2025-04-20` 呼叫 `https://api.anthropic.com/api/oauth/usage`
3. 回傳 `five_hour`（5 小時 session）與 `seven_day`（週額度）的使用百分比與重置時間

注意事項：
- **不自己刷新 token**：`refreshToken` 是單次性、會跟 Claude Code 互搶，硬刷可能把帳號登出。過期就提示啟動該帳號。
- OAuth token 是敏感資訊，只在記憶體中使用。
- `.ps1` 內含中文必須存成 **UTF-8 with BOM**，否則 PowerShell 5.1 會用 Big5 誤讀、parser 壞掉。

## 與 Mac 版差異

| 項目 | Mac | Windows |
|------|-----|---------|
| token 來源 | Keychain（`security`） | `<config_dir>\.credentials.json` 純文字 |
| 切帳號 | zsh `alias` | PowerShell `function` |
| 查額度 | bash + curl | PowerShell + `Invoke-RestMethod` |
