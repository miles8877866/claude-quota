# claude-quota

[繁體中文](./README.md) ｜ **English**

> Multi-account quota manager for Claude Code — Windows edition (PowerShell + cmd).

Manage several Claude accounts (Pro / Max / Team) at once: check every account's remaining quota from the terminal, switch accounts with one command, run a live-refreshing dashboard, and get an automatic recommendation for the "emptiest" account — no browser, no repeated login/logout.

This is a Windows port of the [original macOS version](#differences-from-the-macos-version): macOS uses the Keychain + zsh aliases; Windows uses the plaintext credential file + PowerShell functions / cmd batch files.

---

## Features

| Command | What it does |
|---------|--------------|
| `cq` | List every account's weekly / 5h quota at once; recommends the emptiest account |
| `cqw` | Dashboard mode, auto-refresh every 60s (`cqw 30` to change interval, Ctrl+C to quit) |
| `cu` | Usage valuation (ccusage-style): reads conversation logs, estimates per-model "API-equivalent USD" (needs python) |
| `claude1`~`claude9` | Launch Claude with account N |
| `cc <n>` | Use account N (unlimited, e.g. `cc 10`, `cc 25`) |

```
Claude 帳號額度  離峰 x2  @14:51:16
────────────────────────────────────────────────────────
  claude1      ████████░░░░░░░░░░░░  week: 38%  5h: 12%
  claude2      ██░░░░░░░░░░░░░░░░░░  week:  9%  5h:  0%
  claude3      ██████████████░░░░░░  week: 71%  5h: 55%
────────────────────────────────────────────────────────
  weekly reset: 06/12 02:00 (local)
  -> emptiest: claude2 (week 9%)
```

---

## Demo

**One-command account switching** (jump from account 1 to 5 — one command per account, no login/logout):

```console
PS C:\> claude1          # ← open Claude as account 1
  ╭─────────────────────────────────────────────╮
  │  Claude Code   ·   account: claude1 (vm1@…)  │
  ╰─────────────────────────────────────────────╯
  > /exit

PS C:\> claude2          # ← instantly switch to account 2
  ╭─────────────────────────────────────────────╮
  │  Claude Code   ·   account: claude2 (alt2@…) │
  ╰─────────────────────────────────────────────╯

PS C:\> claude3          # ← account 3
PS C:\> claude4          # ← account 4
PS C:\> claude5          # ← account 5
PS C:\> cc 12            # ← account 6+ : cc takes any number
```

**See every account's quota at a glance** (`cq`):

```console
PS C:\> cq

Claude 帳號額度  離峰 x2  @14:51:16
────────────────────────────────────────────────────────
  claude1      ████████░░░░░░░░░░░░  week: 38%  5h: 12%
  claude2      ██░░░░░░░░░░░░░░░░░░  week:  9%  5h:  0%
  claude3      ██████████████░░░░░░  week: 71%  5h: 55%
  claude4      █████░░░░░░░░░░░░░░░░  week: 25%  5h:  8%
  claude5      ██████████████████░░  week: 92%  5h: 80%
────────────────────────────────────────────────────────
  weekly reset: 06/12 02:00 (local)
  -> emptiest: claude2 (week 9%)     ← best account for your next session
```

> 🟢 0–30% (green)　🟡 31–69% (yellow)　🔴 70%+ (red) — the bar color reflects usage in real time.

**Usage valuation** (`cu`, ccusage-style — reads conversation logs, estimates per-model "API-equivalent USD"):

```console
PS C:\> cu --by-account

Claude Code 用量估值  全部歷史 · API 等值估算
────────────────────────────────────────────────────────────────
  model              input     output   cache-rd        value
────────────────────────────────────────────────────────────────
  sonnet        17.6K     3.3M   669.9M     $319.37
  opus          40.4K   431.2K    46.3M      $42.55
  haiku         25.1K    38.0K     3.9M       $1.32
────────────────────────────────────────────────────────────────
  total                                      $363.24
```

> Subscriptions are flat-fee, so this figure is an "if billed at API rates" estimate — useful for comparing usage across accounts/models. `cu --days 7` limits to the last 7 days; `cu --by-account` breaks it down per account.

**Live dashboard** (`cqw`, auto-refreshes every 60s in place, Ctrl+C to quit):

```console
PS C:\> cqw
# same table, re-queried every 60s; the @HH:MM:SS timestamp ticks
  refreshing every 60s, Ctrl+C to quit
```

---

## Quick install (one command)

Clone/download this repo, then from the project folder run:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

`install.ps1` automatically:
1. Copies the skill to `~\.claude\skills\claude-quota\`
2. Copies the cmd launchers (`cq`/`cqw`/`cc`/`claude1..9`) to `~\.claude\bin\`
3. Adds `~\.claude\bin` to your user PATH

After install, **reopen your terminal** (cmd or PowerShell) and you're ready.

---

## Manual install

If you prefer not to use `install.ps1`:

1. **Skill**: copy the whole folder to `~\.claude\skills\claude-quota\`
   ```powershell
   Copy-Item -Recurse . "$env:USERPROFILE\.claude\skills\claude-quota"
   ```
2. **cmd commands**: copy `bin\*.bat` to `~\.claude\bin\` and add that folder to your user PATH.
3. **(Optional) PowerShell with env-restore**: paste `profile-snippet.ps1` into `$PROFILE` (`notepad $PROFILE`) for switch functions that restore the env var after running.

---

## Usage

### First time: log in each account

```
claude1     → run /login, sign in to account 1 in the browser → /exit
claude2     → /login, sign in to account 2 → /exit
claude3     → ... repeat per account
```
> Each `claudeN` must sign in to a *different* Claude account. Each account's data lives separately in `.claude1`, `.claude2`, … fully isolated.

### Check quota

```
cq          # one-shot, lists all accounts
cqw         # live dashboard (every 60s)
cqw 30      # every 30s
```

### Add more accounts

```
claude6 ~ claude9     # accounts 6–9
cc 10                 # account 10 (cc is unlimited, auto-creates the dir)
cc 25                 # any number
```
`cq` **auto-detects** all `.claude` / `.claude<number>` / `.claude-max-*` directories — once logged in they show up automatically, no config needed.

---

## How it works

```
        cmd ──→  cq.bat / claudeN.bat  ┐
                                        ├─→  check-quota.ps1  ──→  Anthropic usage API
 PowerShell ──→  cq / claudeN funcs     ┘         │
                                                  └─ reads each account's
 Claude Code ──→ skill (claude-quota) ──┘            <dir>\.credentials.json accessToken
```

**Account isolation**: the `CLAUDE_CONFIG_DIR` env var gives each account its own directory (`.claude`, `.claude1`, `.claude2`, …) with fully separate login data. Switching = set that var, then launch `claude`.

**Quota check**: for each account, `check-quota.ps1`:
1. Reads `claudeAiOauth.accessToken` from `<config_dir>\.credentials.json` (in-memory only — never printed or logged)
2. Calls `https://api.anthropic.com/api/oauth/usage` with the `anthropic-beta: oauth-2025-04-20` header
3. Renders `five_hour` (5-hour session) and `seven_day` (weekly) utilization % and reset times as a colored table

---

## Technical notes (key findings from the port)

Design decisions reached by actually testing and hitting walls during the port:

### 1. Tokens live in a file, not the Keychain
macOS reads the token from the Keychain via `security`; Windows has no such command. On Windows, Claude Code stores the OAuth token as **plaintext JSON** at `<config_dir>\.credentials.json`, shaped as `claudeAiOauth.{accessToken, refreshToken, expiresAt, ...}`. Reading the file directly is simpler than the Keychain dance.

### 2. Deliberately does NOT auto-refresh tokens
Tested the "let the script swap the token using refreshToken" path: first blocked by Cloudflare (error 1010), then after adding a User-Agent it returned `invalid_grant`. Reason: the **`refreshToken` is single-use and gets rotated by Claude Code itself**. If the script also refreshes, the two race and log you out.
→ Decision: the script only reads the existing token. If expired, it flags "launch that account once to refresh" instead of touching the refresh flow (the macOS version behaves the same way).

### 3. PowerShell 5.1 encoding trap
A `.ps1` containing Chinese, saved as UTF-8 **without BOM**, is misread by PowerShell 5.1 using the system codepage (Big5 for zh-TW); multibyte chars contain bytes like `"` and `{` that break the parser outright.
→ All `.ps1` files are saved as **UTF-8 with BOM**. `.md` files are read by the Claude Code skill loader (UTF-8, no BOM needed); `.bat` files are pure ASCII to dodge cmd codepage issues.

### 4. Dynamic detection, no hardcoded limit
Detection uses the regex `^\.claude(\d+|-max-.+)$` to scan all account directories — no upper bound. Labels come straight from the directory name (`.claude2` → `claude2`), matching the switch commands.

---

## Differences from the macOS version

| Aspect | macOS | Windows |
|--------|-------|---------|
| Token source | Keychain (`security`) | `<config_dir>\.credentials.json` plaintext |
| Switch account | zsh `alias` | PowerShell `function` / cmd `.bat` |
| Quota check | bash + curl | PowerShell + `Invoke-RestMethod` |
| Live monitor | — | `-Watch` dashboard mode |
| cmd support | — | `.bat` launchers + PATH |

---

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| Garbled Chinese, parser error | `.ps1` must be saved as **UTF-8 with BOM** |
| "token expired" | Launch that account once (`claudeN`) so Claude Code refreshes it |
| "query failed" | Token invalid — same fix as above |
| "no logged-in account found" | Log in first via `claudeN` → `/login` |
| `cq` / `claude6` not recognized | PATH changes only apply to *newly opened* windows — reopen the terminal |
| Execution policy blocks it | `.bat` already passes `-ExecutionPolicy Bypass`; or run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| Logged in, but `cq` doesn't find an account | The account dir name has a **trailing space** (e.g. `.claude1 `). Windows strips trailing spaces from path components, so PowerShell can't read it. Copy that dir's `.credentials.json` into the space-free dir; from then on only switch with `claudeN` / `cc <n>` and never `set CLAUDE_CONFIG_DIR=...\.claudeN ` with a trailing space |

---

## File layout

```
claude-quota/
├── README.md            # Chinese docs
├── README.en.md         # English docs (this file)
├── SKILL.md             # Claude Code skill definition (triggers + instructions)
├── install.ps1          # one-click deploy
├── check-quota.ps1      # quota check / live monitor (core)
├── ccusage.py           # usage valuation (reads logs, per-model USD estimate)
├── setup-account.ps1    # create dir + log in an account (PowerShell)
├── profile-snippet.ps1  # PowerShell switch functions (paste into $PROFILE)
├── bin/                 # cmd launchers
│   ├── cq.bat / cqw.bat / cu.bat / cc.bat
│   └── claude1.bat ~ claude9.bat
└── check-quota.sh       # original macOS version (reference)
```

---

## How the skill triggers

After install, in a **Claude Code conversation** mention a trigger phrase (quota, check quota, switch account, monitor accounts, which account is emptiest, …) and Claude auto-loads this skill, runs the script, and formats the result as a table. You can also type `/claude-quota` to invoke it explicitly.

The difference: typing `cq` in a **plain terminal** runs the `.bat`/function; saying "check quota" **in conversation** triggers the skill. Both call the same `check-quota.ps1` underneath.

---

## License

MIT
