"""Background research worker (instant pages, fail-safe) and pre-registered hypothesis verdicts."""
import json
import tempfile
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from http.server import HTTPServer
from pathlib import Path
from unittest.mock import patch

import memecoin_candidate_study as cs
import memecoin_fast_collector as fc
import research_worker as rw
import memecoin_shadow as ms
from memecoin_paper import migrate


def reset():
    rw._results.clear(); rw._started = False


def test_warming_up_then_instant_and_fail_safe():
    reset()
    payload, code = rw.get("/paper-candidate-study")
    assert code == 503 and payload["status"] == "warming_up"
    calls = {"n": 0}
    def study():
        calls["n"] += 1
        if calls["n"] > 1:
            raise RuntimeError("db hiccup")
        return {"/paper-candidate-study": {"mode": "x", "n": 1}}
    list(rw.run_once({"candidate_study": study}))
    payload, code = rw.get("/paper-candidate-study")
    assert code == 200 and payload["n"] == 1 and "_computed_at" in payload
    list(rw.run_once({"candidate_study": study}))  # second run fails
    payload, code = rw.get("/paper-candidate-study")
    assert code == 200 and payload["n"] == 1, "a failed refresh keeps serving the last good result"


def test_background_thread_serves_while_computing():
    reset()
    started = threading.Event(); release = threading.Event()
    def slow():
        started.set(); release.wait(5)
        return {"/paper-exit-replay": {"mode": "replay"}}
    first = {"quick": lambda: {"/paper-analysis": {"mode": "a"}, "/paper-analysis-trades": {"rows": []}}}
    list(rw.run_once(first))
    stop = threading.Event()
    rw.start({"quick": first["quick"], "slow": slow}, interval=60, gap=0, startup_delay=0, stop=stop)
    assert started.wait(3)
    t0 = time.monotonic(); payload, code = rw.get("/paper-analysis")
    assert code == 200 and time.monotonic() - t0 < 0.05, "pages answer instantly while a job is running"
    release.set(); time.sleep(0.2); stop.set()
    assert rw.get("/paper-exit-replay")[1] == 200


def test_http_route_uses_cache_and_never_computes_on_request():
    reset()
    list(rw.run_once({"s": lambda: {"/paper-candidate-study": {"mode": "read_only_candidate_study"}}}))
    def must_not_run(*a, **k):
        raise AssertionError("request path must not compute")
    with patch.object(fc.memecoin_candidate_study, "run", must_not_run):
        server = HTTPServer(("127.0.0.1", 0), fc.Health)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        base = f"http://127.0.0.1:{server.server_address[1]}"
        got = json.load(urllib.request.urlopen(base + "/paper-candidate-study?v=9"))
        try:
            urllib.request.urlopen(base + "/paper-exit-replay")
            raised = None
        except urllib.error.HTTPError as e:
            raised = e.code
        server.shutdown()
    assert got["mode"] == "read_only_candidate_study"
    assert raised == 503, "not computed yet -> warming up, not a slow on-demand compute"


def _db(path, n, reg_time, frenzy_wins):
    c = ms.init_db(path); migrate(c)
    c.execute("""CREATE TABLE IF NOT EXISTS meme_price_snapshots(id INTEGER PRIMARY KEY AUTOINCREMENT,observed_at TEXT NOT NULL,
        token_address TEXT NOT NULL,pair_address TEXT,price REAL NOT NULL,liquidity_usd REAL,volume_1h_usd REAL)""")
    start = datetime.fromisoformat(reg_time).replace(tzinfo=timezone.utc)
    # a few tokens BEFORE registration that would contradict the hypothesis: must be ignored
    for i in range(-10, n):
        tok = f"H{i + 10:03d}"; seen = start + timedelta(minutes=30 * i + 1)
        calm = i % 2 == 0
        good = (not calm) if (i < 0 or frenzy_wins) else calm
        x = {"token": tok, "token_address": tok, "price_usd": 1.0, "liquidity_usd": 80000,
             "attn_buy_ratio_5m": 0.5 if calm else 0.8, "sol_ret_60m_pct": 0.0}
        c.execute("""INSERT INTO meme_candidates(seen_at,version,token,chain,score,eligible,blocked_reasons,raw_json,token_address)
            VALUES(?,?,?,?,?,?,?,?,?)""", (seen.isoformat(), "V", tok, "solana", 70, 1, "[]", json.dumps(x), tok))
        for s, p in ([(30, 1.1), (60, 1.25)] if good else [(30, 0.95), (60, 0.7)]):
            c.execute("INSERT INTO meme_price_snapshots(observed_at,token_address,price,liquidity_usd) VALUES(?,?,?,?)",
                      ((seen + timedelta(seconds=s)).isoformat(), tok, p, 80000))
    c.commit(); return c


def _verdict(out, name):
    return next(h for h in out["preregistered_hypotheses"] if h["name"] == name)


def test_preregistered_verdicts():
    reg = next(h["registered_at"] for h in cs.HYPOTHESES if h["name"] == "anti_frenzy_buy_ratio_5m")
    with tempfile.TemporaryDirectory() as d:
        c = _db(str(Path(d) / "a.db"), 20, reg, frenzy_wins=False); few = cs.run(c, "now"); c.close()
        c = _db(str(Path(d) / "b.db"), 80, reg, frenzy_wins=False); yes = cs.run(c, "now"); c.close()
        c = _db(str(Path(d) / "c.db"), 80, reg, frenzy_wins=True); no = cs.run(c, "now"); c.close()
    h = _verdict(few, "anti_frenzy_buy_ratio_5m")
    assert h["tokens_evaluated"] == 20, "tokens before registration are ignored"
    assert h["verdict"].startswith("collecting")
    assert _verdict(yes, "anti_frenzy_buy_ratio_5m")["verdict"].startswith("SUPPORTED")
    assert _verdict(no, "anti_frenzy_buy_ratio_5m")["verdict"].startswith("REJECTED")
    json.dumps(yes)


def test_young_pairs_uses_age_at_discovery():
    """pair_age_min = discovery time - pair creation; young pairs win after registration, old ones lose."""
    reg = next(h["registered_at"] for h in cs.HYPOTHESES if h["name"] == "young_pairs_30m")
    start = datetime.fromisoformat(reg).replace(tzinfo=timezone.utc)
    with tempfile.TemporaryDirectory() as d:
        c = ms.init_db(str(Path(d) / "y.db")); migrate(c)
        c.execute("""CREATE TABLE IF NOT EXISTS meme_price_snapshots(id INTEGER PRIMARY KEY AUTOINCREMENT,observed_at TEXT NOT NULL,
            token_address TEXT NOT NULL,pair_address TEXT,price REAL NOT NULL,liquidity_usd REAL,volume_1h_usd REAL)""")
        for i in range(-6, 70):
            tok = f"Y{i + 6:03d}"; seen = start + timedelta(minutes=20 * i + 1)
            young = i % 2 == 0
            age_min = 10 if young else 120
            good = young if i >= 0 else not young   # before registration the opposite holds; must be ignored
            x = {"token": tok, "token_address": tok, "price_usd": 1.0, "liquidity_usd": 80000,
                 "pair_created_at": (seen.timestamp() - age_min * 60) * 1000}
            c.execute("""INSERT INTO meme_candidates(seen_at,version,token,chain,score,eligible,blocked_reasons,raw_json,token_address)
                VALUES(?,?,?,?,?,?,?,?,?)""", (seen.isoformat(), "V", tok, "solana", 70, 1, "[]", json.dumps(x), tok))
            for s, p in ([(30, 1.1), (60, 1.25)] if good else [(30, 0.95), (60, 0.7)]):
                c.execute("INSERT INTO meme_price_snapshots(observed_at,token_address,price,liquidity_usd) VALUES(?,?,?,?)",
                          ((seen + timedelta(seconds=s)).isoformat(), tok, p, 80000))
        c.commit(); out = cs.run(c, "now"); c.close()
    h = _verdict(out, "young_pairs_30m")
    assert h["tokens_evaluated"] == 70, h["tokens_evaluated"]
    assert h["kept"]["n"] == 35 and h["verdict"].startswith("SUPPORTED"), h["verdict"]


if __name__ == "__main__":
    test_warming_up_then_instant_and_fail_safe()
    test_background_thread_serves_while_computing()
    test_http_route_uses_cache_and_never_computes_on_request()
    test_preregistered_verdicts()
    test_young_pairs_uses_age_at_discovery()
    print("research worker + preregistration tests passed")
