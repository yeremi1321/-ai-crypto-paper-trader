"""Read-only paper analysis: features, era split, holdout test, and the HTTP endpoints."""
import json
import tempfile
import threading
import urllib.request
from datetime import datetime, timedelta, timezone
from http.server import HTTPServer
from pathlib import Path
from unittest.mock import patch

import memecoin_entry_analysis as ea
import memecoin_fast_collector as fc
from memecoin_paper import migrate
from memecoin_shadow import init_db

T0 = datetime(2026, 9, 26, 6, 0, tzinfo=timezone.utc)


def iso(sec):
    return (T0 + timedelta(seconds=sec)).isoformat()


def _db(path):
    c = init_db(path); migrate(c)
    c.execute("""CREATE TABLE IF NOT EXISTS meme_price_snapshots(id INTEGER PRIMARY KEY AUTOINCREMENT,observed_at TEXT NOT NULL,
        token_address TEXT NOT NULL,pair_address TEXT,price REAL NOT NULL,liquidity_usd REAL,volume_1h_usd REAL)""")
    cid = [0]

    def trade(token, opened, closed, entry, exit_, reason, liq, pnl):
        cid[0] += 1
        c.execute("""INSERT INTO meme_paper_trades(candidate_id,token,token_address,opened_at,entry_market_price,entry_price,
            quantity,entry_fee,status,closed_at,exit_market_price,exit_reason,net_return_pct,net_pnl_usd,mfe_pct,mae_pct)
            VALUES(?,?,?,?,?,?,1,.6,'CLOSED',?,?,?,?,?,?,?)""",
                  (cid[0], token, token, iso(opened), entry, entry * 1.01, iso(closed), exit_, reason, pnl, pnl,
                   -0.99 if pnl < 0 else 25, -30 if pnl < 0 else -1))
        c.execute("INSERT INTO meme_decision_ledger(candidate_id,liquidity_usd,volume_1h_usd,score,outcome_label) VALUES(?,?,?,?,?)",
                  (cid[0], liq, 50000, 70, "WIN" if pnl > 0 else "LOSS"))

    def snap(token, sec, price, liq):
        c.execute("INSERT INTO meme_price_snapshots(observed_at,token_address,price,liquidity_usd) VALUES(?,?,?,?)",
                  (iso(sec), token, price, liq))

    # Era A: two stacked positions on STACK, both stopped by one crash.
    trade("STACK", 0, 120, 1.0, 0.6, "STOP_10", 40000, -41.0)
    trade("STACK", 30, 120, 1.0, 0.6, "STOP_10", 40000, -41.0)
    # Era B: RUG liquidity drains during the trade; gaps to -30%.
    for s, p, l in [(4000, 1.0, 60000), (4100, 1.05, 50000)]:
        snap("RUG", s, p, l)
    trade("RUG", 4200, 4300, 1.1, 0.77, "STOP_10", 45000, -31.5)
    snap("RUG", 4250, 0.9, 9000)
    # Era C: target, then stop, then a re-entry 50s after the stop that also stops.
    trade("BOUNCE", 7500, 7560, 1.0, 1.25, "TARGET_20", 80000, 22.4)
    trade("BOUNCE", 7600, 7700, 1.2, 0.85, "STOP_10", 70000, -28.1)
    trade("BOUNCE", 7750, 7800, 0.9, 0.8, "STOP_10", 60000, -12.7)
    # Extra independent tokens so the token-disjoint holdout has data on both sides.
    for i in range(10):
        good = i % 3 == 0
        trade(f"T{i}", 5000 + i * 60, 5030 + i * 60, 1.0, 1.25 if good else 0.85, "TARGET_20" if good else "STOP_10",
              30000 + i * 5000, 22.0 if good else -16.0)
    c.commit(); c.close()


def test_features_and_eras():
    with tempfile.TemporaryDirectory() as d:
        path = str(Path(d) / "a.db"); _db(path)
        c = init_db(path)
        summary, table = ea.run(c, "now"); c.close()
    rows = {(r[1], r[2]): dict(zip(table["columns"], r)) for r in table["rows"]}
    stack2 = rows[("STACK", iso(30))]
    assert stack2["era"] == "A_stacking_before_one_per_token" and stack2["concurrent_same_token"] == 1
    rug = rows[("RUG", iso(4200))]
    assert rug["era"] == "B_one_per_token_30s_exits"
    assert rug["stop_overshoot_pct"] == 20.0            # -30% raw vs -10% nominal
    assert rug["liq_change_pre_pct"] == -25.0           # 60k -> 45k before entry
    assert rug["liq_change_during_pct"] == -80.0        # 45k -> 9k during the trade
    assert rug["price_change_pre_pct"] == 10.0
    assert rug["max_gap_s"] == 50.0
    third = rows[("BOUNCE", iso(7750))]
    assert third["era"] == "C_10s_exits" and third["prev_exit_reason"] == "STOP_10" and third["secs_since_prev_close"] == 50
    c_era = summary["eras"]["C_10s_exits"]
    assert c_era["all"]["n"] == 3 and c_era["repeat_after_stop_within_120s"]["n"] == 1
    assert summary["eras"]["A_stacking_before_one_per_token"]["stacked_entries"]["n"] == 1
    ho = summary["holdout_first_trade_per_token"]
    assert ho["train_tokens"] + ho["holdout_tokens"] == 13
    assert "entry_liquidity_usd" in ho["features"]
    json.dumps(summary); json.dumps(table)


def test_http_endpoints_are_read_only_and_cached():
    with tempfile.TemporaryDirectory() as d:
        path = str(Path(d) / "b.db"); _db(path)
        calls = []
        real_run = ea.run
        def counting_run(conn, as_of):
            calls.append(1); return real_run(conn, as_of)
        fc._ANALYSIS.update(at=0.0, summary=None, trades=None)
        with patch.object(fc, "init_db", lambda: init_db(path)), patch.object(fc.memecoin_entry_analysis, "run", counting_run):
            server = HTTPServer(("127.0.0.1", 0), fc.Health)
            t = threading.Thread(target=server.serve_forever, daemon=True); t.start()
            base = f"http://127.0.0.1:{server.server_address[1]}"
            before = Path(path).read_bytes()
            s = json.load(urllib.request.urlopen(base + "/paper-analysis"))
            tr = json.load(urllib.request.urlopen(base + "/paper-analysis-trades"))
            server.shutdown()
            after = Path(path).read_bytes()
    assert s["mode"] == "read_only_paper_analysis" and s["total"]["n"] == 16
    assert tr["columns"][0] == "id" and len(tr["rows"]) == 16
    assert len(calls) == 1, "second request must be served from cache"
    assert before == after, "analysis must not modify the database"


if __name__ == "__main__":
    test_features_and_eras()
    test_http_endpoints_are_read_only_and_cached()
    print("paper analysis tests passed")
