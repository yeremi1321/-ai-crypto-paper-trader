"""Read-only per-trade analysis of memecoin paper trades. Never writes, never trades.

Answers, from the live database:
  * how far stop exits overshoot -10% and how often losers never went green
  * whether repeat entries (especially right after a stop) lose more than first entries
  * whether liquidity / price behaviour before entry, or liquidity drain during the trade,
    separates winners from losers
  * how often open positions were actually re-priced during each trade (refresh cadence)

Any entry-filter idea is tested with a single threshold chosen on TRAINING tokens
(earliest 70% of tokens by first trade) and then checked on untouched HOLDOUT tokens.
Results are split by rule-change era so pre- and post-fix trades are never blended.
"""
import bisect
from datetime import datetime, timedelta
from statistics import median

# Rule-change boundaries (UTC, ISO). Add a row when a rule change goes live.
ERAS = [
    ("", "A_stacking_before_one_per_token"),
    ("2026-09-26T07:03:47", "B_one_per_token_30s_exits"),
    ("2026-09-26T08:04:10", "C_10s_exits"),
    ("2026-09-26T08:16:48", "D_stop_reclaim_reentry"),
]
PRE_WINDOW = timedelta(minutes=5)
TRAIN_FRACTION = 0.7
FEATURES = ["entry_liquidity_usd", "liq_change_pre_pct", "price_change_pre_pct", "entry_volume_1h_usd", "entry_score"]
TRADE_COLUMNS = ["id", "token", "opened_at", "closed_at", "era", "exit_reason", "net_return_pct", "net_pnl_usd",
                 "mfe_pct", "stop_overshoot_pct", "never_green", "repeat_index", "prev_exit_reason",
                 "secs_since_prev_close", "concurrent_same_token", "entry_liquidity_usd", "liq_change_pre_pct",
                 "price_change_pre_pct", "liq_change_during_pct", "entry_volume_1h_usd", "entry_score",
                 "snapshots_during", "max_gap_s"]


def _pct(a, b):
    return ((b / a) - 1) * 100 if a and b is not None else None


def _ts(s):
    return datetime.fromisoformat(s)


def _era(opened_at):
    name = ERAS[0][1]
    for start, label in ERAS:
        if opened_at >= start:
            name = label
    return name


def _r(x, n=2):
    return None if x is None else round(float(x), n)


def load(conn):
    """Three read-only queries. Works on PostgreSQL and SQLite."""
    trades = conn.execute("""SELECT id,candidate_id,token,token_address,opened_at,closed_at,entry_market_price,
        exit_market_price,exit_reason,net_return_pct,net_pnl_usd,mfe_pct,mae_pct
        FROM meme_paper_trades WHERE status='CLOSED' ORDER BY opened_at,id""").fetchall()
    ledger = conn.execute("""SELECT candidate_id,liquidity_usd,volume_1h_usd,score FROM meme_decision_ledger
        WHERE candidate_id IN (SELECT candidate_id FROM meme_paper_trades)""").fetchall()
    try:
        snaps = conn.execute("""SELECT token_address,observed_at,price,liquidity_usd FROM meme_price_snapshots
            WHERE token_address IN (SELECT DISTINCT token_address FROM meme_paper_trades)
            ORDER BY token_address,observed_at""").fetchall()
    except Exception:
        snaps = []
    return trades, ledger, snaps


def build_rows(trades, ledger, snaps):
    led = {r[0]: r[1:] for r in ledger}
    by_tok = {}
    for tok, at, price, liq in snaps:
        d = by_tok.setdefault(tok, ([], [], []))
        d[0].append(at); d[1].append(price); d[2].append(liq)
    rows = []; history = {}
    for (tid, cid, token, addr, opened, closed, entry_mkt, exit_mkt, reason, net_ret, pnl, mfe, mae) in trades:
        prior = history.setdefault(addr, [])
        prev = prior[-1] if prior else None
        concurrent = sum(1 for p in prior if p["opened_at"] < opened and (p["closed_at"] or "") > opened)
        liq_entry, vol_entry, score_entry = led.get(cid, (None, None, None))
        times, prices, liqs = by_tok.get(addr, ([], [], []))
        o = _ts(opened); c = _ts(closed) if closed else o
        lo = bisect.bisect_left(times, (o - PRE_WINDOW).isoformat())
        hi = bisect.bisect_left(times, opened)
        liq_pre = next((liqs[i] for i in range(lo, hi) if liqs[i]), None)
        price_pre = prices[lo] if lo < hi else None
        d_lo = hi; d_hi = bisect.bisect_right(times, closed) if closed else hi
        during = times[d_lo:d_hi]
        liq_exit = next((liqs[i] for i in range(d_hi - 1, d_lo - 1, -1) if liqs[i]), None)
        stamps = [o] + [_ts(t) for t in during] + [c]
        max_gap = max((b - a).total_seconds() for a, b in zip(stamps, stamps[1:])) if len(stamps) > 1 else None
        raw_ret = _pct(entry_mkt, exit_mkt)
        row = {
            "id": tid, "token": token, "token_address": addr, "opened_at": opened, "closed_at": closed,
            "era": _era(opened), "exit_reason": reason, "net_return_pct": _r(net_ret), "net_pnl_usd": _r(pnl),
            "win": (pnl or 0) > 0, "mfe_pct": _r(mfe),
            "stop_overshoot_pct": _r(-10 - raw_ret) if reason == "STOP_10" and raw_ret is not None else None,
            "never_green": mfe is not None and mfe <= 0,
            "repeat_index": len(prior), "prev_exit_reason": prev["exit_reason"] if prev else None,
            "secs_since_prev_close": _r((o - _ts(prev["closed_at"])).total_seconds(), 0) if prev and prev["closed_at"] else None,
            "concurrent_same_token": concurrent,
            "entry_liquidity_usd": _r(liq_entry, 0), "liq_change_pre_pct": _r(_pct(liq_pre, liq_entry)),
            "price_change_pre_pct": _r(_pct(price_pre, entry_mkt)),
            "liq_change_during_pct": _r(_pct(liq_entry, liq_exit)),
            "entry_volume_1h_usd": _r(vol_entry, 0), "entry_score": _r(score_entry),
            "snapshots_during": len(during), "max_gap_s": _r(max_gap, 1),
        }
        rows.append(row); prior.append(row)
    return rows


def _stats(rows):
    if not rows:
        return {"n": 0}
    rets = [r["net_return_pct"] for r in rows if r["net_return_pct"] is not None]
    wins = sum(r["win"] for r in rows)
    return {"n": len(rows), "wins": wins, "win_rate": _r(100 * wins / len(rows), 1),
            "pnl_usd": _r(sum(r["net_pnl_usd"] or 0 for r in rows)),
            "avg_net_return_pct": _r(sum(rets) / len(rets)) if rets else None,
            "median_net_return_pct": _r(median(rets)) if rets else None,
            "unique_tokens": len({r["token_address"] for r in rows})}


def _dist(values):
    v = sorted(x for x in values if x is not None)
    if not v:
        return None
    return {"n": len(v), "median": _r(median(v)), "p90": _r(v[min(len(v) - 1, int(0.9 * len(v)))]), "max": _r(v[-1])}


def _holdout_test(rows, label):
    firsts = {}
    for r in rows:
        firsts.setdefault(r["token_address"], r["opened_at"])
    ordered = sorted(firsts, key=firsts.get)
    cut = int(len(ordered) * TRAIN_FRACTION)
    train_tok, hold_tok = set(ordered[:cut]), set(ordered[cut:])
    train = [r for r in rows if r["token_address"] in train_tok]
    hold = [r for r in rows if r["token_address"] in hold_tok]
    out = {"sample": label, "train_tokens": len(train_tok), "holdout_tokens": len(hold_tok),
           "train_baseline": _stats(train), "holdout_baseline": _stats(hold), "features": {}}
    for f in FEATURES:
        tv = [r[f] for r in train if r[f] is not None]
        if len(tv) < 6:
            out["features"][f] = {"skipped": f"only {len(tv)} training values"}
            continue
        thr = median(tv)
        split = lambda rs, above: [r for r in rs if r[f] is not None and (r[f] > thr) == above]
        ta, tb = _stats(split(train, True)), _stats(split(train, False))
        better_above = (ta.get("avg_net_return_pct") or -1e9) > (tb.get("avg_net_return_pct") or -1e9)
        ha, hb = _stats(split(hold, True)), _stats(split(hold, False))
        keep = ha if better_above else hb
        out["features"][f] = {
            "threshold_from_train_median": _r(thr, 4),
            "train_above": ta, "train_below": tb,
            "rule_chosen_on_train": f"keep {f} {'>' if better_above else '<='} {_r(thr, 4)}",
            "holdout_above": ha, "holdout_below": hb,
            "holdout_kept_avg_net_return_pct": keep.get("avg_net_return_pct"),
            "holdout_baseline_avg_net_return_pct": out["holdout_baseline"].get("avg_net_return_pct"),
            "holdout_kept_positive": (keep.get("avg_net_return_pct") or -1) > 0,
        }
    return out


def summarize(rows, as_of):
    eras = {}
    for _, name in ERAS:
        er = [r for r in rows if r["era"] == name]
        stops = [r for r in er if r["exit_reason"] == "STOP_10"]
        eras[name] = {
            "all": _stats(er),
            "by_exit_reason": {k: _stats([r for r in er if r["exit_reason"] == k]) for k in sorted({r["exit_reason"] for r in er if r["exit_reason"]})},
            "stop_overshoot_pct": _dist(r["stop_overshoot_pct"] for r in stops),
            "stops_never_green_pct": _r(100 * sum(r["never_green"] for r in stops) / len(stops), 1) if stops else None,
            "stacked_entries": _stats([r for r in er if r["concurrent_same_token"] > 0]),
            "first_entries": _stats([r for r in er if r["repeat_index"] == 0]),
            "repeat_after_stop": _stats([r for r in er if r["prev_exit_reason"] == "STOP_10"]),
            "repeat_after_target": _stats([r for r in er if r["prev_exit_reason"] == "TARGET_20"]),
            "repeat_after_time": _stats([r for r in er if r["prev_exit_reason"] == "TIME_20"]),
            "repeat_after_stop_within_120s": _stats([r for r in er if r["prev_exit_reason"] == "STOP_10" and (r["secs_since_prev_close"] or 1e9) <= 120]),
            "max_gap_between_prices_s": _dist(r["max_gap_s"] for r in er),
            "liq_change_during_pct": {"winners": _dist(r["liq_change_during_pct"] for r in er if r["win"]),
                                      "losers": _dist(r["liq_change_during_pct"] for r in er if not r["win"])},
        }
    medians = {f: {"winners": _dist(r[f] for r in rows if r["win"]), "losers": _dist(r[f] for r in rows if not r["win"])} for f in FEATURES}
    first_only = []
    seen = set()
    for r in rows:
        if r["token_address"] not in seen:
            seen.add(r["token_address"]); first_only.append(r)
    return {"as_of": as_of, "mode": "read_only_paper_analysis", "total": _stats(rows), "eras": eras,
            "entry_features_winners_vs_losers": medians,
            "holdout_first_trade_per_token": _holdout_test(first_only, "first trade per token (independent)"),
            "holdout_all_trades_token_split": _holdout_test(rows, "all trades, token-disjoint split (repeats not independent)"),
            "notes": ["Paper fills are sampled quotes, not executable fills.",
                      "Pre-entry features need snapshots; tokens only get snapshots while they are recent candidates or open.",
                      "A feature is only worth promoting if the train-chosen rule is also better on holdout AND positive after costs."]}


def trades_table(rows):
    return {"columns": TRADE_COLUMNS, "rows": [[r[c] for c in TRADE_COLUMNS] for r in rows]}


def run(conn, as_of):
    rows = build_rows(*load(conn))
    return summarize(rows, as_of), trades_table(rows)
