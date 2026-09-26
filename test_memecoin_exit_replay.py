"""Replay mechanics, paper cost parity, token holdout, and read-only HTTP cache."""
import json
import tempfile
import threading
import urllib.request
from datetime import datetime, timedelta, timezone
from http.server import HTTPServer
from pathlib import Path
from unittest.mock import patch

import memecoin_exit_replay as er
import memecoin_fast_collector as fc
import memecoin_paper
from memecoin_shadow import init_db

T0 = datetime(2026, 9, 26, 6, 0, tzinfo=timezone.utc)
RULE = {r["name"]: r for r in er.RULES}


def iso(sec):
    return (T0 + timedelta(seconds=sec)).isoformat()


def test_rule_mechanics():
    e = 1.01
    assert len(RULE) == 20
    assert er.simulate(e, [(30, .90)], RULE[er.BASELINE])[0] == "STOP"
    assert er.simulate(e, [(30, 1.25)], RULE[er.BASELINE])[0] == "TARGET"
    assert er.simulate(e, [(30, 1.12), (60, 1.07)], RULE["tp20_sl10_trail10_3"])[0] == "TRAIL"
    assert er.simulate(e, [(30, 1.12), (60, 1.07)], RULE[er.BASELINE]) is None
    assert er.simulate(e, [(30, 1.07), (60, 1.02)], RULE["tp20_sl10_breakeven5"])[0] == "BREAKEVEN"
    assert er.simulate(e, [(600, 1.02), (1200, 1.03)], RULE[er.BASELINE])[0] == "TIME"
    assert er.simulate(e, [(30, 1.12)], RULE["tp10_sl10"])[0] == "TARGET"


def test_cost_model_matches_live_engine():
    c = init_db(":memory:"); memecoin_paper.migrate(c)
    entry_mkt = .0001; entry = entry_mkt * 1.01; qty = 99.4 / entry
    opened = datetime.now(timezone.utc) - timedelta(minutes=1)
    c.execute("""INSERT INTO meme_paper_trades(candidate_id,token,token_address,opened_at,entry_market_price,
        entry_price,notional_usd,quantity,entry_fee,status,highest_price,lowest_price,current_price)
        VALUES(1,'X','x',?,?,?,100,?,.6,'OPEN',?,?,?)""",
        (opened.isoformat(), entry_mkt, entry, qty, entry_mkt * 1.3, entry_mkt, entry_mkt * 1.3))
    c.execute("INSERT INTO meme_decision_ledger(candidate_id,outcome_label) VALUES(1,'PENDING')")
    c.commit()
    memecoin_paper.close_positions(c)
    live = c.execute("SELECT net_return_pct FROM meme_paper_trades").fetchone()[0]
    assert abs(er.net_return_pct(entry, entry_mkt * 1.3) - live) < 1e-6
    c.close()


def _db(path, n_tokens=20, train_trail_edge=True, holdout_trail_edge=False):
    c = init_db(path); memecoin_paper.migrate(c)
    c.execute("""CREATE TABLE IF NOT EXISTS meme_price_snapshots(id INTEGER PRIMARY KEY AUTOINCREMENT,
        observed_at TEXT NOT NULL,token_address TEXT NOT NULL,pair_address TEXT,price REAL NOT NULL,
        liquidity_usd REAL,volume_1h_usd REAL)""")
    cut = int(n_tokens * er.TRAIN_FRACTION)
    for i in range(n_tokens):
        tok = f"T{i:02d}"; start = i * 2000
        edge = train_trail_edge if i < cut else holdout_trail_edge
        path = [(30, 1.06), (60, 1.13), (90, 1.08), (120, .80)] if edge else [(30, 1.03), (60, .80)]
        for s, p in path:
            c.execute("INSERT INTO meme_price_snapshots(observed_at,token_address,price,liquidity_usd) VALUES(?,?,?,50000)",
                      (iso(start + s), tok, p))
        net = er.net_return_pct(1.01, .80)
        c.execute("""INSERT INTO meme_paper_trades(candidate_id,token,token_address,opened_at,
            entry_market_price,entry_price,notional_usd,quantity,entry_fee,status,closed_at,
            exit_market_price,exit_reason,net_return_pct,net_pnl_usd,mfe_pct,mae_pct)
            VALUES(?,?,?,?,1.0,1.01,100,?,?, 'CLOSED',?,.80,'STOP_10',?,?,11.9,-20.8)""",
            (i + 1, tok, tok, iso(start), 99.4 / 1.01, .6, iso(start + (120 if edge else 60)), net, net))
        c.execute("INSERT INTO meme_decision_ledger(candidate_id,outcome_label) VALUES(?,'LOSS')", (i + 1,))
    c.commit(); c.close()


def test_harness_validation_and_holdout_discipline():
    with tempfile.TemporaryDirectory() as d:
        path = str(Path(d) / "r.db")
        _db(path, train_trail_edge=True, holdout_trail_edge=False)
        c = init_db(path); out = er.run(c, "now"); c.close()
    v = out["harness_validation_live_rule"]
    assert v["trades_compared"] == 20 and v["same_exit_reason_pct"] == 100.0
    assert v["median_abs_net_return_error_pct"] < .01
    ev = out["all_trades_token_split"]
    assert ev["chosen_on_train"] != er.BASELINE
    assert ev["chosen"]["train"]["avg_net_return_pct"] > ev["live_rule"]["train"]["avg_net_return_pct"]
    assert ev["verdict"].startswith("not promotable"), ev["verdict"]
    json.dumps(out)


def test_genuine_edge_is_recognised():
    with tempfile.TemporaryDirectory() as d:
        path = str(Path(d) / "g.db")
        _db(path, train_trail_edge=True, holdout_trail_edge=True)
        c = init_db(path); out = er.run(c, "now"); c.close()
    ev = out["all_trades_token_split"]
    assert ev["chosen"]["holdout"]["avg_net_return_pct"] > ev["live_rule"]["holdout"]["avg_net_return_pct"]
    assert ev["holdout_bootstrap"]["pct_chosen_beats_live"] == 100.0
    assert not ev["verdict"].startswith("not promotable")


def test_endpoint_read_only_and_cached():
    with tempfile.TemporaryDirectory() as d:
        path = str(Path(d) / "e.db"); _db(path)
        calls = []; real = er.run
        fc._REPLAY.update(at=0.0, result=None)
        with patch.object(fc, "init_db", lambda: init_db(path)), \
             patch.object(fc.memecoin_exit_replay, "run", lambda c, a: (calls.append(1), real(c, a))[1]):
            server = HTTPServer(("127.0.0.1", 0), fc.Health)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                url = f"http://127.0.0.1:{server.server_address[1]}/paper-exit-replay"
                before = Path(path).read_bytes()
                a = json.load(urllib.request.urlopen(url))
                json.load(urllib.request.urlopen(url))
                assert Path(path).read_bytes() == before
            finally:
                server.shutdown(); server.server_close(); thread.join(3)
    assert a["mode"] == "read_only_exit_replay" and a["trades_replayed"] == 20 and len(calls) == 1


if __name__ == "__main__":
    test_rule_mechanics()
    test_cost_model_matches_live_engine()
    test_harness_validation_and_holdout_discipline()
    test_genuine_edge_is_recognised()
    test_endpoint_read_only_and_cached()
    print("exit replay tests passed")
