"""Research-only entry learning engine.

Replays historical scanner decisions causally and compares the original decision price
with delayed entries (1/2/3 scans) and pullback/retest-style alternatives. It writes
suggestions only; it never changes V5 or Challenger rules.
"""
import argparse
import sqlite3
import pandas as pd

DB = "paper_trader_v4.db"
HORIZON_SCANS = 8
DELAY_SCANS = (1, 2, 3)
MIN_SAMPLES = 12


def ensure_schema(conn):
    conn.execute("""CREATE TABLE IF NOT EXISTS entry_learning(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        evaluated_at TEXT, decision_id INTEGER, product TEXT, decision TEXT,
        original_price REAL, horizon_price REAL, original_return_pct REAL,
        best_entry_style TEXT, best_entry_price REAL, best_return_pct REAL,
        improvement_pct REAL, sample_ready INTEGER, detail TEXT,
        UNIQUE(decision_id)
    )""")
    conn.commit()


def future_path(scans, product, seen_at):
    return scans[(scans.product == product) & (scans.seen_at > seen_at)].head(HORIZON_SCANS).copy()


def evaluate(conn):
    ensure_schema(conn)
    decisions = pd.read_sql_query(
        """SELECT id, seen_at, product, decision, price FROM decision_log
           WHERE stage='ENTRY_FILTER' ORDER BY id""", conn
    )
    scans = pd.read_sql_query("SELECT id, seen_at, product, price FROM scans ORDER BY id", conn)
    if decisions.empty or scans.empty:
        return 0
    decisions["seen_at"] = pd.to_datetime(decisions.seen_at, utc=True)
    scans["seen_at"] = pd.to_datetime(scans.seen_at, utc=True)
    existing = {r[0] for r in conn.execute("SELECT decision_id FROM entry_learning").fetchall()}
    inserted = 0
    for row in decisions.itertuples():
        if row.id in existing or not row.price:
            continue
        path = future_path(scans, row.product, row.seen_at)
        if len(path) < HORIZON_SCANS:
            continue
        horizon = float(path.price.iloc[-1])
        original_return = (horizon / float(row.price) - 1) * 100
        candidates = [("IMMEDIATE", float(row.price))]
        for delay in DELAY_SCANS:
            candidates.append((f"WAIT_{delay}_SCAN", float(path.price.iloc[delay - 1])))
        # Causal proxy: first later scan at/below original price while the observation window unfolds.
        pullbacks = path[path.price <= float(row.price)]
        if not pullbacks.empty:
            candidates.append(("PULLBACK_RETEST", float(pullbacks.price.iloc[0])))
        scored = [(style, price, (horizon / price - 1) * 100) for style, price in candidates if price > 0]
        style, best_price, best_return = max(scored, key=lambda x: x[2])
        improvement = best_return - original_return
        prior_samples = conn.execute(
            "SELECT COUNT(*) FROM entry_learning WHERE product=? AND best_entry_style=?",
            (row.product, style),
        ).fetchone()[0]
        sample_ready = int(prior_samples + 1 >= MIN_SAMPLES)
        detail = f"Research only: {style} improved horizon return by {improvement:+.2f}pp vs immediate."
        conn.execute("""INSERT OR IGNORE INTO entry_learning(
            evaluated_at, decision_id, product, decision, original_price, horizon_price,
            original_return_pct, best_entry_style, best_entry_price, best_return_pct,
            improvement_pct, sample_ready, detail
        ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (pd.Timestamp.now(tz="UTC").isoformat(), row.id, row.product, row.decision,
             float(row.price), horizon, original_return, style, best_price, best_return,
             improvement, sample_ready, detail))
        inserted += 1
    conn.commit()
    return inserted


def table_exists(conn, name):
    return conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)).fetchone() is not None


def evaluate_trades(conn):
    """Study completed V5 and Challenger trades without changing either strategy."""
    ensure_schema(conn)
    scans = pd.read_sql_query("SELECT id, seen_at, product, price FROM scans ORDER BY id", conn)
    if scans.empty:
        return 0
    scans["seen_at"] = pd.to_datetime(scans.seen_at, utc=True)
    sources = []
    if table_exists(conn, "paper_trades"):
        sources.append(("V5", "paper_trades"))
    if table_exists(conn, "challenger_trades"):
        sources.append(("CHALLENGER", "challenger_trades"))
    inserted = 0
    for source, table in sources:
        cols = {r[1] for r in conn.execute("PRAGMA table_info(" + table + ")").fetchall()}
        mfe_expr = "mfe_pct" if "mfe_pct" in cols else "NULL AS mfe_pct"
        mae_expr = "mae_pct" if "mae_pct" in cols else "NULL AS mae_pct"
        trades = pd.read_sql_query(
            f"""SELECT id, product, opened_at, closed_at, entry_market_price,
                       exit_market_price, net_return_pct, exit_reason,
                       {mfe_expr}, {mae_expr}
                FROM {table} WHERE status='CLOSED' AND closed_at IS NOT NULL ORDER BY id""", conn)
        for t in trades.itertuples():
            exists = conn.execute("SELECT 1 FROM trade_learning WHERE source=? AND trade_id=?", (source, t.id)).fetchone()
            if exists or not t.entry_market_price or not t.exit_market_price:
                continue
            opened = pd.to_datetime(t.opened_at, utc=True)
            closed = pd.to_datetime(t.closed_at, utc=True)
            path = scans[(scans.product == t.product) & (scans.seen_at > opened) & (scans.seen_at < closed)].head(HORIZON_SCANS)
            candidates = [("ACTUAL", float(t.entry_market_price))]
            for delay in DELAY_SCANS:
                if len(path) >= delay:
                    candidates.append((f"WAIT_{delay}_SCAN", float(path.price.iloc[delay - 1])))
            pullbacks = path[path.price <= float(t.entry_market_price)]
            if not pullbacks.empty:
                candidates.append(("PULLBACK_RETEST", float(pullbacks.price.iloc[0])))
            exit_market = float(t.exit_market_price)
            scored = [(style, price, (exit_market / price - 1) * 100) for style, price in candidates if price > 0]
            style, best_price, cf_return = max(scored, key=lambda x: x[2])
            actual_return = float(t.net_return_pct or 0)
            improvement = cf_return - actual_return
            mfe = None if pd.isna(t.mfe_pct) else float(t.mfe_pct)
            mae = None if pd.isna(t.mae_pct) else float(t.mae_pct)
            capture = (actual_return / mfe * 100) if mfe and mfe > 0 else None
            detail = f"{source}: {style} was best among tested entry timings; {improvement:+.2f}pp vs recorded net return."
            conn.execute("""INSERT OR IGNORE INTO trade_learning(
                evaluated_at, source, trade_id, product, opened_at, closed_at, entry_price,
                exit_price, actual_return_pct, mfe_pct, mae_pct, exit_reason, best_entry_style,
                best_entry_price, counterfactual_return_pct, entry_improvement_pct,
                capture_ratio, detail
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (pd.Timestamp.now(tz="UTC").isoformat(), source, t.id, t.product, t.opened_at,
                 t.closed_at, float(t.entry_market_price), exit_market, actual_return, mfe, mae,
                 t.exit_reason, style, best_price, cf_return, improvement, capture, detail))
            inserted += 1
    conn.commit()
    return inserted


def self_test():
    conn = sqlite3.connect(":memory:")
    conn.execute("""CREATE TABLE decision_log(
        id INTEGER PRIMARY KEY, seen_at TEXT, product TEXT, stage TEXT,
        decision TEXT, price REAL)""")
    conn.execute("""CREATE TABLE scans(
        id INTEGER PRIMARY KEY, seen_at TEXT, product TEXT, price REAL)""")
    start = pd.Timestamp("2026-01-01T00:00:00Z")
    conn.execute("INSERT INTO decision_log VALUES(1,?,?,?,?,?)",
                 (start.isoformat(), "BTC-USD", "ENTRY_FILTER", "QUALIFIES", 100.0))
    prices = [99, 98, 101, 102, 103, 104, 105, 106]
    for i, price in enumerate(prices, 1):
        conn.execute("INSERT INTO scans VALUES(?,?,?,?)",
                     (i, (start + pd.Timedelta(minutes=15*i)).isoformat(), "BTC-USD", price))
    evaluated = evaluate(conn)
    assert evaluated == 1, f"expected 1 evaluated decision, got {evaluated}"
    row = conn.execute("SELECT best_entry_style, improvement_pct FROM entry_learning").fetchone()
    assert row[0] in {"WAIT_1_SCAN", "WAIT_2_SCAN", "WAIT_3_SCAN", "PULLBACK_RETEST"}
    assert row[1] > 0
    print("entry_learning self-test passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=DB)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    else:
        conn = sqlite3.connect(args.db)
        decision_count = evaluate(conn)
        trade_count = evaluate_trades(conn)
        print(f"entry learning: {decision_count} decisions + {trade_count} completed trades evaluated")
        conn.close()
