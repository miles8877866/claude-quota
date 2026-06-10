# claude-quota

**繁體中文** ｜ [English](./README.en.md)

> Claude Code 多帳號額度管理 — Windows 版（PowerShell + cmd）。

多個 Claude 帳號（Pro / Max / Team）一次管理：在終端裡查所有帳號剩多少額度、一鍵切帳號、開儀表板持續監測，不用開網頁、不用反覆登入登出，並自動推薦「最空」的帳號。

這是 [原 Mac 版](#與-mac-版差異) 的 Windows 移植：Mac 用 Keychain + zsh alias，Windows 改用純文字 credential 檔 + PowerShell 函式 / cmd 批次檔。

---

## 功能

| 指令 | 功能 |
|------|------|
| `cq` | 一次列出所有帳號的週額度 / 5h 額度，推薦最空的帳號 |
| `cqw` | 儀表板模式，每 60 秒自動刷新（`cqw 30` 改間隔，Ctrl+C 結束） |
| `cu` | 用量估值（ccusage 風格）：讀對話 log，估算各模型「等值美元」（需 python） |
| `cu --watch` | **持續監控用量**：讀本機 log，無 API 限流，可任意高頻刷新 |
| `claude1`~`claude9` | 用第 N 個帳號開 Claude |
| `cc <數字>` | 用第 N 個帳號（不限數量，如 `cc 10`、`cc 25`） |

```
Claude 帳號額度  離峰 x2  @14:51:16
────────────────────────────────────────────────────────
  claude1      ████████░░░░░░░░░░░░  週: 38%  5h: 12%
  claude2      ██░░░░░░░░░░░░░░░░░░  週:  9%  5h:  0%
  claude3      ██████████████░░░░░░  週: 71%  5h: 55%
────────────────────────────────────────────────────────
  週重置: 06/12 02:00 (本地時間)
  -> 最空: claude2 (週 9%)
```

---

## 效果展示

**一鍵切帳號**（從帳號 1 切到 5，每打一個指令就換一個帳號，不用登入登出）：

```console
PS C:\> claude1          # ← 用帳號 1 開 Claude
  ╭─────────────────────────────────────────────╮
  │  Claude Code   ·   account: claude1 (vm1@…)  │
  ╰─────────────────────────────────────────────╯
  > /exit

PS C:\> claude2          # ← 秒切帳號 2
  ╭─────────────────────────────────────────────╮
  │  Claude Code   ·   account: claude2 (alt2@…) │
  ╰─────────────────────────────────────────────╯

PS C:\> claude3          # ← 帳號 3
PS C:\> claude4          # ← 帳號 4
PS C:\> claude5          # ← 帳號 5
PS C:\> cc 12            # ← 第 6 個以上：cc 任意數字
```

**一眼看完所有帳號額度**（`cq`）：

```console
PS C:\> cq

Claude 帳號額度  離峰 x2  @14:51:16
────────────────────────────────────────────────────────
  claude1      ████████░░░░░░░░░░░░  週: 38%  5h: 12%
  claude2      ██░░░░░░░░░░░░░░░░░░  週:  9%  5h:  0%
  claude3      ██████████████░░░░░░  週: 71%  5h: 55%
  claude4      █████░░░░░░░░░░░░░░░░  週: 25%  5h:  8%
  claude5      ██████████████████░░  週: 92%  5h: 80%
────────────────────────────────────────────────────────
  週重置: 06/12 02:00 (本地時間)
  -> 最空: claude2 (週 9%)        ← 下次開新 session 用這個最划算
```

> 🟢 0–30%（綠）　🟡 31–69%（黃）　🔴 70%+（紅），進度條顏色即時反映用量。

**用量估值**（`cu`，ccusage 風格，讀對話 log 算各模型「照 API 計費的等值美元」）：

```console
PS C:\> cu

Claude Code 用量估值  全部歷史 · API 等值估算
────────────────────────────────────────────────────────────────
  模型               輸入       輸出      快取讀          估值
────────────────────────────────────────────────────────────────
  sonnet        17.6K     3.3M   669.9M     $319.37
  opus          40.4K   431.2K    46.3M      $42.55
  haiku         25.1K    38.0K     3.9M       $1.32
────────────────────────────────────────────────────────────────
  總計                                       $363.24
```

> 訂閱是月費吃到飽，這個金額是「若照 API 單價計費的等值」估算，方便比較各帳號/各模型用量。**預設就分帳號**；`cu --days 7` 只算近 7 天，`cu --total-only` 只看總計，`cu --watch` 持續監控。

**持續監測儀表板**（`cqw`，每 60 秒自動刷新、原地更新畫面，Ctrl+C 結束）：

```console
PS C:\> cqw
# 同上表格，每 60 秒自動重查一次，時間戳 @HH:MM:SS 會跳動
  每 60 秒刷新, Ctrl+C 結束
```

---

## 快速安裝（一鍵）

下載/clone 本專案後，在專案資料夾執行：

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

`install.ps1` 會自動：
1. 把 skill 複製到 `~\.claude\skills\claude-quota\`
2. 把 cmd 啟動器（`cq`/`cqw`/`cc`/`claude1..9`）複製到 `~\.claude\bin\`
3. 把 `~\.claude\bin` 加進使用者 PATH

裝完**重開終端機**（cmd 或 PowerShell 都行）即可使用。

---

## 手動安裝

如果不想用 install.ps1：

1. **skill**：把整個資料夾複製到 `~\.claude\skills\claude-quota\`
   ```powershell
   Copy-Item -Recurse . "$env:USERPROFILE\.claude\skills\claude-quota"
   ```
2. **cmd 指令**：把 `bin\*.bat` 複製到 `~\.claude\bin\`，並把該目錄加進使用者 PATH。
3. **（選用）PowerShell 自動還原版**：把 `profile-snippet.ps1` 內容貼進 `$PROFILE`（`notepad $PROFILE`），提供「跑完自動還原環境變數」的切帳號函式。

---

## 用法

### 第一次：登入各帳號

```
claude1     → 啟動後打 /login，瀏覽器登入第 1 個帳號 → /exit
claude2     → /login 登入第 2 個帳號 → /exit
claude3     → ... 依帳號數重複
```
> 每個 `claudeN` 要登入「不同的」Claude 帳號。各帳號資料分別存在 `.claude1`、`.claude2`… 互不干擾。

### 查額度

```
cq          # 查一次，列出所有帳號
cqw         # 持續監測（每 60 秒）
cqw 30      # 改成每 30 秒
```

### 新增更多帳號

```
claude6 ~ claude9     # 第 6~9 個帳號
cc 10                 # 第 10 個 (cc 不限數量, 會自動建目錄)
cc 25                 # 任意數字
```
`cq` 會**自動偵測**所有 `.claude` / `.claude<數字>` / `.claude-max-*` 目錄，登入後即自動納入，不必設定。

---

## 運作原理

```
        cmd ──→  cq.bat / claudeN.bat  ┐
                                        ├─→  check-quota.ps1  ──→  Anthropic 額度 API
 PowerShell ──→  cq / claudeN 函式      ┘         │
                                                  └─ 讀各帳號 <dir>\.credentials.json
 Claude Code ──→ skill (claude-quota) ──┘            的 accessToken
```

**多帳號隔離**：靠 `CLAUDE_CONFIG_DIR` 環境變數讓每個帳號各自有獨立目錄（`.claude`、`.claude1`、`.claude2`…），登入資料完全分開。切帳號 = 設定該變數後啟動 `claude`。

**查額度**：`check-quota.ps1` 對每個帳號：
1. 讀 `<config_dir>\.credentials.json` 的 `claudeAiOauth.accessToken`（只在記憶體用，不印出、不寫 log）
2. 帶 `anthropic-beta: oauth-2025-04-20` header 呼叫 `https://api.anthropic.com/api/oauth/usage`
3. 取回 `five_hour`（5 小時 session）與 `seven_day`（週額度）的使用百分比與重置時間，畫成彩色表格

---

## 技術解析（移植時的關鍵發現）

移植過程實測驗證、踩坑後得到的設計決策：

### 1. token 儲存位置：檔案，不是 Keychain
Mac 用 `security` 從 Keychain 讀 token；Windows 沒有這指令。Windows 的 Claude Code 把 OAuth token 以**純文字 JSON** 存在 `<config_dir>\.credentials.json`，結構為 `claudeAiOauth.{accessToken, refreshToken, expiresAt, ...}`。直接讀檔即可，比 Mac 簡單。

### 2. 刻意「不」自動刷新 token
實測「腳本自己用 refreshToken 換新 token」這條路：先被 Cloudflare 擋（error 1010），補上 User-Agent 後回 `invalid_grant`。原因是 **`refreshToken` 是單次性、會被 Claude Code 自己輪替**。若腳本也去刷，兩邊互搶會把帳號登出。
→ 設計決策：腳本只讀現有 token，過期就標示「啟動一次該帳號刷新」，不碰刷新流程（原 Mac 版也是如此）。

### 3. PowerShell 5.1 的編碼陷阱
含中文的 `.ps1` 若存成 UTF-8 **無 BOM**，PowerShell 5.1 會用系統 codepage（繁中為 Big5）誤讀，多位元組字元含 `"`、`{` 等 byte 導致 parser 直接壞掉。
→ 所有 `.ps1` 一律存成 **UTF-8 with BOM**。`.md` 由 Claude Code skill 載入器讀（吃 UTF-8），不需 BOM；`.bat` 用純 ASCII 避免 cmd codepage 問題。

### 4. 動態偵測，不寫死數量
偵測用正則 `^\.claude(\d+|-max-.+)$` 掃描所有帳號目錄，數量無上限；標籤直接取目錄名（`.claude2` → `claude2`），對齊切帳號指令。

---

## 監控用量該用哪個？(重要)

兩種「監控」資料來源不同，限流行為完全不同：

| | 資料來源 | 限流 | 適合 |
|---|---|---|---|
| `cq` / `cqw`（額度 %） | Anthropic 額度 API | **有，且嚴格** | 偶爾查剩餘額度 |
| `cu --watch`（用量值） | 本機對話 log | **無** | 持續監控用量 |

- **想持續監控用量 → 用 `cu --watch`**：讀本機 log，不打 API，刷新多快都不會被限流。
- **`cqw`（額度儀表板）會打 API**，端點限流很嚴，不適合每幾秒輪詢。為此 `cq`/`cqw` 已內建：
  - **快取**（預設 120 秒內重複查直接讀快取，`-MaxAge` 可調）
  - **429 退避重試** + **被限流時自動顯示上次數值**（標「限流→快取」），不再卡住或誤報 token 失效。
- 原始 Mac 版沒有持續監控、是手動跑 `cq`，本來就不會撞限流；watch 模式是本專案新增的。

## 與 Mac 版差異

| 項目 | Mac | Windows |
|------|-----|---------|
| token 來源 | Keychain（`security` 指令） | `<config_dir>\.credentials.json` 純文字 |
| 切帳號 | zsh `alias` | PowerShell `function` / cmd `.bat` |
| 查額度 | bash + curl | PowerShell + `Invoke-RestMethod` |
| 持續監測 | — | `-Watch` 儀表板模式 |
| cmd 支援 | — | `.bat` 啟動器 + PATH |

---

## 疑難排解

| 症狀 | 原因 / 解法 |
|------|------------|
| 中文亂碼、parser 錯誤 | `.ps1` 須存成 **UTF-8 with BOM** |
| 「token 已過期」 | 啟動一次該帳號（`claudeN`）讓 Claude Code 自動刷新 |
| 「查詢失敗」 | token 失效，同上 |
| 「找不到任何已登入的帳號」 | 先用 `claudeN` → `/login` 登入 |
| `cq` / `claude6` 找不到指令 | PATH 變更只對「新開」的視窗生效，關掉重開終端 |
| 執行原則擋住 | `.bat` 已帶 `-ExecutionPolicy Bypass`；或 `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| 明明登入了，`cq` 卻抓不到某帳號 | 帳號目錄名**結尾多了空格**（如 `.claude1 `）。Windows 會自動截掉路徑結尾空格，PowerShell 因而讀不到。把該目錄的 `.credentials.json` 複製到無空格的目錄即可；往後切帳號只用 `claudeN` / `cc <n>` 指令，別手動 `set CLAUDE_CONFIG_DIR=...\.claudeN ` 留結尾空格 |

---

## 檔案結構

```
claude-quota/
├── README.md            # 繁中文件 (本檔)
├── README.en.md         # 英文文件
├── SKILL.md             # Claude Code skill 定義 (觸發詞 + 指示)
├── install.ps1          # 一鍵部署
├── check-quota.ps1      # 查額度 / 持續監測 (核心)
├── ccusage.py           # 用量估值 (讀對話 log 算各模型等值美元)
├── setup-account.ps1    # 建目錄並登入某帳號 (PowerShell)
├── profile-snippet.ps1  # PowerShell 切帳號函式 (貼到 $PROFILE)
├── bin/                 # cmd 啟動器
│   ├── cq.bat / cqw.bat / cu.bat / cc.bat
│   └── claude1.bat ~ claude9.bat
└── check-quota.sh       # 原 Mac 版 (參考)
```

---

## Skill 如何觸發

安裝後，在 **Claude Code 對話中**用自然語言講到觸發詞（`額度`、`查額度`、`換帳號`、`監測帳號`、`哪個帳號最空`…），Claude 會自動載入這個 skill、跑腳本並整理成表格；也可在輸入框打 `/claude-quota` 明確叫出。

差別：在**純終端機**打 `cq` 跑的是 `.bat`/函式；在**對話中**說「查額度」觸發的是 skill。兩者底層都呼叫同一個 `check-quota.ps1`。

---

## License

MIT
