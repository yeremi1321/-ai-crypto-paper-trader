"""Exit replay: rule mechanics, cost parity with the live engine, harness validation, holdout discipline."""
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
    e = 1.01  # entry_price incl. slippage; market entry 1.00
    assert er.simulate(e, [(30, 0.90)], RULE[er.BASELINE])[0] == "STOP"
    assert er.simulate(e, [(30, 1.25)], RULE[er.BASELINE])[0] == "TARGET"
    assert er.simulate(e, [(30, 1.12), (60, 1.07)], RULE["tp20_sl10_trail10_3"])[0] == "TRAIL"
    assert er.simulate(e, [(30, 1.12), (60, 1.07)], RULE[er.BASELINE]) is None  # path ends early: incomplete
    assert er.simulate(e, [(30, 1.07), (60, 1.02)], RULE["tp20_sl10_breakeven5"])[0] == "BREAKEVEN"
    assert er.simulate(e, [(600, 1.02), (1200, 1.03)], RULE[er.BASELINE])[0] == "TIME"
    assert er.simulate(e, [(30, 1.12)], RULE["tp10_sl10"])[0] == "TARGET"


def test_cost_model_matches_live_engine():
    c = init_db(":memory:"); memecoin_paper.migrate(c)
    entry_mkt = 0.0001; entry = entry_mkt * 1.01; qty = 99.4 / entry
    opened = datetime.now(timezone.utc) - timedelta(minutes=1)
    c.execute("""INSERT INTO meme_paper_trades(candidate_id,token,token_address,opened_at,entry_market_price,entry_price,
        quantity,entry_fee,status,highest_price,lowest_price,current_price) VALUES(1,'X','x',?,?,?,?,.6,'OPEN',?,?,?)""",
              (opened.isoformat(), entry_mkt, entry, qty, entry_mkt * 1.3, entry_mkt, entry_mkt * 1.3))
    c.execute("INSERT INTO meme_decision_ledger(candidate_id,outcome_label) VALUES(1,'PENDING')"); c.commit()
    memecoin_paper.close_positions(c)
    live = c.execute("SELECT net_return_pct FROM meme_paper_trades").fetchone()[0]
    assert abs(er.net_return_pct(entry, entry_mkt * 1.3) - live) < 1e-6


def _db(path, n_tokens=20, train_trail_edge=True, holdout_trail_edge=False):
    """Each token: one trade that rises ~12% then collapses. A trailing stop saves it only when *_edge is True."""
    c = init_db(path); memecoin_paper.migrate(c)
    c.execute("""CREATE TABLE IF NOT EXISTS meme_price_snapshots(id INTEGER PRIMARY KEY AUTOINCREMENT,observed_at TEXT NOT NULL,
        token_address TEXT NOT NULL,pair_address TEXT,price REAL NOT NULL,liquidity_usd REAL,volume_1h_usd REAL)""")
    cut = int(n_tokens * er.TRAIN_FRACTION)
    for i in range(n_tokens):
        tok = f"T{i:02d}"; start = i * 2000
        edge = train_trail_edge if i < cut else holdout_trail_edge
        # rises to +12%, then either eases (trail exits green) or gaps straight through the stop
        # edge: rises to +12% and eases before collapsing (profit protection can exit green);
        # no edge: barely moves, then gaps straight through the stop (no rule can help).
        path = [(30, 1.06), (60, 1.13), (90, 1.08), (120, 0.80)] if edge else [(30, 1.03), (60, 0.80), (90, 0.80), (120, 0.80)]
        for s, p in path:
            c.execute("INSERT INTO meme_price_snapshots(observed_at,token_address,price,liquidity_usd) VALUES(?,?,?,?)",
                      (iso(start + s), tok, p, 50000))
        exit_px = 1.08 if edge else 0.80
        net = er.net_return_pct(1.01, 0.80 if not edge else 0.80)
        c.execute("""INSERT INTO meme_paper_trades(candidate_id,token,token_address,opened_at,entry_market_price,entry_price,
            quantity,entry_fee,status,closed_at,exit_market_price,exit_reason,net_return_pct,net_pnl_usd,mfe_pct,mae_pct)
            VALUES(?,?,?,?,1.0,1.01,98.4,.6,'CLOSED',?,?,?,?,?,11.9,-20.8)""",
                  (i + 1, tok, tok, iso(start), iso(start + (120 if not edge else 120)), 0.80, "STOP_10", net, net))
        c.execute("INSERT INTO meme_decision_ledger(candidate_id,outcome_label) VALUES(?,'LOSS')", (i + 1,))
    c.commit(); c.close()


def test_harness_validation_and_holdout_discipline():
    with tempfile.TemporaryDirectory() as d:
        path = str(Path(d) / "r.db")
        _db(path, train_trail_edge=True, holdout_trail_edge=False)
        c = init_db(path); out = er.run(c, "now"); c.close()
    v = out["harness_validation_live_rule"]
    assert v["trades_compared"] == 20 and v["same_exit_reason_pct"] == 100.0 and v["median_abs_net_return_error_pct"] < 0.01
    ev = out["all_trades_token_split"]
    assert ev["chosen_on_train"] != er.BASELINE, ev["chosen_on_train"]
    assert ev["chosen"]["train"]["avg_net_return_pct"] > ev["live_rule"]["train"]["avg_net_return_pct"]
    assert ev["verdict"].startswith("not promotable"), ev["verdict"]  # edge only existed in training tokens
    json.dumps(out)


def test_genuine_edge_is_recognised():
    with tempfile.TemporaryDirectory() as d:
        path = str(Path(d) / "g.db")
        _db(path, train_trail_edge=True, holdout_trail_edge=True)
        c = init_db(path); out = er.run(c, "now"); c.close()
    ev = out["all_trades_token_split"]
    assert ev["chosen"]["holdout"]["avg_net_return_pct"] > ev["live_rule"]["holdout"]["avg_net_return_pct"]
    assert ev["holdout_bootstrap"]["pct_chosen_beats_live"] == 100.0
    assert not ev["verdict"].startswith("not promotable"), ev["verdict"]


def test_endpoint_read_only_and_cached():
    """Pages are served from the background worker's cache; computing never happens on request or writes."""
    import research_worker as rw
    import memecoin_shadow
    with tempfile.TemporaryDirectory() as d:
        path = str(Path(d) / "e.db"); _db(path)
        real_init = memecoin_shadow.init_db
        rw._results.clear()
        before = Path(path).read_bytes()
        with patch.object(memecoin_shadow, "init_db", lambda p=None: real_init(path)):
            jobs = rw.default_jobs()
            list(rw.run_once({"exit_replay": jobs["exit_replay"]}))
        after = Path(path).read_bytes()
        server = HTTPServer(("127.0.0.1", 0), fc.Health)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        base = f"http://127.0.0.1:{server.server_address[1]}"
        a = json.load(urllib.request.urlopen(base + "/paper-exit-replay"))
        server.shutdown()
    assert before == after, "research must not modify the database"
    assert a["mode"] == "read_only_exit_replay" and a["trades_replayed"] == 20


if __name__ == "__main__":
    test_rule_mechanics()
    test_cost_model_matches_live_engine()
    test_harness_validation_and_holdout_discipline()
    test_genuine_edge_is_recognised()
    test_endpoint_read_only_and_cached()
    print("exit replay tests passed")


def test_faster_loss_exits_and_gap_diagnostic():
    e = 1.01
    assert er.simulate(e, [(30, .95)], RULE["tp20_sl10_early5_60s"])[0] == "EARLY_STOP"
    assert er.simulate(e, [(90, .95), (1200, 1.0)], RULE["tp20_sl10_early5_60s"])[0] == "TIME"  # outside window
    assert er.simulate(e, [(30, 1.0), (60, .93)], RULE["tp20_sl10_tickdrop5"])[0] == "TICK_DROP"
    assert er.simulate(e, [(30, 1.0), (60, .97)], RULE["tp20_sl10_tickdrop5"]) is None
    gap = {"entry_price": e, "path": [(30, 1.0), (40, .60)]}             # one 10s tick from -1% to -40%
    slide = {"entry_price": e, "path": [(30, .95), (40, .92), (50, .88)]}
    d = er.stop_gaps([gap, gap, slide])
    assert d["stops"] == 3 and d["gap_stops"]["n"] == 2 and d["sliding_stops"]["n"] == 1
    assert d["reading"].startswith("mostly gaps") and d["severe_stops_pct"] > 60
    sparse = {"entry_price": e, "path": [(30, 1.0), (600, .6)]}          # quotes 10 minutes apart
    assert er.stop_gaps([sparse])["reading"].startswith("prices too sparse")


def test_confirmed_stop_ignores_one_bad_quote():
    e = 1.01
    r = RULE["tp20_sl10_confirm2"]
    assert er.simulate(e, [(30, .5), (40, 1.0), (1200, 1.0)], r)[0] == "TIME"      # lone bad quote ignored
    assert er.simulate(e, [(30, .85), (40, .80)], r)[:2] == ("STOP", .80)          # real drop stops one quote later
    assert er.simulate(e, [(30, .5), (40, 1.0), (1200, 1.0)], RULE[er.BASELINE])[0] == "STOP"


def test_exit_forward_test_is_blind_then_decides_on_exactly_n_trades():
    h = er.FORWARD_TESTS[0]
    reg = datetime.fromisoformat(h["registered_at"])
    def trade(i, dip):
        opened = (reg + timedelta(minutes=i)).isoformat()
        return {"id": i, "token": f"t{i}", "token_address": f"a{i}", "opened_at": opened, "entry_price": 1.01,
                "actual_reason": None, "actual_net_return_pct": None,
                "path": [(30, dip), (1200, .80 if dip < .97 else 1.0)]}   # dips keep falling; the rest recover
    paths = [trade(i, .95 if i % 3 == 0 else .99) for i in range(h["decide_at_trades"] - 1)]
    results, _ = er.replay(paths)
    r = er.forward_tests(paths, results)[0]
    assert r["verdict"].startswith("blind") and "rule_result" not in r
    paths.append(trade(1000, .95))
    paths.append({**trade(-1, .95), "opened_at": (reg - timedelta(hours=1)).isoformat()})  # before registration
    results, _ = er.replay(paths)
    r = er.forward_tests(paths, results)[0]
    assert r["rule_result"]["n"] == h["decide_at_trades"] and r["verdict"].startswith("SUPPORTED"), r
