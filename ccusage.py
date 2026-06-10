#!/usr/bin/env python3
# ccusage.py — Claude Code 多帳號用量估值 (ccusage 風格, Windows 版)
#
# 原理: 掃描每個帳號設定目錄的對話 log (projects/**/*.jsonl), 每則 assistant 訊息
#       都記錄了 model + 真實 token 數 (input/output/cache)。按模型加總 token,
#       乘上 Anthropic API 單價, 估算「如果照 API 計費」的等值花費。
#
# 注意: 訂閱(Pro/Max/Team)是吃到飽月費, 這個金額是「等值估算」, 不是實際扣款。
#       快取單價用文件公布的倍率 (寫入 1.25x, 讀取 0.1x), 屬近似值。
#
# 用法: python ccusage.py                 # 所有帳號, 全部歷史
#       python ccusage.py --days 7        # 只算最近 7 天
#       python ccusage.py --by-account    # 額外列出每帳號明細
#       python ccusage.py --dir "C:\path\to\.claude"   # 只算指定目錄

import json, os, glob, sys, argparse
from datetime import datetime, timezone, timedelta
from collections import defaultdict

# Windows: 強制 UTF-8 輸出, 中文與框線才不會亂碼 (預設可能是 cp950/Big5)
try:
    sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass

# --- API 定價 (USD / 每百萬 token) ---
# 來源: Anthropic 官方 API 定價。快取: 寫入=輸入x1.25, 讀取=輸入x0.1
PRICING = {
    'opus':   {'in': 5.0,  'out': 25.0},
    'sonnet': {'in': 3.0,  'out': 15.0},
    'haiku':  {'in': 1.0,  'out': 5.0},
    'fable':  {'in': 10.0, 'out': 50.0},
}
CACHE_WRITE_MULT = 1.25
CACHE_READ_MULT  = 0.10

G='\033[32m'; Y='\033[33m'; C='\033[36m'; DIM='\033[2m'; BOLD='\033[1m'; RST='\033[0m'

def tier(model):
    if not model: return None
    m = model.lower()
    for t in PRICING:
        if t in m: return t
    return None

def cost(t, inp, out, cw, cr):
    p = PRICING[t]
    return ((inp + cw*CACHE_WRITE_MULT + cr*CACHE_READ_MULT) / 1e6) * p['in'] \
         + (out / 1e6) * p['out']

def fmt_usd(x):
    return f"${x:,.2f}"

def fmt_tok(n):
    if n >= 1e9: return f"{n/1e9:.2f}B"
    if n >= 1e6: return f"{n/1e6:.1f}M"
    if n >= 1e3: return f"{n/1e3:.1f}K"
    return str(int(n))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--days', type=int, default=0, help='只算最近 N 天 (0=全部)')
    ap.add_argument('--by-account', action='store_true', help='列出每帳號明細')
    ap.add_argument('--dir', default=None, help='只掃指定設定目錄')
    args = ap.parse_args()

    home = os.path.expanduser('~')
    if args.dir:
        roots = [args.dir]
    else:
        # 所有 .claude / .claude<數字>(含結尾空格) / .claude-max-*
        roots = []
        for d in glob.glob(home + '/.claude*'):
            if os.path.isdir(d) and os.path.isdir(os.path.join(d, 'projects')):
                roots.append(d)

    cutoff = None
    if args.days > 0:
        cutoff = datetime.now(timezone.utc) - timedelta(days=args.days)

    seen = set()
    # per (account, tier) -> token 累計
    acct_model = defaultdict(lambda: defaultdict(lambda: [0,0,0,0]))  # [in,out,cw,cr]
    skipped_models = defaultdict(int)

    for root in roots:
        label = os.path.basename(root.rstrip('/\\')).lstrip('.').strip() or '?'
        for fp in glob.glob(os.path.join(root, 'projects', '**', '*.jsonl'), recursive=True):
            try:
                fh = open(fp, encoding='utf-8', errors='ignore')
            except: continue
            for line in fh:
                try: d = json.loads(line)
                except: continue
                msg = d.get('message')
                if not isinstance(msg, dict): continue
                u = msg.get('usage')
                if not u: continue
                # 去重: message.id + requestId
                key = (msg.get('id','') , d.get('requestId',''))
                if key != ('','') :
                    if key in seen: continue
                    seen.add(key)
                # 日期篩選
                if cutoff:
                    ts = d.get('timestamp')
                    try:
                        if ts and datetime.fromisoformat(ts.replace('Z','+00:00')) < cutoff:
                            continue
                    except: pass
                model = msg.get('model','')
                t = tier(model)
                if not t:
                    if model and model != '<synthetic>':
                        skipped_models[model] += 1
                    continue
                rec = acct_model[label][t]
                rec[0] += u.get('input_tokens',0) or 0
                rec[1] += u.get('output_tokens',0) or 0
                rec[2] += u.get('cache_creation_input_tokens',0) or 0
                rec[3] += u.get('cache_read_input_tokens',0) or 0

    # --- 彙總 ---
    model_tot = defaultdict(lambda: [0,0,0,0])
    grand = 0.0
    for label, models in acct_model.items():
        for t, rec in models.items():
            for i in range(4): model_tot[t][i] += rec[i]
            grand += cost(t, *rec)

    period = f"最近 {args.days} 天" if args.days else "全部歷史"
    print()
    print(f"{BOLD}Claude Code 用量估值{RST}  {DIM}{period} · API 等值估算{RST}")
    print(DIM + '─'*64 + RST)

    if not model_tot:
        print("  找不到任何用量 log。先用各帳號跑過 Claude Code 才有資料。")
        print()
        return

    # 各模型總計
    print(f"  {'模型':<10}{'輸入':>9}{'輸出':>9}{'快取讀':>9}{'估值':>12}")
    print(DIM + '─'*64 + RST)
    for t in sorted(model_tot, key=lambda x: -cost(x,*model_tot[x])):
        inp,out,cw,cr = model_tot[t]
        c = cost(t, inp,out,cw,cr)
        print(f"  {t:<10}{fmt_tok(inp):>9}{fmt_tok(out):>9}{fmt_tok(cr):>9}{G}{fmt_usd(c):>12}{RST}")
    print(DIM + '─'*64 + RST)
    print(f"  {BOLD}{'總計':<10}{'':>27}{Y}{fmt_usd(grand):>12}{RST}")

    # 每帳號明細
    if args.by_account:
        print()
        print(f"{BOLD}各帳號明細{RST}")
        print(DIM + '─'*64 + RST)
        acct_cost = {}
        for label, models in acct_model.items():
            acct_cost[label] = sum(cost(t,*rec) for t,rec in models.items())
        for label in sorted(acct_cost, key=lambda x:-acct_cost[x]):
            print(f"  {C}{label}{RST}  {G}{fmt_usd(acct_cost[label])}{RST}")
            for t in sorted(acct_model[label], key=lambda x:-cost(x,*acct_model[label][x])):
                rec = acct_model[label][t]
                print(f"    {DIM}{t:<8}{RST} {fmt_tok(rec[0])} in / {fmt_tok(rec[1])} out  {fmt_usd(cost(t,*rec))}")

    if skipped_models:
        print()
        print(f"  {DIM}略過未知模型: {', '.join(sorted(skipped_models))}{RST}")
    print(f"  {DIM}* 訂閱為月費吃到飽; 此為「照 API 計費的等值」估算, 含快取倍率近似{RST}")
    print()

if __name__ == '__main__':
    main()
