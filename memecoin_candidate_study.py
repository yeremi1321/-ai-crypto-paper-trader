"""Read-only study of EVERY discovered memecoin, not just the ones the bot traded. Never writes, never trades.

Question: if the bot had bought each token the first time it was discovered, using the live paper
rules (+20% target, -10% stop, 20-minute max hold, 1% slippage and 0.6% fee each side, sampled
quotes), what would have happened? From that:

  * GATE AUDIT - for each safety gate and the score threshold, how did blocked tokens do compared
    with tokens that passed? (Are the gates protecting the bot, or filtering out winners?)
  * FEATURE TEST - for each numeric field recorded at discovery, pick one threshold on TRAINING
    tokens (earliest 70% by first discovery), then judge it on untouched HOLDOUT tokens with a
    token bootstrap. Nothing is promoted automatically.

One observation per token (its first discovery) so every row is independent.
"""
import bisect
import json
import random
from datetime import datetime, timedelta
from statistics import mean, median

FEE = 0.006
SLIP = 0.01
TP, SL, HORIZON_S = 20.0, 10.0, 20 * 60
END_TOLERANCE_S = 60
TRAIN_FRACTION = 0.7
BOOTSTRAP_SAMPLES = 1000
MIN_FEATURE_COVERAGE = 0.5
SKIP_FIELDS = {"price_usd", "token", "token_address", "pair_address", "chain", "dex", "url"}


def _pct(a, b):
    return ((b / a) - 1) * 100 if a else None


def _r(x, n=2):
    return None if x is None else round(float(x), n)


NOTIONAL = 100.0
REALISTIC_MIN_LIQ = 20000.0
FORWARD_START = "2026-09-26T09:29:00"   # data after this was never used to form any hypothesis
REGIME_FIELD = "sol_ret_60m_pct"


def impact(liquidity_usd):
    """Approximate constant-product price impact of a $100 order: ~2*order/pool liquidity, capped at 50%."""
    if not liquidity_usd or liquidity_usd <= 0:
        return 0.5
    return min(0.5, 2 * NOTIONAL / float(liquidity_usd))


def net_return_pct(entry_price, exit_market, exit_slip=SLIP):
    qty = 100 * (1 - FEE) / entry_price
    return qty * exit_market * (1 - exit_slip) * (1 - FEE) - 100


def simulate_live(entry_price, path, exit_slip=None):
    """Live paper rule on a sampled path [(secs, price[, liquidity])]. exit_slip(liq) -> slippage fraction;
    default is the flat live 1%. Returns (reason, net_return_pct, max_up_pct) or None."""
    max_up = 0.0
    slip = (lambda liq: SLIP) if exit_slip is None else exit_slip
    for step in path:
        t, p = step[0], step[1]
        liq = step[2] if len(step) > 2 else None
        nr = lambda px: net_return_pct(entry_price, px, slip(liq))
        if t > HORIZON_S + END_TOLERANCE_S:
            break
        ret = _pct(entry_price, p)
        max_up = max(max_up, ret)
        if ret <= -SL:
            return "STOP", nr(p), max_up
        if ret >= TP:
            return "TARGET", nr(p), max_up
        if t >= HORIZON_S:
            return "TIME", nr(p), max_up
    if path and path[-1][0] >= HORIZON_S - END_TOLERANCE_S:
        last = path[-1]
        return "TIME", net_return_pct(entry_price, last[1], slip(last[2] if len(last) > 2 else None)), max_up
    return None


def load(conn):
    """First discovery per token, plus price snapshots for those tokens. Three read-only queries."""
    firsts = conn.execute("""SELECT id,seen_at,token_address,score,eligible,blocked_reasons,raw_json FROM meme_candidates
        WHERE id IN (SELECT MIN(id) FROM meme_candidates WHERE token_address IS NOT NULL GROUP BY token_address)
        ORDER BY seen_at""").fetchall()
    try:
        snaps = conn.execute("""SELECT token_address,observed_at,price,liquidity_usd FROM meme_price_snapshots
            ORDER BY token_address,observed_at""").fetchall()
    except Exception:
        snaps = []
    traded = {r[0] for r in conn.execute("SELECT DISTINCT token_address FROM meme_paper_trades") if r[0]}
    return firsts, snaps, traded


def build_rows(firsts, snaps, traded, liquidity_aware=False):
    by_tok = {}
    for tok, at, price, liq in snaps:
        d = by_tok.setdefault(tok, ([], [], []))
        d[0].append(at); d[1].append(float(price)); d[2].append(liq)
    rows = []; incomplete = no_price = 0
    for cid, seen, addr, score, eligible, blocked, raw in firsts:
        try:
            x = json.loads(raw) if raw else {}
        except Exception:
            x = {}
        price = x.get("price_usd")
        if not price:
            no_price += 1; continue
        entry_liq = x.get("liquidity_usd")
        entry = float(price) * (1 + SLIP + (impact(entry_liq) if liquidity_aware else 0))
        times, prices, liqs = by_tok.get(addr, ([], [], []))
        s = datetime.fromisoformat(seen)
        lo = bisect.bisect_right(times, seen)
        hi = bisect.bisect_right(times, (s + timedelta(seconds=HORIZON_S + END_TOLERANCE_S)).isoformat())
        path = [((datetime.fromisoformat(times[i]) - s).total_seconds(), prices[i], liqs[i] or entry_liq) for i in range(lo, hi)]
        sim = simulate_live(entry, path, (lambda liq: SLIP + impact(liq)) if liquidity_aware else None)
        if sim is None:
            incomplete += 1; continue
        reason, net, max_up = sim
        try:
            reasons = json.loads(blocked) if blocked else []
        except Exception:
            reasons = []
        feats = {k: float(v) for k, v in x.items()
                 if k not in SKIP_FIELDS and isinstance(v, (int, float)) and not isinstance(v, bool)}
        feats["score"] = float(score) if score is not None else None
        rows.append({"token_address": addr, "seen_at": seen, "entry_liquidity_usd": entry_liq, "eligible": bool(eligible), "blocked": reasons,
                     "traded": addr in traded, "reason": reason, "net": net, "max_up": max_up, "feats": feats})
    return rows, incomplete, no_price


def _stats(rows):
    if not rows:
        return {"n": 0}
    nets = [r["net"] for r in rows]
    return {"n": len(rows), "win_rate": _r(100 * sum(n > 0 for n in nets) / len(nets), 1),
            "avg_net_return_pct": _r(mean(nets)), "median_net_return_pct": _r(median(nets)),
            "reached_plus20_pct": _r(100 * sum(r["max_up"] >= TP for r in rows) / len(rows), 1)}


def gate_audit(rows):
    reasons = sorted({b for r in rows for b in r["blocked"]})
    out = {"all_tokens": _stats(rows), "passed_all_gates_and_score": _stats([r for r in rows if r["eligible"]]),
           "passed_gates_but_score_below_threshold": _stats([r for r in rows if not r["blocked"] and not r["eligible"]]),
           "blocked_by_any_gate": _stats([r for r in rows if r["blocked"]]),
           "tokens_the_bot_actually_traded": _stats([r for r in rows if r["traded"]]), "by_gate": {}}
    for g in reasons:
        out["by_gate"][g] = {"blocked": _stats([r for r in rows if g in r["blocked"]]),
                             "blocked_only_by_this_gate": _stats([r for r in rows if r["blocked"] == [g]])}
    return out


def _bootstrap(hold, keep, rng):
    by_tok = {}
    for r in hold:
        by_tok.setdefault(r["token_address"], []).append(r)
    toks = list(by_tok)
    if not toks:
        return None, None
    beats = positive = 0
    for _ in range(BOOTSTRAP_SAMPLES):
        sample = [r for t in (rng.choice(toks) for _ in toks) for r in by_tok[t]]
        kept = [r["net"] for r in sample if keep(r)]
        base = mean(r["net"] for r in sample)
        k = mean(kept) if kept else base
        beats += k > base; positive += k > 0
    return _r(100 * beats / BOOTSTRAP_SAMPLES, 1), _r(100 * positive / BOOTSTRAP_SAMPLES, 1)


def feature_test(rows, seed=11, prefix=None):
    ordered = sorted(rows, key=lambda r: r["seen_at"])
    cut = int(len(ordered) * TRAIN_FRACTION)
    train, hold = ordered[:cut], ordered[cut:]
    names = sorted({k for r in rows for k in r["feats"] if prefix is None or k.startswith(prefix)})
    rng = random.Random(seed)
    out = {"train_tokens": len(train), "holdout_tokens": len(hold),
           "train_baseline": _stats(train), "holdout_baseline": _stats(hold), "features": {}, "candidates": []}
    for f in names:
        tv = [r["feats"][f] for r in train if r["feats"].get(f) is not None]
        if len(tv) < max(10, MIN_FEATURE_COVERAGE * len(train)):
            continue
        thr = median(tv)
        # Ties at the median can empty one side (e.g. most scores are exactly 70); fall back to >= / <.
        strict = any(v > thr for v in tv)
        above = (lambda r: r["feats"].get(f) is not None and r["feats"][f] > thr) if strict else \
                (lambda r: r["feats"].get(f) is not None and r["feats"][f] >= thr)
        below = (lambda r: r["feats"].get(f) is not None and r["feats"][f] <= thr) if strict else \
                (lambda r: r["feats"].get(f) is not None and r["feats"][f] < thr)
        ta, tb = _stats([r for r in train if above(r)]), _stats([r for r in train if below(r)])
        if not ta.get("n") or not tb.get("n"):
            continue
        keep = above if (ta["avg_net_return_pct"] > tb["avg_net_return_pct"]) else below
        side = (">" if strict else ">=") if keep is above else ("<=" if strict else "<")
        hk = _stats([r for r in hold if keep(r)])
        beats, positive = _bootstrap(hold, keep, rng)
        res = {"rule_chosen_on_train": f"keep {f} {side} {_r(thr, 6)}",
               "train_kept": ta if keep is above else tb, "holdout_kept": hk,
               "holdout_bootstrap_pct_beats_baseline": beats, "holdout_bootstrap_pct_positive": positive}
        out["features"][f] = res
        if hk.get("n") and (hk["avg_net_return_pct"] or -1) > 0 and (positive or 0) >= 90:
            out["candidates"].append(res["rule_chosen_on_train"])
    return out


def _forward(real):
    """Out-of-sample sections: only tokens first discovered after FORWARD_START, realistic costs."""
    fwd = [r for r in real if r["seen_at"] >= FORWARD_START]
    fwd_big = [r for r in fwd if (r["entry_liquidity_usd"] or 0) >= REALISTIC_MIN_LIQ]
    reg = [r for r in fwd_big if r["feats"].get(REGIME_FIELD) is not None]

    def by_regime(rows):
        out = {}
        for r in rows:
            v = r["feats"][REGIME_FIELD]
            out.setdefault("SOL_UP" if v > 0.5 else "SOL_DOWN" if v < -0.5 else "SOL_FLAT", []).append(r)
        return {k: _stats(v) for k, v in sorted(out.items())}

    attn = [r for r in fwd_big if r["feats"].get("attn_tx_accel_5m") is not None]
    older_pairs = [r for r in fwd_big if r["feats"].get("pair_created_at") is not None]
    cut = median([r["feats"]["pair_created_at"] for r in older_pairs]) if older_pairs else None
    return {"since": FORWARD_START, "cost_model": "liquidity-aware, pools >= $20k",
            "all_tokens": _stats(fwd), "realistic_pools": _stats(fwd_big),
            "pair_age_hypothesis": {"note": "pre-registered 09:29 UTC: older pairs do better",
                                    "older_half": _stats([r for r in older_pairs if r["feats"]["pair_created_at"] <= cut]) if cut else {"n": 0},
                                    "newer_half": _stats([r for r in older_pairs if r["feats"]["pair_created_at"] > cut]) if cut else {"n": 0}},
            "sol_regime": {"tokens_with_regime": len(reg), "by_sol_60m_trend": by_regime(reg),
                           "feature_test": feature_test(reg, prefix="sol_") if len(reg) >= 20 else {"skipped": f"only {len(reg)} tokens so far"}},
            "attention": {"tokens_with_attention": len(attn),
                          "note": "about 10 attention fields are tested at once; expect ~1 false 'candidate' by chance, so any hit needs a second forward confirmation",
                          "feature_test": feature_test(attn, prefix="attn_") if len(attn) >= 20 else {"skipped": f"only {len(attn)} tokens so far"}}}


def run(conn, as_of):
    firsts, snaps, traded = load(conn)
    rows, incomplete, no_price = build_rows(firsts, snaps, traded)
    real, _, _ = build_rows(firsts, snaps, traded, liquidity_aware=True)
    liqs = sorted(r["entry_liquidity_usd"] for r in rows if r["entry_liquidity_usd"] is not None)
    big = [r for r in real if (r["entry_liquidity_usd"] or 0) >= REALISTIC_MIN_LIQ]
    return {"as_of": as_of, "mode": "read_only_candidate_study",
            "tokens_discovered": len(firsts), "tokens_studied": len(rows),
            "excluded_incomplete_price_path": incomplete, "excluded_no_price": no_price,
            "entry_liquidity_usd": {"median": _r(median(liqs), 0) if liqs else None,
                                    "pct_below_1k": _r(100 * sum(l < 1000 for l in liqs) / len(liqs), 1) if liqs else None,
                                    "pct_at_least_20k": _r(100 * sum(l >= REALISTIC_MIN_LIQ for l in liqs) / len(liqs), 1) if liqs else None},
            "gate_audit": gate_audit(rows), "feature_test": feature_test(rows),
            "liquidity_aware": {"cost_model": "1% slippage + ~2x$100/pool-liquidity price impact per side (cap 50%)",
                                "gate_audit": gate_audit(real), "feature_test": feature_test(real)},
            "realistic_pools_only": {"min_entry_liquidity_usd": REALISTIC_MIN_LIQ, "all": _stats(big),
                                     "feature_test": feature_test(big)},
            "forward_test": _forward(real),
            "notes": ["Hypothetical entry at each token's FIRST discovery with the live +20/-10/20min rule and live costs.",
                      "Sampled quotes (~30s); real fills on thin pools would likely be worse.",
                      "A feature appears under 'candidates' only if its train-chosen rule is profitable on holdout "
                      "in >=90% of token bootstrap samples. Even then: paper trial only."]}
