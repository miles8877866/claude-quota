#!/usr/bin/env python3
# ccusage.py — Claude Code 多帳號用量估值 (ccusage 風格, Windows 版)
#
# 原理: 掃描每個帳號設定目錄的對話 log (projects/**/*.jsonl), 每則 assistant 訊息
#       都記錄了 model + 真實 token 數。按模型/帳號/日期加總, 乘 API 單價估算等值花費。
#
# 注意: 訂閱(Pro/Max/Team)是吃到飽月費, 此金額為「照 API 計費的等值」估算, 非實際扣款。
#
# 用法:
#   python ccusage.py              # 本月用量 (各模型 + 各帳號)
#   python ccusage.py --daily      # 每日明細 (近 30 天, 分帳號)
#   python ccusage.py --monthly    # 每月明細 (分帳號)
#   python ccusage.py --days 7     # 近 7 天
#   python ccusage.py --all        # 有史以來全部
#   python ccusage.py --total-only # 只看總計, 不分帳號
#   python ccusage.py --watch      # 持續監控 (讀本機 log, 無 API 限流)

import json, os, glob, sys, argparse
from datetime import datetime, timezone, timedelta
from collections import defaultdict

try:
    sys.stdout.reconfigure(encoding='utf-8')   # Windows: 強制 UTF-8, 中文不亂碼
except Exception:
    pass

# --- API 定價 (USD / 每百萬 token: in 輸入, out 輸出, cr 快取讀, cw 快取寫) ---
# 預設偶爾抓線上 LiteLLM 價格庫 (快取 7 天); 抓不到才用下面這張寫死的後備表。
PRICING_FALLBACK = {
    'opus':   {'in': 5.0,  'out': 25.0, 'cr': 0.50, 'cw': 6.25},
    'sonnet': {'in': 3.0,  'out': 15.0, 'cr': 0.30, 'cw': 3.75},
    'haiku':  {'in': 1.0,  'out': 5.0,  'cr': 0.10, 'cw': 1.25},
    'fable':  {'in': 10.0, 'out': 50.0, 'cr': 1.00, 'cw': 12.5},
}
PRICING = dict(PRICING_FALLBACK)   # 由 load_pricing() 覆蓋
PRICE_SOURCE = '後備表'

LITELLM_URL = 'https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json'
PRICE_CACHE = os.path.join(os.path.expanduser('~'), '.claude', '.litellm-prices.json')
PRICE_TTL = 7 * 86400   # 7 天才重抓一次
# 各 tier 的代表 model key (新→舊, 取第一個抓得到的)
TIER_KEYS = {
    'opus':   ['claude-opus-4-8', 'claude-opus-4-7', 'claude-opus-4-6', 'claude-opus-4-5'],
    'sonnet': ['claude-sonnet-4-6', 'claude-sonnet-4-5'],
    'haiku':  ['claude-haiku-4-5'],
    'fable':  ['claude-fable-5'],
}

def load_pricing(force=False):
    """偶爾抓 LiteLLM 線上價格 (快取 7 天)。失敗則用快取/後備表。設定全域 PRICING/PRICE_SOURCE。"""
    global PRICING, PRICE_SOURCE
    import time
    # 1) 快取夠新就直接用
    if not force and os.path.isfile(PRICE_CACHE):
        try:
            c = json.load(open(PRICE_CACHE, encoding='utf-8'))
            if time.time() - c.get('fetched_at', 0) < PRICE_TTL and c.get('pricing'):
                PRICING = {k: v for k, v in c['pricing'].items()}
                PRICE_SOURCE = f"線上@{c.get('date', '?')}(快取)"
                return
        except Exception:
            pass
    # 2) 抓線上
    try:
        import urllib.request
        raw = urllib.request.urlopen(LITELLM_URL, timeout=20).read()
        db = json.loads(raw)
        new = {}
        for tier, keys in TIER_KEYS.items():
            for k in keys:
                e = db.get(k)
                if e and e.get('input_cost_per_token'):
                    new[tier] = {
                        'in': e['input_cost_per_token'] * 1e6,
                        'out': e.get('output_cost_per_token', 0) * 1e6,
                        'cr': (e.get('cache_read_input_token_cost') or e['input_cost_per_token'] * 0.1) * 1e6,
                        'cw': (e.get('cache_creation_input_token_cost') or e['input_cost_per_token'] * 1.25) * 1e6,
                    }
                    break
            if tier not in new:
                new[tier] = dict(PRICING_FALLBACK[tier])   # 該 tier 抓不到就用後備
        date = datetime.now().astimezone().strftime('%Y-%m-%d')
        PRICING = new
        PRICE_SOURCE = f"線上@{date}"
        try:
            os.makedirs(os.path.dirname(PRICE_CACHE), exist_ok=True)
            json.dump({'fetched_at': time.time(), 'date': date, 'pricing': new},
                      open(PRICE_CACHE, 'w', encoding='utf-8'))
        except Exception:
            pass
    except Exception:
        # 3) 抓不到: 有舊快取就用舊的, 否則後備表
        if os.path.isfile(PRICE_CACHE):
            try:
                c = json.load(open(PRICE_CACHE, encoding='utf-8'))
                if c.get('pricing'):
                    PRICING = {k: v for k, v in c['pricing'].items()}
                    PRICE_SOURCE = f"線上@{c.get('date', '?')}(舊快取/離線)"
                    return
            except Exception:
                pass
        PRICING = dict(PRICING_FALLBACK)
        PRICE_SOURCE = '後備表(離線)'

G='\033[32m'; Y='\033[33m'; C='\033[36m'; DIM='\033[2m'; BOLD='\033[1m'; RST='\033[0m'

def tier(model):
    if not model: return None
    m = model.lower()
    for t in PRICING:
        if t in m: return t
    return None

def cost(t, rec):
    inp, out, cw, cr = rec
    p = PRICING[t]
    return (inp*p['in'] + out*p['out'] + cw*p['cw'] + cr*p['cr']) / 1e6

def fmt_usd(x): return f"${x:,.2f}"
def fmt_tok(n):
    if n >= 1e9: return f"{n/1e9:.2f}B"
    if n >= 1e6: return f"{n/1e6:.1f}M"
    if n >= 1e3: return f"{n/1e3:.1f}K"
    return str(int(n))

def acct_inline(acct_cost):
    """把 {帳號:花費} 排序成 'claude $30, claude1 $22' 一行"""
    parts = [f"{C}{a}{RST} {fmt_usd(v)}" for a, v in sorted(acct_cost.items(), key=lambda kv: -kv[1]) if v > 0.005]
    return "  ".join(parts) if parts else f"{DIM}(無){RST}"

def scan(roots):
    """回傳 agg[(day, account, tier)] = [in,out,cw,cr]; day 為本地日期 'YYYY-MM-DD'"""
    seen = set()
    agg = defaultdict(lambda: [0, 0, 0, 0])
    skipped = defaultdict(int)
    for root in roots:
        label = os.path.basename(root.rstrip('/\\')).lstrip('.').strip() or '?'
        for fp in glob.glob(os.path.join(root, 'projects', '**', '*.jsonl'), recursive=True):
            try: fh = open(fp, encoding='utf-8', errors='ignore')
            except: continue
            for line in fh:
                try: d = json.loads(line)
                except: continue
                msg = d.get('message')
                if not isinstance(msg, dict): continue
                u = msg.get('usage')
                if not u: continue
                key = (msg.get('id', ''), d.get('requestId', ''))
                if key != ('', ''):
                    if key in seen: continue
                    seen.add(key)
                t = tier(msg.get('model', ''))
                if not t:
                    m = msg.get('model', '')
                    if m and m != '<synthetic>': skipped[m] += 1
                    continue
                # 時間 -> 本地日期
                day = '?'
                ts = d.get('timestamp')
                if ts:
                    try: day = datetime.fromisoformat(ts.replace('Z', '+00:00')).astimezone().strftime('%Y-%m-%d')
                    except: pass
                rec = agg[(day, label, t)]
                u_in = u.get('input_tokens', 0) or 0
                u_out = u.get('output_tokens', 0) or 0
                rec[0] += u_in
                rec[1] += u_out
                rec[2] += u.get('cache_creation_input_tokens', 0) or 0
                rec[3] += u.get('cache_read_input_tokens', 0) or 0
    return agg, skipped

def run_once(args):
    home = os.path.expanduser('~')
    roots = [args.dir] if args.dir else [
        d for d in glob.glob(home + '/.claude*')
        if os.path.isdir(d) and os.path.isdir(os.path.join(d, 'projects'))
    ]
    agg, skipped = scan(roots)

    now_local = datetime.now().astimezone()
    cur_month = now_local.strftime('%Y-%m')

    # ---------- 每日明細 ----------
    if args.daily:
        ndays = args.days if args.days > 0 else 30
        cutoff = (now_local - timedelta(days=ndays)).strftime('%Y-%m-%d')
        day_acct = defaultdict(lambda: defaultdict(float))
        for (day, acct, t), rec in agg.items():
            if day >= cutoff: day_acct[day][acct] += cost(t, rec)
        print()
        print(f"{BOLD}每日用量{RST}  {DIM}近 {ndays} 天 · API 等值估算{RST}")
        print(DIM + '─'*64 + RST)
        if not day_acct: print("  (這段期間沒有用量)")
        for day in sorted(day_acct, reverse=True):
            tot = sum(day_acct[day].values())
            print(f"  {BOLD}{day}{RST}  {G}{fmt_usd(tot):>9}{RST}   {acct_inline(day_acct[day])}")
        print(DIM + '─'*64 + RST)
        _footer(skipped); return

    # ---------- 每月明細 ----------
    if args.monthly:
        mon_acct = defaultdict(lambda: defaultdict(float))
        for (day, acct, t), rec in agg.items():
            mon_acct[day[:7]][acct] += cost(t, rec)
        print()
        print(f"{BOLD}每月用量{RST}  {DIM}各帳號 · API 等值估算{RST}")
        print(DIM + '─'*64 + RST)
        if not mon_acct: print("  (沒有用量)")
        for mon in sorted(mon_acct, reverse=True):
            tot = sum(mon_acct[mon].values())
            mark = f" {Y}← 本月{RST}" if mon == cur_month else ""
            print(f"  {BOLD}{mon}{RST}  {G}{fmt_usd(tot):>9}{RST}   {acct_inline(mon_acct[mon])}{mark}")
        print(DIM + '─'*64 + RST)
        _footer(skipped); return

    # ---------- 區間總計 (預設本月) ----------
    if args.all:
        title, keep = "有史以來", (lambda day: True)
    elif args.days > 0:
        cutoff = (now_local - timedelta(days=args.days)).strftime('%Y-%m-%d')
        title, keep = f"近 {args.days} 天", (lambda day: day >= cutoff)
    else:
        title, keep = f"本月 ({cur_month})", (lambda day: day.startswith(cur_month))

    model_tot = defaultdict(lambda: [0, 0, 0, 0])
    acct_model = defaultdict(lambda: defaultdict(lambda: [0, 0, 0, 0]))
    for (day, acct, t), rec in agg.items():
        if not keep(day): continue
        for i in range(4):
            model_tot[t][i] += rec[i]
            acct_model[acct][t][i] += rec[i]

    print()
    print(f"{BOLD}Claude Code 用量估值{RST}  {DIM}{title} · API 等值估算{RST}")
    print(DIM + '─'*64 + RST)
    if not model_tot:
        print("  這段期間沒有用量。")
        print(); return
    print(f"  {'模型':<10}{'輸入':>9}{'輸出':>9}{'快取讀':>9}{'估值':>12}")
    print(DIM + '─'*64 + RST)
    grand = 0.0
    for t in sorted(model_tot, key=lambda x: -cost(x, model_tot[x])):
        rec = model_tot[t]; c = cost(t, rec); grand += c
        print(f"  {t:<10}{fmt_tok(rec[0]):>9}{fmt_tok(rec[1]):>9}{fmt_tok(rec[3]):>9}{G}{fmt_usd(c):>12}{RST}")
    print(DIM + '─'*64 + RST)
    print(f"  {BOLD}{'總計':<10}{'':>27}{Y}{fmt_usd(grand):>12}{RST}")

    if not args.total_only:
        print()
        print(f"{BOLD}各帳號明細{RST}")
        print(DIM + '─'*64 + RST)
        acct_cost = {a: sum(cost(t, r) for t, r in m.items()) for a, m in acct_model.items()}
        for a in sorted(acct_cost, key=lambda x: -acct_cost[x]):
            if acct_cost[a] < 0.005: continue
            print(f"  {C}{a}{RST}  {G}{fmt_usd(acct_cost[a])}{RST}")
            for t in sorted(acct_model[a], key=lambda x: -cost(x, acct_model[a][x])):
                r = acct_model[a][t]
                print(f"    {DIM}{t:<8}{RST} {fmt_tok(r[0])} in / {fmt_tok(r[1])} out  {fmt_usd(cost(t, r))}")
    _footer(skipped)

def _footer(skipped):
    if skipped:
        print(f"  {DIM}略過未知模型: {', '.join(sorted(skipped))}{RST}")
    print(f"  {DIM}* 訂閱為月費吃到飽; 此為「照 API 計費的等值」估算 · 定價來源: {PRICE_SOURCE}{RST}")
    print()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--daily', action='store_true', help='每日明細 (近 30 天, 分帳號)')
    ap.add_argument('--monthly', action='store_true', help='每月明細 (分帳號)')
    ap.add_argument('--days', type=int, default=0, help='近 N 天 (區間總計用)')
    ap.add_argument('--all', action='store_true', help='有史以來全部 (預設只算本月)')
    ap.add_argument('--total-only', action='store_true', help='只看總計, 不分帳號')
    ap.add_argument('--by-account', action='store_true', help='(預設已開啟, 保留相容)')
    ap.add_argument('--dir', default=None, help='只掃指定設定目錄')
    ap.add_argument('--watch', action='store_true', help='持續監控 (讀本機 log, 無 API 限流)')
    ap.add_argument('--interval', type=int, default=30, help='watch 刷新秒數 (預設 30)')
    ap.add_argument('--refresh-prices', action='store_true', help='強制重抓線上定價 (平時 7 天才抓一次)')
    args = ap.parse_args()

    load_pricing(force=args.refresh_prices)   # 偶爾抓線上價 (快取 7 天), 抓不到用後備表

    if args.watch:
        import time
        while True:
            os.system('cls' if os.name == 'nt' else 'clear')
            run_once(args)
            print(f"  {DIM}每 {args.interval} 秒刷新 (讀本機 log, 無 API 限流), Ctrl+C 結束{RST}")
            try: time.sleep(args.interval)
            except KeyboardInterrupt: break
    else:
        run_once(args)

if __name__ == '__main__':
    main()
