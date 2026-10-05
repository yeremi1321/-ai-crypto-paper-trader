"""Read-only replay of fixed exit rules over sampled paper-trade prices.

Select on the earliest 70% of tokens, then evaluate on disjoint holdout tokens.
All fills use the live paper costs, but sampled quotes cannot model intragap fills.
"""
import bisect
import random
from datetime import datetime, timedelta
from statistics import mean, median

from memecoin_entry_analysis import load
from memecoin_shadow import PAPER_FEE_RATE, PAPER_SLIPPAGE_RATE

FEE = PAPER_FEE_RATE
SLIP = PAPER_SLIPPAGE_RATE
HORIZON_S = 20 * 60
END_TOLERANCE_S = 60
TRAIN_FRACTION = 0.7
BOOTSTRAP_SAMPLES = 1000
BASELINE = "live_tp20_sl10"
MAX_DIAGNOSTIC_GAP_S = 60  # gap/slide is only meaningful with quotes this close together


def _rule(name, tp=20.0, sl=10.0, trail_after=None, trail_drop=None, breakeven_after=None,
          early_sl=None, early_window=None, tick_drop=None, confirm_stop=False):
    return {"name": name, "tp": tp, "sl": sl, "trail_after": trail_after,
            "trail_drop": trail_drop, "breakeven_after": breakeven_after,
            "early_sl": early_sl, "early_window": early_window, "tick_drop": tick_drop,
            "confirm_stop": confirm_stop}


RULES = [_rule(BASELINE)]
RULES += [_rule(f"tp{t}_sl10", tp=t) for t in (5, 8, 10, 15, 30)]
RULES += [_rule(f"tp20_sl10_trail{a}_{d}", trail_after=a, trail_drop=d)
          for a, d in ((5, 3), (8, 3), (10, 3), (10, 5), (15, 5), (20, 8))]
RULES += [_rule(f"notp_sl10_trail{a}_{d}", tp=None, trail_after=a, trail_drop=d)
          for a, d in ((5, 3), (8, 3), (10, 3), (10, 5), (15, 5))]
RULES += [_rule(f"tp20_sl10_breakeven{b}", breakeven_after=b) for b in (5, 10)]
RULES += [_rule("tp20_sl5", sl=5.0)]
# Faster loss exits (2026-09-30): stops averaged about -24% net against a -10% stop, and severe losses (-20% or worse)
# erased the winners. EARLY: a tighter stop only in the first seconds after entry, when failed entries dump.
# TICKDROP: leave as soon as one quote-to-quote fall reaches d%, before a falling token reaches the stop.
RULES += [_rule(f"tp20_sl10_early{x}_{w}s", early_sl=x, early_window=w) for x, w in ((5, 60), (6, 60), (6, 120), (8, 120))]
RULES += [_rule(f"tp20_sl10_tickdrop{d}", tick_drop=d) for d in (5, 8)]
# CONFIRM: the stop needs two quotes in a row at or below -10%, so one bad quote cannot stop a trade out
# (tests upgrade #6; costs one extra quote of delay on real crashes).
RULES += [_rule("tp20_sl10_confirm2", confirm_stop=True)]


# Pre-registered blind forward tests of exit rules, judged only on trades opened after registration, once, at a fixed
# trade count. Never edit one after registration; add a new one instead. Nothing here changes live trading.
FORWARD_TESTS = [
    {"name": "tighter_stop_sl5_fixed_150",
     "registered_at": "2026-10-01T23:00:00+00:00",
     "motivation": "exit replay 2026-10-01 22:05Z (154 trades): tp20_sl5 was chosen on training tokens and beat the "
                   "live rule on holdout (+2.92% vs +2.09%/trade) but was not reliably profitable; 63 of 84 stops were "
                   "gaps no exit can catch.",
     "statement": "On the first 150 paper trades opened after registration, a -5% stop (target unchanged) gives a "
                  "higher average net return than the live -10% stop on the same sampled price paths.",
     "rule": "tp20_sl5", "decide_at_trades": 150,
     # Frozen once decided, so later snapshot retention cannot change it.
     "recorded_verdict": "REJECTED: the rule does not beat the live exit (decided 2026-10-03: -5% stop -2.76%/trade vs "
                         "live -2.15% over 150 trades; beat live in 28.2% of bootstrap samples)"},
    {"name": "delayed_entry_120s_hold3_fixed_150",
     "kind": "delayed_entry",
     "registered_at": "2026-10-05T06:00:00+00:00",
     "motivation": "2026-10-05: three tokens rugged -98% within 2-4 minutes of entry and five more fell 40-53% as fast "
                   "(-$883 in 12 hours). Skipping losers did not work by predicted risk, so test waiting instead.",
     "statement": "Waiting 120 seconds after the bot's entry signal and buying only if the price is no more than 3% "
                  "below the original entry (otherwise skipping, counted as 0) gives a higher average net return per "
                  "opportunity than entering immediately, both with the live exit rule on the same sampled prices.",
     "delay_s": 120, "max_wait_s": 60, "max_drop_pct": 3.0, "decide_at_trades": 150},
]


def delayed_outcome(tr, quotes, h):
    """Net return of waiting h['delay_s'] then entering only if the price held, or None while data is incomplete.

    quotes: [(seconds after the original entry, market price)] for the trade's token."""
    window = [(t, p) for t, p in quotes if h["delay_s"] <= t <= h["delay_s"] + h["max_wait_s"]]
    if not window:
        return None
    t0, p0 = window[0]
    entry_mkt = tr["entry_price"] / (1 + SLIP)
    if _pct(entry_mkt, p0) < -h["max_drop_pct"]:
        return 0.0  # price did not hold: skipped, no trade
    entry = p0 * (1 + SLIP)
    sub = [(t - t0, p) for t, p in quotes if t > t0 and t - t0 <= HORIZON_S + END_TOLERANCE_S]
    sim = simulate(entry, sub, RULES[0])
    return None if sim is None else net_return_pct(entry, sim[1])


def forward_tests(paths, results, seed=13, snaps=()):
    out = []
    by_tok = {}
    for tok, at, price, _liq in snaps:
        by_tok.setdefault(tok, []).append((at, float(price)))
    for h in FORWARD_TESTS:
        if h.get("recorded_verdict"):
            out.append({**h, "verdict": h["recorded_verdict"]})
            continue
        if h.get("kind") == "delayed_entry":
            out.append(_delayed_entry_test(h, paths, results, by_tok, seed))
            continue
        trades = sorted((tr for tr in paths if tr["opened_at"] >= h["registered_at"] and tr["id"] in results),
                        key=lambda tr: (tr["opened_at"], tr["id"]))
        n = h["decide_at_trades"]
        if len(trades) < n:
            out.append({**h, "trades_so_far": len(trades),
                        "verdict": f"blind: decided once at {n} trades (have {len(trades)}); interim results hidden"})
            continue
        trades = trades[:n]
        rule = [results[tr["id"]][h["rule"]][1] for tr in trades]
        live = [results[tr["id"]][BASELINE][1] for tr in trades]
        rng = random.Random(seed)
        beats = positive = 0
        for _ in range(BOOTSTRAP_SAMPLES):
            idx = [rng.randrange(n) for _ in range(n)]
            beats += sum(rule[i] for i in idx) > sum(live[i] for i in idx)
            positive += sum(rule[i] for i in idx) > 0
        pct = _r(100 * beats / BOOTSTRAP_SAMPLES, 1)
        if mean(rule) <= mean(live):
            verdict = "REJECTED: the rule does not beat the live exit"
        elif pct >= 90:
            verdict = "SUPPORTED: beats the live exit in >=90% of bootstrap samples -> eligible for a paper trial (needs owner OK)"
        else:
            verdict = "NOT SUPPORTED: ahead but not reliably"
        out.append({**h, "rule_result": _stats(rule), "live_result": _stats(live), "bootstrap_pct_beats_live": pct,
                    "bootstrap_pct_rule_positive": _r(100 * positive / BOOTSTRAP_SAMPLES, 1), "verdict": verdict})
    return out


def _delayed_entry_test(h, paths, results, by_tok, seed):
    rows = []
    for tr in sorted((t for t in paths if t["opened_at"] >= h["registered_at"] and t["id"] in results),
                     key=lambda t: (t["opened_at"], t["id"])):
        o = datetime.fromisoformat(tr["opened_at"])
        quotes = [((datetime.fromisoformat(at) - o).total_seconds(), p) for at, p in by_tok.get(tr["token_address"], ())
                  if at > tr["opened_at"]]
        d = delayed_outcome(tr, quotes, h)
        if d is not None:
            rows.append((d, results[tr["id"]][BASELINE][1]))
    n = h["decide_at_trades"]
    if len(rows) < n:
        return {**h, "trades_so_far": len(rows),
                "verdict": f"blind: decided once at {n} trades (have {len(rows)}); interim results hidden"}
    rows = rows[:n]
    rule, live = [r[0] for r in rows], [r[1] for r in rows]
    rng = random.Random(seed)
    beats = positive = 0
    for _ in range(BOOTSTRAP_SAMPLES):
        idx = [rng.randrange(n) for _ in range(n)]
        beats += sum(rule[i] for i in idx) > sum(live[i] for i in idx)
        positive += sum(rule[i] for i in idx) > 0
    pct = _r(100 * beats / BOOTSTRAP_SAMPLES, 1)
    if mean(rule) <= mean(live):
        verdict = "REJECTED: waiting does not beat entering immediately"
    elif pct >= 90:
        verdict = "SUPPORTED: beats immediate entry in >=90% of bootstrap samples -> eligible for a paper trial (needs owner OK)"
    else:
        verdict = "NOT SUPPORTED: ahead but not reliably"
    return {**h, "rule_result": _stats(rule), "live_result": _stats(live), "skipped": sum(r == 0.0 for r in rule),
            "bootstrap_pct_beats_live": pct, "bootstrap_pct_rule_positive": _r(100 * positive / BOOTSTRAP_SAMPLES, 1),
            "verdict": verdict}


def _pct(a, b):
    return ((b / a) - 1) * 100 if a else None


def _r(x, n=2):
    return None if x is None else round(float(x), n)


def net_return_pct(entry_price, exit_market):
    """Net percent on a $100 position after entry fee, exit slippage and exit fee."""
    qty = 100 * (1 - FEE) / entry_price
    return qty * exit_market * (1 - SLIP) * (1 - FEE) - 100


def simulate(entry_price, path, rule):
    """Return (exit reason, sampled market price, age in seconds), or None."""
    peak = entry_price / (1 + SLIP)
    trail_armed = be_armed = False
    prev = None
    below = False
    for t, p in path:
        if t > HORIZON_S + END_TOLERANCE_S:
            break
        ret = _pct(entry_price, p)
        peak = max(peak, p)
        peak_ret = _pct(entry_price, peak)
        if ret <= -rule["sl"]:
            if not rule.get("confirm_stop") or below:
                return "STOP", p, t
            below = (t, p)
        else:
            below = False
        if rule.get("early_sl") is not None and t <= rule["early_window"] and ret <= -rule["early_sl"]:
            return "EARLY_STOP", p, t
        if rule.get("tick_drop") is not None and prev and _pct(prev, p) <= -rule["tick_drop"]:
            return "TICK_DROP", p, t
        prev = p
        if rule["tp"] is not None and ret >= rule["tp"]:
            return "TARGET", p, t
        if rule["trail_after"] is not None:
            trail_armed = trail_armed or peak_ret >= rule["trail_after"]
            if trail_armed and _pct(peak, p) <= -rule["trail_drop"]:
                return "TRAIL", p, t
        if rule["breakeven_after"] is not None:
            be_armed = be_armed or peak_ret >= rule["breakeven_after"]
            if be_armed and ret <= 2.0:
                return "BREAKEVEN", p, t
        if t >= HORIZON_S:
            return "TIME", p, t
    if below and below == path[-1]:  # no quote left to confirm with: stop conservatively
        return "STOP", below[1], below[0]
    if path and path[-1][0] >= HORIZON_S - END_TOLERANCE_S:
        return "TIME", path[-1][1], path[-1][0]
    return None


def build_paths(trades, snaps):
    by_tok = {}
    for tok, at, price, _liq in snaps:
        d = by_tok.setdefault(tok, ([], []))
        d[0].append(at)
        d[1].append(float(price))
    out = []
    for tid, _cid, token, addr, opened, closed, entry_mkt, exit_mkt, reason, net_ret, pnl, mfe, mae in trades:
        if not entry_mkt:
            continue
        times, prices = by_tok.get(addr, ([], []))
        o = datetime.fromisoformat(opened)
        lo = bisect.bisect_right(times, opened)
        hi = bisect.bisect_right(times, (o + timedelta(seconds=HORIZON_S + END_TOLERANCE_S)).isoformat())
        path = [((datetime.fromisoformat(times[i]) - o).total_seconds(), prices[i]) for i in range(lo, hi)]
        out.append({"id": tid, "token": token, "token_address": addr, "opened_at": opened,
                    "entry_price": float(entry_mkt) * (1 + SLIP), "actual_reason": reason,
                    "actual_net_return_pct": net_ret, "path": path})
    return out


def _stats(values):
    if not values:
        return {"n": 0}
    wins = sum(v > 0 for v in values)
    return {"n": len(values), "win_rate": _r(100 * wins / len(values), 1),
            "avg_net_return_pct": _r(mean(values)), "median_net_return_pct": _r(median(values)),
            "pnl_usd": _r(sum(values))}


def replay(paths):
    """Use the same complete trade sample for every rule."""
    results = {}
    excluded = 0
    for tr in paths:
        per_rule = {}
        for rule in RULES:
            sim = simulate(tr["entry_price"], tr["path"], rule)
            if sim is None:
                break
            reason, px, secs = sim
            per_rule[rule["name"]] = (reason, net_return_pct(tr["entry_price"], px), secs)
        if len(per_rule) != len(RULES):
            excluded += 1
            continue
        results[tr["id"]] = per_rule
    return results, excluded


def stop_gaps(paths, gap_from=-5.0):
    """Were the live rule's stops gaps or slides? A stop is a GAP when the quote before it was still above
    gap_from% (no exit rule can react between the two quotes); otherwise it SLID and a faster exit could act."""
    rows = []
    for tr in paths:
        sim = simulate(tr["entry_price"], tr["path"], RULES[0])
        if not sim or sim[0] != "STOP":
            continue
        before = [(t, p) for t, p in tr["path"] if t < sim[2]]
        prev_ret = _pct(tr["entry_price"], before[-1][1]) if before else 0.0
        rows.append({"net": net_return_pct(tr["entry_price"], sim[1]), "prev_ret": prev_ret,
                     "gap_s": sim[2] - (before[-1][0] if before else 0.0)})
    gap = [r for r in rows if r["prev_ret"] > gap_from]
    slide = [r for r in rows if r["prev_ret"] <= gap_from]
    dense = rows and median(r["gap_s"] for r in rows) <= MAX_DIAGNOSTIC_GAP_S
    reading = ("no stops" if not rows else
               f"prices too sparse to tell (median {median(r['gap_s'] for r in rows):.0f}s between quotes; "
               f"needs <= {MAX_DIAGNOSTIC_GAP_S}s)" if not dense else
               "mostly gaps: faster exits cannot help much; avoid the entries instead" if len(gap) > len(slide) else
               "mostly slides: faster exits can cut these losses")
    side = lambda rs: {"n": len(rs), "avg_net_return_pct": _r(mean(r["net"] for r in rs)) if rs else None,
                       "median_seconds_since_prior_quote": _r(median(r["gap_s"] for r in rs), 1) if rs else None}
    return {"stops": len(rows), "avg_stop_net_return_pct": _r(mean(r["net"] for r in rows)) if rows else None,
            "severe_stops_pct": _r(100 * sum(r["net"] <= -20 for r in rows) / len(rows), 1) if rows else None,
            "gap_stops": side(gap), "sliding_stops": side(slide),
            "reading": reading}


def validate(paths, results):
    """Compare the replayed live rule with observed paper exit reasons and returns."""
    live_map = {"STOP_10": "STOP", "TARGET_20": "TARGET", "TIME_20": "TIME"}
    same = n = 0
    abs_err = []
    for tr in paths:
        r = results.get(tr["id"])
        if not r or tr["actual_net_return_pct"] is None:
            continue
        reason, net, _ = r[BASELINE]
        n += 1
        same += live_map.get(tr["actual_reason"]) == reason
        abs_err.append(abs(net - tr["actual_net_return_pct"]))
    return {"trades_compared": n, "same_exit_reason_pct": _r(100 * same / n, 1) if n else None,
            "median_abs_net_return_error_pct": _r(median(abs_err)) if abs_err else None,
            "p90_abs_net_return_error_pct": _r(sorted(abs_err)[min(len(abs_err) - 1, int(.9 * len(abs_err)))]) if abs_err else None}


def _split(paths):
    firsts = {}
    for tr in paths:
        firsts.setdefault(tr["token_address"], tr["opened_at"])
    ordered = sorted(firsts, key=firsts.get)
    cut = int(len(ordered) * TRAIN_FRACTION)
    return set(ordered[:cut]), set(ordered[cut:])


def _verdict(ch, live, beats, positive, done):
    if not ch.get("n") or not done:
        return "insufficient holdout data"
    better = ch["avg_net_return_pct"] > live["avg_net_return_pct"]
    if better and ch["avg_net_return_pct"] > 0 and positive / done >= .9:
        return "candidate: better than live AND positive on holdout in >=90% of bootstrap samples"
    if better and beats / done >= .9:
        return "improves on the live rule on holdout, but still not reliably profitable"
    return "not promotable: does not reliably beat the live rule on holdout"


def evaluate(paths, results, label, seed=7):
    train_tok, hold_tok = _split(paths)
    usable = [tr for tr in paths if tr["id"] in results]
    train = [tr for tr in usable if tr["token_address"] in train_tok]
    hold = [tr for tr in usable if tr["token_address"] in hold_tok]
    table = {}
    for rule in RULES:
        name = rule["name"]
        table[name] = {"train": _stats([results[t["id"]][name][1] for t in train]),
                       "holdout": _stats([results[t["id"]][name][1] for t in hold])}
    ranked = sorted(RULES, key=lambda r: table[r["name"]]["train"].get("avg_net_return_pct", float("-inf")), reverse=True)
    chosen = ranked[0]["name"]
    rng = random.Random(seed)
    by_tok = {}
    for t in hold:
        by_tok.setdefault(t["token_address"], []).append(t)
    toks = list(by_tok)
    beats = positive = done = 0
    if toks:
        for _ in range(BOOTSTRAP_SAMPLES):
            sample = [t for tok in (rng.choice(toks) for _ in toks) for t in by_tok[tok]]
            c = mean(results[t["id"]][chosen][1] for t in sample)
            b = mean(results[t["id"]][BASELINE][1] for t in sample)
            beats += c > b
            positive += c > 0
            done += 1
    return {"sample": label, "train_tokens": len(train_tok), "holdout_tokens": len(hold_tok),
            "train_trades": len(train), "holdout_trades": len(hold),
            "chosen_on_train": chosen, "top3_on_train": [r["name"] for r in ranked[:3]],
            "chosen": table[chosen], "live_rule": table[BASELINE],
            "holdout_bootstrap": {"samples": done,
                                  "pct_chosen_beats_live": _r(100 * beats / done, 1) if done else None,
                                  "pct_chosen_positive": _r(100 * positive / done, 1) if done else None},
            "verdict": _verdict(table[chosen]["holdout"], table[BASELINE]["holdout"], beats, positive, done),
            "all_rules": table}


def run(conn, as_of):
    trades, _ledger, snaps = load(conn)
    paths = build_paths(trades, snaps)
    results, excluded = replay(paths)
    first = []
    seen = set()
    for tr in paths:
        if tr["token_address"] not in seen:
            seen.add(tr["token_address"])
            first.append(tr)
    gaps = [b[0] - a[0] for tr in paths for a, b in zip(tr["path"], tr["path"][1:])]
    return {"as_of": as_of, "mode": "read_only_exit_replay",
            "trades_total": len(paths), "trades_replayed": len(results), "trades_excluded_incomplete": excluded,
            "median_seconds_between_prices": _r(median(gaps), 1) if gaps else None,
            "harness_validation_live_rule": validate(paths, results),
            "stop_gap_diagnostic": stop_gaps(paths),
            "forward_tests": forward_tests(paths, results, snaps=snaps),
            "rules": [r["name"] for r in RULES],
            "all_trades_token_split": evaluate(paths, results, "all trades, token-disjoint split"),
            "first_trade_per_token": evaluate(first, results, "first trade per token (independent)"),
            "notes": ["Fills are sampled quotes: a rule that exits between samples fills at the next quote.",
                      "Tighter stops look better in sampled data than they would in live gaps; treat them cautiously.",
                      "Only a rule marked 'candidate' on holdout should be considered for a paper-only trial."]}
