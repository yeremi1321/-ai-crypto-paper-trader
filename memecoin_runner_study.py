"""Read-only study of 'runners': tokens that kept rising while the paper bot was stopped out on them. Never trades.

Motivated by 2026-09-27 (jizz: price up ~3.4x in an hour, five -10% stops then one +20% target, net -$54).
Three questions, judged with the same discipline as the other studies (choose on the earliest 70% of tokens,
judge on the untouched rest with a token bootstrap):

  * CENSUS - how often does the bot lose money on a token whose price ran up >= 50% while it traded it?
  * WIDER STOPS - replay each trade's sampled price path under wider stop / target pairs.
  * RE-ENTRY POLICY - drop the trades a stricter re-entry policy would have skipped.

Only trades from the one-position-per-token eras are used (stacked-era trades are not independent).
A 'candidate' here is only eligible to be pre-registered and tested forward; nothing is promoted.
"""
import bisect
import random
from datetime import datetime

from memecoin_entry_analysis import ERAS, _era, load
from memecoin_exit_replay import (BASELINE, BOOTSTRAP_SAMPLES, TRAIN_FRACTION, _r, _rule, _stats, build_paths,
                                  net_return_pct, simulate)

ONE_PER_TOKEN_ERAS = {name for _, name in ERAS[1:]}
RUN_THRESHOLD_PCT = 50.0

EXIT_RULES = [_rule(BASELINE)] + [_rule(f"tp{tp}_sl10", tp=tp) for tp in (30, 50)]
EXIT_RULES += [_rule(f"tp{tp}_sl{sl}", tp=tp, sl=sl) for sl in (15, 20, 25) for tp in (20, 30, 50)]

LIVE_POLICY = "live_all_reentries"
POLICIES = {
    LIVE_POLICY: ("all", 0),
    "first_trade_only": ("first_only", 0),
    "halt_after_1_stop": ("halt_after_stops", 1),
    "halt_after_2_stops": ("halt_after_stops", 2),
    "halt_after_3_stops": ("halt_after_stops", 3),
    "cooldown_5m_after_stop": ("cooldown_min", 5),
    "cooldown_15m_after_stop": ("cooldown_min", 15),
    "cooldown_30m_after_stop": ("cooldown_min", 30),
}

# Pre-registered hypotheses. Each is fixed before the data that judges it exists and is evaluated only on tokens
# the bot FIRST traded after its registration time. Never edit a rule after registration; add a new one instead.
MIN_VERDICT_TOKENS = 30
HYPOTHESES = [
    {"name": "no_reentry_first_trade_only",
     "registered_at": "2026-09-27T06:30:00",
     "motivation": "runner study 2026-09-27 06:06Z: first_trade_only chosen on train, beat live on holdout in 99.9% "
                   "of bootstrap samples (34 holdout tokens)",
     "statement": "Taking only the first trade on each token beats the live re-entry behaviour on P&L per token.",
     "policy": "first_trade_only",
     # The no-re-entry paper trial went live here; after it, live == first trade only, so later tokens can't test this.
     "evaluated_until": "2026-09-27T18:10:19"},
]


def _pct(a, b):
    return ((b / a) - 1) * 100 if a and b is not None else None


def _is_stop(t):
    return (t[8] or "").startswith("STOP")


def _by_token(trades):
    out = {}
    for t in trades:
        out.setdefault(t[3], []).append(t)
    return out


def census(trades, snaps):
    px = {}
    for addr, at, price, _liq in snaps:
        d = px.setdefault(addr, ([], []))
        d[0].append(at)
        d[1].append(float(price))
    rows = []
    for addr, ts in _by_token(trades).items():
        p0 = ts[0][6]
        if not p0:
            continue
        times, prices = px.get(addr, ([], []))
        lo = bisect.bisect_left(times, ts[0][4])
        hi = bisect.bisect_right(times, max(t[5] or t[4] for t in ts))
        peak = max(prices[lo:hi], default=None)
        rows.append({"token": ts[0][2], "trades": len(ts), "stops": sum(_is_stop(t) for t in ts),
                     "targets": sum((t[8] or "").startswith("TARGET") for t in ts),
                     "run_up_pct": _r(_pct(float(p0), peak), 1), "bot_pnl_usd": _r(sum(t[10] or 0 for t in ts))})
    runners = [r for r in rows if r["run_up_pct"] is not None and r["run_up_pct"] >= RUN_THRESHOLD_PCT]
    others = [r for r in rows if r not in runners]

    def group(rs):
        pnl = sum(r["bot_pnl_usd"] for r in rs)
        return {"tokens": len(rs), "trades": sum(r["trades"] for r in rs), "stops": sum(r["stops"] for r in rs),
                "bot_pnl_usd": _r(pnl), "pnl_per_token_usd": _r(pnl / len(rs)) if rs else None,
                "tokens_bot_lost_money_on": sum(r["bot_pnl_usd"] < 0 for r in rs)}
    lost = sorted((r for r in runners if r["bot_pnl_usd"] < 0), key=lambda r: r["run_up_pct"], reverse=True)
    return {"run_threshold_pct": RUN_THRESHOLD_PCT,
            "definition": "run-up = highest sampled price between the first entry and the last exit, vs the first entry price",
            "runners": group(runners), "other_tokens": group(others), "runners_bot_lost_money_on": lost[:15]}


def keep_trades(ts, policy):
    """Trades on one token (in order) that a re-entry policy would still have taken."""
    kind, k = policy
    kept, streak, last_stop_close = [], 0, None
    for t in ts:
        if kind == "first_only" and kept:
            break
        if kind == "halt_after_stops" and streak >= k:
            break
        if kind == "cooldown_min" and last_stop_close and \
                (datetime.fromisoformat(t[4]) - datetime.fromisoformat(last_stop_close)).total_seconds() < k * 60:
            continue
        kept.append(t)
        streak = streak + 1 if _is_stop(t) else 0
        if _is_stop(t):
            last_stop_close = t[5]
    return kept


def judge(per_token, first_seen, names, baseline, seed=5):
    """Choose the best name on training tokens by P&L per token; judge it on holdout tokens against the baseline."""
    ordered = sorted(per_token, key=first_seen.get)
    cut = int(len(ordered) * TRAIN_FRACTION)
    train, hold = ordered[:cut], ordered[cut:]

    def summary(toks, name):
        vals = [v for tok in toks for v in per_token[tok][name]]
        s = _stats(vals)
        s["tokens"] = len(toks)
        s["pnl_per_token_usd"] = _r(sum(vals) / len(toks)) if toks else None
        return s
    table = {n: {"train": summary(train, n), "holdout": summary(hold, n)} for n in names}
    chosen = max(names, key=lambda n: table[n]["train"]["pnl_per_token_usd"]
                 if table[n]["train"]["pnl_per_token_usd"] is not None else float("-inf"))
    rng = random.Random(seed)
    beats = positive = done = 0
    for _ in range(BOOTSTRAP_SAMPLES if hold else 0):
        sample = [rng.choice(hold) for _ in hold]
        c = sum(sum(per_token[t][chosen]) for t in sample)
        b = sum(sum(per_token[t][baseline]) for t in sample)
        beats += c > b
        positive += c > 0
        done += 1
    ch, live = table[chosen]["holdout"], table[baseline]["holdout"]
    if not done or not ch.get("n"):
        verdict = "insufficient holdout data"
    elif chosen == baseline:
        verdict = "the live behaviour is best on training tokens"
    elif ch["pnl_per_token_usd"] > live["pnl_per_token_usd"] and beats / done >= .9 and positive / done >= .9:
        verdict = "candidate: beats live AND profitable on holdout in >=90% of bootstrap samples -> eligible to pre-register"
    elif ch["pnl_per_token_usd"] > live["pnl_per_token_usd"] and beats / done >= .9:
        verdict = "improves on live on holdout, but still not reliably profitable"
    else:
        verdict = "not promotable: does not reliably beat live on holdout"
    return {"train_tokens": len(train), "holdout_tokens": len(hold), "chosen_on_train": chosen,
            "chosen": table[chosen], "live": table[baseline],
            "holdout_bootstrap": {"samples": done,
                                  "pct_chosen_beats_live": _r(100 * beats / done, 1) if done else None,
                                  "pct_chosen_positive": _r(100 * positive / done, 1) if done else None},
            "verdict": verdict, "all": table}


def wider_stops(trades, snaps, first_seen):
    per_token, excluded = {}, 0
    for tr in build_paths(trades, snaps):
        sims = [simulate(tr["entry_price"], tr["path"], rule) for rule in EXIT_RULES]
        if any(s is None for s in sims):
            excluded += 1
            continue
        d = per_token.setdefault(tr["token_address"], {rule["name"]: [] for rule in EXIT_RULES})
        for rule, (_reason, px, _secs) in zip(EXIT_RULES, sims):
            d[rule["name"]].append(net_return_pct(tr["entry_price"], px))
    out = judge(per_token, first_seen, [r["name"] for r in EXIT_RULES], BASELINE)
    out["trades_replayed"] = sum(len(v[BASELINE]) for v in per_token.values())
    out["trades_excluded_incomplete_path"] = excluded
    return out


def reentry(trades, first_seen):
    per_token = {addr: {name: [t[9] for t in keep_trades(ts, pol)] for name, pol in POLICIES.items()}
                 for addr, ts in _by_token(trades).items()}
    return judge(per_token, first_seen, list(POLICIES), LIVE_POLICY)


def preregistered(trades, seed=29):
    by_tok = _by_token(trades)
    out = []
    for h in HYPOTHESES:
        toks = [a for a, ts in by_tok.items() if ts[0][4] >= h["registered_at"]
                and ("evaluated_until" not in h or ts[0][4] < h["evaluated_until"])]
        per = {a: {n: sum(t[9] for t in keep_trades(by_tok[a], POLICIES[n])) for n in (h["policy"], LIVE_POLICY)}
               for a in toks}

        def side(name):
            vals = [per[a][name] for a in toks]
            return {"pnl_usd": _r(sum(vals)), "pnl_per_token_usd": _r(sum(vals) / len(vals)) if vals else None}
        pol, live = side(h["policy"]), side(LIVE_POLICY)
        rng = random.Random(seed)
        beats = positive = done = 0
        for _ in range(BOOTSTRAP_SAMPLES if toks else 0):
            sample = [rng.choice(toks) for _ in toks]
            c = sum(per[a][h["policy"]] for a in sample)
            beats += c > sum(per[a][LIVE_POLICY] for a in sample)
            positive += c > 0
            done += 1
        pct_beats = _r(100 * beats / done, 1) if done else None
        if len(toks) < MIN_VERDICT_TOKENS:
            verdict = f"collecting: need {MIN_VERDICT_TOKENS}+ tokens first traded after registration (have {len(toks)})"
        elif pol["pnl_per_token_usd"] <= live["pnl_per_token_usd"]:
            verdict = "REJECTED: does not beat the live behaviour"
        elif pct_beats >= 90:
            verdict = "SUPPORTED: beats live in >=90% of bootstrap samples -> eligible for a paper trial (needs owner OK)"
        else:
            verdict = "NOT SUPPORTED: ahead of live but not reliably"
        out.append({**h, "tokens_evaluated": len(toks), "policy_result": pol, "live_result": live,
                    "bootstrap_pct_beats_live": pct_beats,
                    "bootstrap_pct_policy_positive": _r(100 * positive / done, 1) if done else None,
                    "verdict": verdict})
    return out


def run(conn, as_of):
    trades, _ledger, snaps = load(conn)
    elig = [t for t in trades if _era(t[4]) in ONE_PER_TOKEN_ERAS and t[9] is not None]
    first_seen = {}
    for t in elig:
        first_seen.setdefault(t[3], t[4])
    return {"as_of": as_of, "mode": "read_only_runner_study", "eras_used": sorted(ONE_PER_TOKEN_ERAS),
            "trades_used": len(elig), "tokens_used": len(first_seen),
            "census": census(elig, snaps),
            "wider_stops": wider_stops(elig, snaps, first_seen),
            "reentry_policy": reentry(elig, first_seen),
            "preregistered_hypotheses": preregistered(elig),
            "notes": ["Wider stops: sampled quotes (~10-30s); a stop fills at the next quote, so gaps are only partly modelled.",
                      "Re-entry policies remove trades the policy would have skipped; they cannot add the trades the bot "
                      "might have taken instead with the freed slot or at different times.",
                      "Scores are P&L per token ($100 per trade), so policies that trade less are compared fairly.",
                      "A 'candidate' must still be pre-registered and confirmed on later data before any paper trial."]}
