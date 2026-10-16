"""FOMO memecoin paper bot (MEME_FOMO_V1). Paper only: no wallet, no keys, no real orders.

A separate simulated cohort that chases short, fresh pumps on new Solana tokens, with its own
tables (meme_fomo_*) so its results never mix with the paused MEME_PAPER_V1 ledger.

Entry (all must hold, on two looks 25-150 s apart, price not lower on the second look):
  * token is new-ish (pair 5 min - 24 h old) and is boosted / freshly profiled on DEX Screener
  * the shared rug gates pass (liquidity, holder and dev concentration, mint/freeze authority,
    sellability, LP control) - security checked only for tokens that already look like a pump
  * a fresh pump: 5-min price +4..+40 %, 1-h price +15..+300 %, 5-min volume >= 2.5x the 1-h
    average pace, >= 25 buys in 5 min, buys/sells >= 1.3
  * not too late: caps on the 5-min and 1-h move skip blow-off tops
Exits (checked every 10 s): -12 % stop; sell half at +25 % and move the stop to cost; sell a
quarter more at +60 %; the rest trails 15 % under the peak; out at 12 min if +25 % never came,
on a buyer fade, on a liquidity pull, or at 45 min. Gaps fill at the observed price, never at the
stop level. Same costs as the main ledger: 1 % slippage + 0.6 % fee on every buy and sell.

Risk caps: $100 per trade, 3 open at once, one trade per token, new entries stop for the UTC day
after -$40 realized. MEME_FOMO_ENABLED=0 stops new entries; open positions still exit.
"""
import argparse, json, os, time
from datetime import datetime, timezone, timedelta

from memecoin_shadow import safety_reasons, PAPER_FEE_RATE as FEE, PAPER_SLIPPAGE_RATE as SLIP

VERSION = "MEME_FOMO_V1"
DEX = "https://api.dexscreener.com"
NOTIONAL_USD = 100.0
MAX_OPEN = 3
DAILY_LOSS_LIMIT_USD = -40.0
BATCH = 30  # DEX Screener accepts up to 30 addresses per batch call

ENTRY = {
    "min_pair_age_min": 5, "max_pair_age_h": 24,
    "min_m5_pct": 4.0, "max_m5_pct": 40.0,
    "min_h1_pct": 15.0, "max_h1_pct": 300.0,
    "min_vol_accel": 2.5, "min_m5_volume_usd": 5000.0,
    "min_m5_buys": 25, "min_buy_ratio": 1.3,
    "confirm_min_s": 25, "confirm_max_s": 150,
}
EXIT = {
    "stop_pct": -12.0, "be_stop_pct": 3.5,  # 3.5 % covers the ~3.2 % round-trip cost
    "tp1_pct": 25.0, "tp1_frac": 0.50, "tp2_pct": 60.0, "tp2_frac": 0.25,
    "trail_pct": 15.0, "no_progress_min": 12.0, "max_hold_min": 45.0,
    "fade_after_min": 3.0, "fade_buy_ratio": 0.9, "liq_pull_frac": 0.5,
    "no_price_grace_min": 15.0,
}


# ---------- storage (SQLite locally, PostgreSQL on Render) ----------
def _pg(c):
    return c.__class__.__module__.startswith("psycopg") or getattr(c, "dialect", "") == "postgres"

def q(c, sql, params=()):
    return c.execute(sql.replace("?", "%s") if _pg(c) else sql, params)

def init(c):
    pk = "BIGSERIAL PRIMARY KEY" if _pg(c) else "INTEGER PRIMARY KEY"
    real = "DOUBLE PRECISION" if _pg(c) else "REAL"
    c.execute(f"""CREATE TABLE IF NOT EXISTS meme_fomo_signals(id {pk},seen_at TEXT,version TEXT,token TEXT,
      token_address TEXT,pair_address TEXT,stage TEXT,price {real},reasons TEXT,metrics_json TEXT)""")
    c.execute(f"""CREATE TABLE IF NOT EXISTS meme_fomo_trades(id {pk},version TEXT,token TEXT,token_address TEXT,
      pair_address TEXT,opened_at TEXT,entry_market_price {real},entry_price {real},notional_usd {real},
      quantity {real},remaining_qty {real},entry_fee {real},entry_liquidity_usd {real},status TEXT,
      peak_price {real},low_price {real},last_price {real},last_price_at TEXT,tp1_hit INTEGER,tp2_hit INTEGER,
      realized_usd {real},closed_at TEXT,exit_reason TEXT,net_pnl_usd {real},net_return_pct {real},
      fills_json TEXT,signal_json TEXT)""")
    c.execute("CREATE INDEX IF NOT EXISTS meme_fomo_signals_tok ON meme_fomo_signals(token_address,seen_at)")
    c.execute("CREATE INDEX IF NOT EXISTS meme_fomo_trades_tok ON meme_fomo_trades(token_address)")
    c.commit()


# ---------- market data ----------
_SEC_CACHE = {}
SEC_TTL_S = 600

def _get(url):
    from memecoin_discovery import get_json
    return get_json(url)

def feed_addresses(limit=60):
    """Newest boosted, top boosted, and newly profiled Solana tokens: where FOMO attention shows up first."""
    out, seen = [], set()
    for path in ("/token-boosts/latest/v1", "/token-boosts/top/v1", "/token-profiles/latest/v1"):
        try:
            rows = _get(DEX + path)
        except Exception as e:
            print(f"::warning::fomo feed {path}: {e}", flush=True); continue
        for r in rows if isinstance(rows, list) else []:
            a = r.get("tokenAddress")
            if r.get("chainId") == "solana" and a and a not in seen:
                seen.add(a); out.append(a)
    return out[:limit]

def pairs_for_tokens(addresses):
    """{token_address: deepest-liquidity pair} using batch lookups."""
    best = {}
    for i in range(0, len(addresses), BATCH):
        chunk = addresses[i:i + BATCH]
        try:
            rows = _get(f"{DEX}/tokens/v1/solana/{','.join(chunk)}")
        except Exception as e:
            print(f"::warning::fomo pair batch: {e}", flush=True); continue
        for p in rows if isinstance(rows, list) else []:
            a = (p.get("baseToken") or {}).get("address")
            if a not in chunk or not p.get("priceUsd"): continue
            if a not in best or _liq(p) > _liq(best[a]): best[a] = p
    return best

def pairs_by_address(pair_addresses):
    out = {}
    for i in range(0, len(pair_addresses), BATCH):
        chunk = pair_addresses[i:i + BATCH]
        try:
            data = _get(f"{DEX}/latest/dex/pairs/solana/{','.join(chunk)}")
        except Exception as e:
            print(f"::warning::fomo price refresh: {e}", flush=True); continue
        rows = (data.get("pairs") or ([data["pair"]] if data.get("pair") else [])) if isinstance(data, dict) else (data or [])
        for p in rows:
            if p and p.get("pairAddress"): out[p["pairAddress"]] = p
    return out

def security(address, now_s=None):
    now_s = now_s or time.time()
    hit = _SEC_CACHE.get(address)
    if hit and now_s - hit[0] < SEC_TTL_S: return hit[1]
    from memecoin_discovery import goplus
    sec = goplus(address)
    _SEC_CACHE[address] = (now_s, sec)
    return sec


# ---------- signal logic ----------
def _f(v):
    try: return float(v or 0)
    except (TypeError, ValueError): return 0.0

def _liq(p): return _f((p.get("liquidity") or {}).get("usd"))

def metrics(pair, now):
    tx5 = (pair.get("txns") or {}).get("m5") or {}
    vol = pair.get("volume") or {}; pc = pair.get("priceChange") or {}
    buys, sells = int(tx5.get("buys") or 0), int(tx5.get("sells") or 0)
    h1v = _f(vol.get("h1")); m5v = _f(vol.get("m5"))
    created = pair.get("pairCreatedAt")
    age_min = (now.timestamp() * 1000 - float(created)) / 60000 if created else None
    return {"price": _f(pair.get("priceUsd")), "liquidity_usd": _liq(pair), "pair_age_min": age_min,
            "m5_pct": _f(pc.get("m5")), "h1_pct": _f(pc.get("h1")), "m5_volume_usd": m5v,
            "vol_accel": round(m5v / max(h1v / 12, 1.0), 3), "m5_buys": buys, "m5_sells": sells,
            "buy_ratio": round(buys / max(sells, 1), 3)}

def momentum_reasons(m, r=ENTRY):
    out = []
    age = m["pair_age_min"]
    if age is None or age < r["min_pair_age_min"]: out.append("TOO_NEW_OR_UNKNOWN_AGE")
    elif age > r["max_pair_age_h"] * 60: out.append("NOT_FRESH")
    if m["m5_pct"] < r["min_m5_pct"]: out.append("NO_5M_PUMP")
    if m["m5_pct"] > r["max_m5_pct"]: out.append("5M_BLOWOFF")
    if m["h1_pct"] < r["min_h1_pct"]: out.append("NO_1H_TREND")
    if m["h1_pct"] > r["max_h1_pct"]: out.append("1H_OVEREXTENDED")
    if m["vol_accel"] < r["min_vol_accel"] or m["m5_volume_usd"] < r["min_m5_volume_usd"]: out.append("NO_VOLUME_SURGE")
    if m["m5_buys"] < r["min_m5_buys"] or m["buy_ratio"] < r["min_buy_ratio"]: out.append("SELLERS_IN_CONTROL")
    return out

def rug_reasons(pair, sec):
    from memecoin_discovery import normalize
    x = normalize({"tokenAddress": (pair.get("baseToken") or {}).get("address")}, pair, sec)
    r = safety_reasons(x)
    if not sec: r.append("SECURITY_UNAVAILABLE")  # never buy blind
    return r


# ---------- ledger ----------
def _log(c, now, token, addr, pair_addr, stage, price, reasons, m):
    q(c, """INSERT INTO meme_fomo_signals(seen_at,version,token,token_address,pair_address,stage,price,reasons,metrics_json)
      VALUES(?,?,?,?,?,?,?,?,?)""", (now.isoformat(), VERSION, token, addr, pair_addr, stage, price, json.dumps(reasons), json.dumps(m)))

SIGNAL_KEEP_DAYS = 7
REPEAT_LOG_MIN = 60

def _logged_recently(c, addr, stage, now):
    since = (now - timedelta(minutes=REPEAT_LOG_MIN)).isoformat()
    return q(c, "SELECT 1 FROM meme_fomo_signals WHERE token_address=? AND stage=? AND seen_at>=? LIMIT 1",
             (addr, stage, since)).fetchone() is not None

def prune(c, now):
    """Keep the free database small: drop non-entry signal rows after 7 days. Trades are never deleted."""
    cut = (now - timedelta(days=SIGNAL_KEEP_DAYS)).isoformat()
    q(c, "DELETE FROM meme_fomo_signals WHERE stage<>'ENTERED' AND seen_at<?", (cut,))

def realized_today(c, now):
    day = now.replace(hour=0, minute=0, second=0, microsecond=0).isoformat()
    return _f(q(c, "SELECT COALESCE(SUM(net_pnl_usd),0) FROM meme_fomo_trades WHERE status='CLOSED' AND closed_at>=?", (day,)).fetchone()[0])

def entry_veto(c, addr, now):
    if os.getenv("MEME_FOMO_ENABLED", "1") == "0": return "FOMO_DISABLED"
    if q(c, "SELECT 1 FROM meme_fomo_trades WHERE token_address=? LIMIT 1", (addr,)).fetchone(): return "ALREADY_TRADED"
    if q(c, "SELECT COUNT(*) FROM meme_fomo_trades WHERE status='OPEN'").fetchone()[0] >= MAX_OPEN: return "MAX_OPEN"
    if realized_today(c, now) <= DAILY_LOSS_LIMIT_USD: return "DAILY_LOSS_LIMIT"
    return None

def open_trade(c, now, token, addr, pair, m):
    p = m["price"]; ep = p * (1 + SLIP); fee = NOTIONAL_USD * FEE; qty = (NOTIONAL_USD - fee) / ep
    q(c, """INSERT INTO meme_fomo_trades(version,token,token_address,pair_address,opened_at,entry_market_price,entry_price,
      notional_usd,quantity,remaining_qty,entry_fee,entry_liquidity_usd,status,peak_price,low_price,last_price,last_price_at,
      tp1_hit,tp2_hit,realized_usd,fills_json,signal_json) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,'OPEN',?,?,?,?,0,0,0,'[]',?)""",
      (VERSION, token, addr, pair.get("pairAddress"), now.isoformat(), p, ep, NOTIONAL_USD, qty, qty, fee,
       m["liquidity_usd"], p, p, p, now.isoformat(), json.dumps(m)))

def scan(c, now=None, addresses=None, fetch_pairs=None, fetch_sec=None):
    """One discovery pass: log pumps, confirm on the second look, open paper trades. Returns opened tokens."""
    now = now or datetime.now(timezone.utc)
    fetch_pairs = fetch_pairs or pairs_for_tokens; fetch_sec = fetch_sec or security
    since = (now - timedelta(seconds=ENTRY["confirm_max_s"])).isoformat()
    pending = {r[0]: (r[1], _f(r[2])) for r in q(c, """SELECT token_address,MAX(seen_at),MAX(price) FROM meme_fomo_signals
      WHERE stage='FIRST_LOOK' AND seen_at>=? GROUP BY token_address""", (since,)).fetchall()}
    addrs = list(dict.fromkeys(list(pending) + list(addresses if addresses is not None else feed_addresses())))
    traded = {r[0] for r in q(c, "SELECT DISTINCT token_address FROM meme_fomo_trades").fetchall()}
    addrs = [a for a in addrs if a not in traded]  # one trade per token: skip without logging or security calls
    opened = []
    for addr, pair in (fetch_pairs(addrs) if addrs else {}).items():
        token = (pair.get("baseToken") or {}).get("symbol") or addr
        m = metrics(pair, now)
        if momentum_reasons(m):
            continue  # not pumping: not logged, keeps the table small
        rug = rug_reasons(pair, fetch_sec(addr))
        if rug:
            if not _logged_recently(c, addr, "RUG_FILTERED", now):
                _log(c, now, token, addr, pair.get("pairAddress"), "RUG_FILTERED", m["price"], rug, m)
            continue
        first = pending.get(addr)
        age_s = (now - datetime.fromisoformat(first[0])).total_seconds() if first else None
        if not first or age_s < ENTRY["confirm_min_s"]:
            if not first: _log(c, now, token, addr, pair.get("pairAddress"), "FIRST_LOOK", m["price"], [], m)
            continue
        if m["price"] < first[1]:
            _log(c, now, token, addr, pair.get("pairAddress"), "FAILED_CONFIRM", m["price"], ["PRICE_LOWER_ON_SECOND_LOOK"], m); continue
        veto = entry_veto(c, addr, now)
        if veto:
            if not _logged_recently(c, addr, "VETOED", now):
                _log(c, now, token, addr, pair.get("pairAddress"), "VETOED", m["price"], [veto], m)
            continue
        _log(c, now, token, addr, pair.get("pairAddress"), "ENTERED", m["price"], [], m)
        open_trade(c, now, token, addr, pair, m); opened.append(token)
    prune(c, now)
    c.commit()
    return opened


# ---------- exits ----------
def _sell(t, frac_of_original, price, reason, now):
    qty = min(t["quantity"] * frac_of_original, t["remaining_qty"])
    if qty <= 0: return
    fill = price * (1 - SLIP); gross = qty * fill; fee = gross * FEE
    t["remaining_qty"] -= qty; t["realized_usd"] += gross - fee
    t["fills"].append({"at": now.isoformat(), "reason": reason, "qty": qty, "market_price": price, "fill_price": fill, "fee": fee})

def decide(t, price, m, now):
    """Apply the exit ladder to one open trade dict in place. Returns the closing reason or None."""
    entry = t["entry_market_price"]; ret = (price / entry - 1) * 100
    t["peak_price"] = max(t["peak_price"], price); t["low_price"] = min(t["low_price"], price)
    age = (now - datetime.fromisoformat(t["opened_at"])).total_seconds() / 60
    if not t["tp1_hit"] and ret >= EXIT["tp1_pct"]:
        _sell(t, EXIT["tp1_frac"], price, "TP1_25", now); t["tp1_hit"] = 1
    if t["tp1_hit"] and not t["tp2_hit"] and ret >= EXIT["tp2_pct"]:
        _sell(t, EXIT["tp2_frac"], price, "TP2_60", now); t["tp2_hit"] = 1
    reason = None
    if not t["tp1_hit"]:
        if ret <= EXIT["stop_pct"]: reason = "STOP_12"
        elif m and t["entry_liquidity_usd"] and m["liquidity_usd"] < t["entry_liquidity_usd"] * EXIT["liq_pull_frac"]: reason = "LIQUIDITY_PULL"
        elif m and age >= EXIT["fade_after_min"] and ret < 0 and m["buy_ratio"] < EXIT["fade_buy_ratio"]: reason = "BUYERS_FADED"
        elif age >= EXIT["no_progress_min"]: reason = "NO_PROGRESS_12M"
    else:
        if ret <= EXIT["be_stop_pct"]: reason = "BREAKEVEN_STOP"
        elif price <= t["peak_price"] * (1 - EXIT["trail_pct"] / 100): reason = "TRAIL_15"
        elif m and t["entry_liquidity_usd"] and m["liquidity_usd"] < t["entry_liquidity_usd"] * EXIT["liq_pull_frac"]: reason = "LIQUIDITY_PULL"
    if not reason and age >= EXIT["max_hold_min"]: reason = "MAX_HOLD_45M"
    if reason: _sell(t, 1.0, price, reason, now)
    return reason

COLS = ("id,token,pair_address,opened_at,entry_market_price,quantity,remaining_qty,entry_liquidity_usd,peak_price,low_price,"
        "last_price_at,tp1_hit,tp2_hit,realized_usd,fills_json,notional_usd")

def _close(c, t, now, reason):
    net = t["realized_usd"] - t["notional_usd"]
    q(c, """UPDATE meme_fomo_trades SET status='CLOSED',closed_at=?,exit_reason=?,net_pnl_usd=?,net_return_pct=?
      WHERE id=? AND status='OPEN'""", (now.isoformat(), reason, net, 100 * net / t["notional_usd"], t["id"]))

def manage(c, now=None, fetch=None):
    """Refresh open FOMO trades and run exits. Returns [(token, reason, net_pnl)] for closed trades."""
    now = now or datetime.now(timezone.utc); fetch = fetch or pairs_by_address
    rows = [dict(zip(COLS.split(","), r)) for r in q(c, f"SELECT {COLS} FROM meme_fomo_trades WHERE status='OPEN' ORDER BY id").fetchall()]
    if not rows: return []
    live = fetch([t["pair_address"] for t in rows]); closed = []
    for t in rows:
        t["fills"] = json.loads(t["fills_json"] or "[]")
        for k in ("quantity", "remaining_qty", "realized_usd", "peak_price", "low_price", "entry_market_price", "notional_usd"): t[k] = _f(t[k])
        pair = live.get(t["pair_address"])
        price = _f(pair.get("priceUsd")) if pair else 0.0
        if price <= 0:
            stale = (now - datetime.fromisoformat(t["last_price_at"])).total_seconds() / 60
            age = (now - datetime.fromisoformat(t["opened_at"])).total_seconds() / 60
            if age >= EXIT["max_hold_min"] and stale >= EXIT["no_price_grace_min"]:
                t["remaining_qty"] = 0.0  # pair vanished (likely rugged): count what is left as worthless
                _close(c, t, now, "NO_PRICE_ASSUMED_ZERO"); closed.append((t["token"], "NO_PRICE_ASSUMED_ZERO", round(t["realized_usd"] - t["notional_usd"], 2)))
            continue
        reason = decide(t, price, metrics(pair, now), now)
        q(c, """UPDATE meme_fomo_trades SET remaining_qty=?,peak_price=?,low_price=?,last_price=?,last_price_at=?,
          tp1_hit=?,tp2_hit=?,realized_usd=?,fills_json=? WHERE id=?""",
          (t["remaining_qty"], t["peak_price"], t["low_price"], price, now.isoformat(), t["tp1_hit"], t["tp2_hit"],
           t["realized_usd"], json.dumps(t["fills"]), t["id"]))
        if reason:
            _close(c, t, now, reason); closed.append((t["token"], reason, round(t["realized_usd"] - t["notional_usd"], 2)))
    c.commit()
    return closed


# ---------- report ----------
def summary(c, now=None):
    now = now or datetime.now(timezone.utc)
    closed = q(c, "SELECT token,net_pnl_usd,exit_reason,opened_at,closed_at,tp1_hit FROM meme_fomo_trades WHERE status='CLOSED' ORDER BY id").fetchall()
    open_rows = q(c, "SELECT token,opened_at,entry_market_price,last_price,remaining_qty,quantity,tp1_hit FROM meme_fomo_trades WHERE status='OPEN' ORDER BY id").fetchall()
    pnl = [_f(r[1]) for r in closed]; wins = [x for x in pnl if x > 0]; losses = [x for x in pnl if x <= 0]
    peak = run = dd = 0.0
    for x in pnl:
        run += x; peak = max(peak, run); dd = min(dd, run - peak)
    by_exit = {}
    for r in closed:
        e = by_exit.setdefault(r[2], {"trades": 0, "net_pnl_usd": 0.0}); e["trades"] += 1; e["net_pnl_usd"] = round(e["net_pnl_usd"] + _f(r[1]), 2)
    stages = dict(q(c, "SELECT stage,COUNT(*) FROM meme_fomo_signals GROUP BY stage").fetchall())
    return {"version": VERSION, "mode": "paper_only", "entries_enabled": os.getenv("MEME_FOMO_ENABLED", "1") != "0",
            "closed": len(pnl), "wins": len(wins), "losses": len(losses),
            "win_rate_pct": round(100 * len(wins) / len(pnl), 1) if pnl else None,
            "net_pnl_usd": round(sum(pnl), 2), "expectancy_usd_per_trade": round(sum(pnl) / len(pnl), 2) if pnl else None,
            "avg_win_usd": round(sum(wins) / len(wins), 2) if wins else None,
            "avg_loss_usd": round(sum(losses) / len(losses), 2) if losses else None,
            "max_drawdown_usd": round(dd, 2), "realized_today_usd": round(realized_today(c, now), 2),
            "by_exit_reason": by_exit, "signal_stages": stages,
            "open": [{"token": r[0], "opened_at": r[1], "return_pct": round((_f(r[3]) / _f(r[2]) - 1) * 100, 2) if _f(r[2]) else None,
                      "remaining_pct_of_position": round(100 * _f(r[4]) / _f(r[5]), 1) if _f(r[5]) else None, "tp1_hit": bool(r[6])} for r in open_rows],
            "recent": [{"token": r[0], "net_pnl_usd": round(_f(r[1]), 2), "exit": r[2], "opened_at": r[3], "closed_at": r[4]} for r in closed[-15:]][::-1],
            "rules": {"entry": ENTRY, "exit": EXIT, "notional_usd": NOTIONAL_USD, "max_open": MAX_OPEN,
                      "daily_loss_limit_usd": DAILY_LOSS_LIMIT_USD, "slippage_each_side": SLIP, "fee_each_side": FEE}}


def connect():
    from memecoin_shadow import init_db
    c = init_db(); init(c); return c

if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--once", action="store_true", help="one scan + one exit pass against live data")
    ap.add_argument("--report", action="store_true")
    a = ap.parse_args()
    c = connect()
    try:
        if a.once:
            print({"opened": scan(c), "closed": manage(c)})
        print(json.dumps(summary(c), indent=1))
    finally:
        c.close()
