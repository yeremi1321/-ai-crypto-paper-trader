"""Candidate study: live-rule parity, gate audit, feature holdout discipline, endpoint read-only."""
import json
import tempfile
import threading
import urllib.request
from datetime import datetime, timedelta, timezone
from http.server import HTTPServer
from pathlib import Path
from unittest.mock import patch

import memecoin_candidate_study as cs
import memecoin_fast_collector as fc
from memecoin_paper import migrate
from memecoin_shadow import init_db

T0 = datetime(2026, 9, 26, 3, 0, tzinfo=timezone.utc)


def iso(sec):
    return (T0 + timedelta(seconds=sec)).isoformat()


def _db(path, n=40, feature_edge_in_holdout=True):
    """Tokens with odd 'volume_accel' rise to +25%; even ones fall to -30%. Low-liquidity tokens are blocked.
    If feature_edge_in_holdout is False, the relationship flips for the newest 30% of tokens."""
    c = init_db(path); migrate(c)
    c.execute("""CREATE TABLE IF NOT EXISTS meme_price_snapshots(id INTEGER PRIMARY KEY AUTOINCREMENT,observed_at TEXT NOT NULL,
        token_address TEXT NOT NULL,pair_address TEXT,price REAL NOT NULL,liquidity_usd REAL,volume_1h_usd REAL)""")
    cut = int(n * cs.TRAIN_FRACTION)
    for i in range(n):
        tok = f"T{i:02d}"; start = i * 3000
        hot = i % 2 == 1
        good = hot if (i < cut or feature_edge_in_holdout) else not hot
        liq = 10000 if i % 5 == 0 else 60000
        blocked = ["LOW_LIQUIDITY"] if liq < 30000 else []
        x = {"token": tok, "token_address": tok, "price_usd": 1.0, "liquidity_usd": liq,
             "volume_accel": 3.0 if hot else 1.0, "makers": 500, "higher_highs": True}
        for k in range(2):  # repeated observations: only the first should be used
            c.execute("""INSERT INTO meme_candidates(seen_at,version,token,chain,score,eligible,blocked_reasons,raw_json,token_address)
                VALUES(?,?,?,?,?,?,?,?,?)""", (iso(start + k * 30), "V", tok, "solana", 70, int(not blocked),
                                               json.dumps(blocked), json.dumps(x), tok))
        path = [(30, 1.1), (60, 1.25)] if good else [(30, 0.95), (60, 0.70)]
        for s, p in path:
            c.execute("INSERT INTO meme_price_snapshots(observed_at,token_address,price) VALUES(?,?,?)", (iso(start + s), tok, p))
    c.execute("""INSERT INTO meme_paper_trades(candidate_id,token,token_address,opened_at,entry_price,status)
        VALUES(1,'T01','T01',?,1.01,'CLOSED')""", (iso(0),))
    c.commit(); c.close()


def test_live_rule_parity():
    assert cs.simulate_live(1.01, [(30, 0.90)])[0] == "STOP"
    assert cs.simulate_live(1.01, [(30, 1.22)])[0] == "TARGET"
    assert cs.simulate_live(1.01, [(30, 1.05)]) is None
    assert cs.simulate_live(1.01, [(1200, 1.03)])[0] == "TIME"
    assert abs(cs.net_return_pct(1.01, 1.212) - 17.3786768) < 1e-6  # same figure as the live paper engine


def test_gate_audit_and_first_observation_only():
    with tempfile.TemporaryDirectory() as d:
        path = str(Path(d) / "c.db"); _db(path)
        c = init_db(path); out = cs.run(c, "now"); c.close()
    assert out["tokens_discovered"] == 40 and out["tokens_studied"] == 40
    ga = out["gate_audit"]
    assert ga["blocked_by_any_gate"]["n"] == 8 and "LOW_LIQUIDITY" in ga["by_gate"]
    assert ga["tokens_the_bot_actually_traded"]["n"] == 1
    json.dumps(out)


def test_feature_edge_found_only_when_it_survives_holdout():
    with tempfile.TemporaryDirectory() as d:
        good = str(Path(d) / "g.db"); _db(good, feature_edge_in_holdout=True)
        c = init_db(good); a = cs.run(c, "now"); c.close()
        bad = str(Path(d) / "b.db"); _db(bad, feature_edge_in_holdout=False)
        c = init_db(bad); b = cs.run(c, "now"); c.close()
    assert any("volume_accel >" in x for x in a["feature_test"]["candidates"]), a["feature_test"]["candidates"]
    assert not any("volume_accel" in x for x in b["feature_test"]["candidates"]), b["feature_test"]["candidates"]


def test_endpoint_read_only_and_cached():
    with tempfile.TemporaryDirectory() as d:
        path = str(Path(d) / "e.db"); _db(path)
        calls = []; real = cs.run
        fc._STUDY.update(at=0.0, result=None)
        with patch.object(fc, "init_db", lambda: init_db(path)), \
             patch.object(fc.memecoin_candidate_study, "run", lambda c, a: (calls.append(1), real(c, a))[1]):
            server = HTTPServer(("127.0.0.1", 0), fc.Health)
            threading.Thread(target=server.serve_forever, daemon=True).start()
            url = f"http://127.0.0.1:{server.server_address[1]}/paper-candidate-study"
            before = Path(path).read_bytes()
            r = json.load(urllib.request.urlopen(url)); json.load(urllib.request.urlopen(url))
            server.shutdown()
            assert Path(path).read_bytes() == before
    assert r["mode"] == "read_only_candidate_study" and len(calls) == 1


def test_liquidity_aware_costs():
    assert cs.impact(2.67) == 0.5 and abs(cs.impact(100000) - 0.002) < 1e-12
    flat = cs.simulate_live(1.01, [(30, 1.25, 60000)])[1]
    thin = cs.simulate_live(1.01 * (1 + cs.impact(300)) , [(30, 1.25 * 1.0, 300)], lambda l: cs.SLIP + cs.impact(l))
    assert thin is None or thin[1] < flat  # thin pool: target may not even trigger; if it does, it pays far more
    with tempfile.TemporaryDirectory() as d:
        path = str(Path(d) / "l.db"); _db(path)
        c = init_db(path); out = cs.run(c, "now"); c.close()
    assert out["entry_liquidity_usd"]["pct_at_least_20k"] == 80.0
    assert out["realistic_pools_only"]["all"]["n"] == 32
    la = out["liquidity_aware"]["gate_audit"]["all_tokens"]["avg_net_return_pct"]
    assert la < out["gate_audit"]["all_tokens"]["avg_net_return_pct"]


if __name__ == "__main__":
    test_live_rule_parity()
    test_gate_audit_and_first_observation_only()
    test_feature_edge_found_only_when_it_survives_holdout()
    test_endpoint_read_only_and_cached()
    test_liquidity_aware_costs()
    print("candidate study tests passed")
