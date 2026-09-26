"""Read-only diagnostic of completed memecoin paper trades.

Run inside the existing Render service, where its private PostgreSQL is reachable.
The chronological holdout is reported once and never used to select a rule.
"""
import json
import statistics
from collections import Counter, defaultdict
from datetime import datetime, timezone

from memecoin_shadow import init_db

FEATURES = {
    "liquidity_usd": (lambda x: x.get("liquidity_usd"), [50000, 75000, 100000, 150000]),
    "makers": (lambda x: x.get("makers"), [250, 500, 1000, 3000]),
    "volume_1h_usd": (lambda x: x.get("volume_1h_usd"), [50000, 100000, 250000, 500000]),
    "price_change_1h_pct": (lambda x: x.get("price_change_1h_pct"), [20, 50, 100, 200]),
    "volume_accel": (lambda x: x.get("volume_accel"), [1.5, 2, 3, 5]),
    "score": (lambda x: x.get("score"), [65, 70, 80, 90]),
}


def stats(rows):
    if not rows:
        return {"n": 0}
    returns = [r["net_return_pct"] for r in rows]
    return {
        "n": len(rows),
        "wins": sum(v > 0 for v in returns),
        "win_pct": round(100 * sum(v > 0 for v in returns) / len(rows), 2),
        "mean_net_pct": round(statistics.mean(returns), 3),
        "median_net_pct": round(statistics.median(returns), 3),
        "sum_pnl_usd": round(sum(r["net_pnl_usd"] for r in rows), 2),
    }


def load(conn):
    sql = """SELECT p.candidate_id,p.token_address,p.opened_at,p.closed_at,
             p.net_return_pct,p.net_pnl_usd,p.exit_reason,p.mfe_pct,p.mae_pct,
             p.entry_price,p.exit_market_price,l.raw_json,l.score
             FROM meme_paper_trades p JOIN meme_decision_ledger l
             ON p.candidate_id=l.candidate_id
             WHERE p.status='CLOSED' AND p.net_return_pct IS NOT NULL
             ORDER BY p.opened_at,p.id"""
    rows = []
    for cid, token, opened, closed, ret, pnl, reason, mfe, mae, entry, exit_price, raw, score in conn.execute(sql):
        try:
            features = json.loads(raw or "{}")
        except (ValueError, TypeError):
            features = {}
        features["score"] = score
        rows.append(dict(candidate_id=cid, token_address=token, opened_at=opened,
                         closed_at=closed, net_return_pct=float(ret), net_pnl_usd=float(pnl),
                         exit_reason=reason, mfe_pct=mfe, mae_pct=mae,
                         entry_price=entry, exit_market_price=exit_price, features=features))
    return rows


def summarize(rows):
    first = {}
    for row in rows:
        first.setdefault(row["token_address"], row)
    unique = sorted(first.values(), key=lambda r: r["opened_at"])
    cut = max(1, int(len(unique) * .7))
    train, holdout = unique[:cut], unique[cut:]
    baseline = stats(train)
    by_exit = {reason: stats(group) for reason, group in
               ((key, [r for r in rows if r["exit_reason"] == key])
                for key in sorted({r["exit_reason"] for r in rows}))}
    duplicates = Counter(r["token_address"] for r in rows)
    winners = [r for r in train if r["net_return_pct"] > 0]
    losers = [r for r in train if r["net_return_pct"] <= 0]
    feature_report = {}
    candidates = []
    for name, (getter, thresholds) in FEATURES.items():
        def val(row):
            try:
                value = getter(row["features"])
                return float(value) if value is not None else None
            except (TypeError, ValueError):
                return None
        def median(group):
            values = [v for r in group if (v := val(r)) is not None]
            return round(statistics.median(values), 3) if values else None
        feature_report[name] = {
            "winner_median": median(winners), "loser_median": median(losers),
            "missing_train": sum(val(r) is None for r in train),
        }
        for threshold in thresholds:
            for direction in ("ge", "le"):
                chosen = [r for r in train if (v := val(r)) is not None and
                          (v >= threshold if direction == "ge" else v <= threshold)]
                if len(chosen) < max(20, int(len(train) * .15)):
                    continue
                s = stats(chosen)
                candidates.append((s["mean_net_pct"] - baseline["mean_net_pct"],
                                   name, direction, threshold, s))
    # Select on training only. Holdout is evaluated only for the chosen rule.
    candidates.sort(reverse=True)
    selected = candidates[0] if candidates else None
    selected_report = None
    if selected:
        improvement, name, direction, threshold, training = selected
        getter = FEATURES[name][0]
        def passes(row):
            try:
                v = getter(row["features"])
                return v is not None and (float(v) >= threshold if direction == "ge"
                                          else float(v) <= threshold)
            except (TypeError, ValueError):
                return False
        selected_report = {"feature": name, "direction": direction, "threshold": threshold,
                           "training": training, "training_delta_mean_pct": round(improvement, 3),
                           "holdout": stats([r for r in holdout if passes(r)]),
                           "holdout_baseline": stats(holdout)}
    return {
        "all_trades": stats(rows), "unique_tokens": len(unique),
        "repeated_token_trades": sum(n - 1 for n in duplicates.values()),
        "top_repeat_counts": duplicates.most_common(5),
        "first_trade_train": baseline, "first_trade_holdout": stats(holdout),
        "feature_medians_train": feature_report,
        "exit_reasons_all": by_exit, "selected_training_rule": selected_report,
        "holdout_used_for_selection": False,
    }


def run():
    conn = init_db()
    try:
        report = summarize(load(conn))
    finally:
        conn.close()
    print("MEME_TRADE_ANALYSIS " + json.dumps(report, sort_keys=True), flush=True)
    return report


if __name__ == "__main__":
    run()
