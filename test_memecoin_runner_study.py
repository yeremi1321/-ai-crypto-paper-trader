"""Runner study: census, wider-stop replay, re-entry policies, holdout discipline, endpoint read-only."""
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
import memecoin_runner_study as rs
from memecoin_paper import migrate
from memecoin_shadow import init_db

T0 = datetime(2026, 9, 26, 10, 0, tzinfo=timezone.utc)   # inside the one-position-per-token era


def iso(sec):
    return (T0 + timedelta(seconds=sec)).isoformat()


class DB:
    def __init__(self, path):
        self.c = init_db(path); migrate(self.c); self.cid = 0
        self.c.execute("""CREATE TABLE IF NOT EXISTS meme_price_snapshots(id INTEGER PRIMARY KEY AUTOINCREMENT,observed_at TEXT NOT NULL,
            token_address TEXT NOT NULL,pair_address TEXT,price REAL NOT NULL,liquidity_usd REAL,volume_1h_usd REAL)""")

    def trade(self, tok, opened, closed, entry_mkt, exit_mkt, reason):
        self.cid += 1
        net = er.net_return_pct(entry_mkt * 1.01, exit_mkt)
        self.c.execute("""INSERT INTO meme_paper_trades(candidate_id,token,token_address,opened_at,entry_market_price,entry_price,
            quantity,entry_fee,status,closed_at,exit_market_price,exit_reason,net_return_pct,net_pnl_usd,mfe_pct,mae_pct)
            VALUES(?,?,?,?,?,?,1,.6,'CLOSED',?,?,?,?,?,0,0)""",
                       (self.cid, tok, tok, iso(opened), entry_mkt, entry_mkt * 1.01, iso(closed), exit_mkt, reason, net, net))

    def snap(self, tok, sec, price):
        self.c.execute("INSERT INTO meme_price_snapshots(observed_at,token_address,price) VALUES(?,?,?)", (iso(sec), tok, price))

    def close(self):
        self.c.commit(); self.c.close()


def _stops_db(path, holdout_edge):
    """Each token dips -12% then rallies. A wider stop survives the dip - unless the holdout dip keeps going."""
    db = DB(path); n = 20; cut = int(n * rs.TRAIN_FRACTION)
    for i in range(n):
        tok = f"S{i:02d}"; start = i * 3000
        edge = i < cut or holdout_edge
        path = [(30, 0.88), (60, 0.95), (90, 1.30), (1200, 1.30)] if edge else [(30, 0.88), (60, 0.80), (1200, 0.80)]
        for s, p in path:
            db.snap(tok, start + s, p)
        db.trade(tok, start, start + 30, 1.0, 0.88, "STOP_10")
    db.close()


def _reentry_db(path, holdout_reentries_win):
    """Each token: a stop, then two quick re-entries. They lose in training; in holdout they may win."""
    db = DB(path); n = 20; cut = int(n * rs.TRAIN_FRACTION)
    for i in range(n):
        tok = f"R{i:02d}"; start = i * 3000
        db.trade(tok, start, start + 60, 1.0, 0.88, "STOP_10")
        win = i >= cut and holdout_reentries_win
        for k in (1, 2):
            o = start + k * 120
            db.trade(tok, o, o + 60, 1.0, 1.25 if win else 0.88, "TARGET_20" if win else "STOP_10")
    db.close()


def _run(path):
    c = init_db(path); out = rs.run(c, "now"); c.close(); json.dumps(out); return out


def test_keep_trades_policies():
    t = lambda o, c, r: (0, 0, "X", "x", iso(o), iso(c), 1.0, 1.0, r, 0.0, 0.0, 0, 0)
    ts = [t(0, 60, "STOP_10"), t(120, 180, "STOP_10"), t(240, 300, "TARGET_20"), t(360, 420, "STOP_10"), t(1500, 1560, "STOP_10")]
    assert len(rs.keep_trades(ts, ("all", 0))) == 5
    assert len(rs.keep_trades(ts, ("first_only", 0))) == 1
    assert len(rs.keep_trades(ts, ("halt_after_stops", 1))) == 1
    assert len(rs.keep_trades(ts, ("halt_after_stops", 2))) == 2
    assert len(rs.keep_trades(ts, ("halt_after_stops", 3))) == 5          # target resets the streak
    kept = rs.keep_trades(ts, ("cooldown_min", 5))                       # skips re-entries within 5 min of a stop
    assert [x[4] for x in kept] == [iso(0), iso(360), iso(1500)]


def test_census_finds_runner_the_bot_lost_on():
    with tempfile.TemporaryDirectory() as d:
        path = str(Path(d) / "c.db"); db = DB(path)
        for s, p in [(0, 1.0), (60, 1.5), (200, 2.2), (400, 3.0)]:
            db.snap("RUN", s, p)
        db.trade("RUN", 0, 30, 1.0, 0.88, "STOP_10")
        db.trade("RUN", 100, 130, 1.6, 1.4, "STOP_10")
        db.trade("RUN", 300, 400, 2.4, 3.0, "TARGET_20")
        for s, p in [(5000, 1.0), (5100, 1.1)]:
            db.snap("FLAT", s, p)
        db.trade("FLAT", 5000, 5100, 1.0, 0.88, "STOP_10")
        # a stacked-era trade must be ignored entirely
        db.c.execute("""INSERT INTO meme_paper_trades(candidate_id,token,token_address,opened_at,entry_market_price,entry_price,
            quantity,entry_fee,status,closed_at,exit_market_price,exit_reason,net_return_pct,net_pnl_usd)
            VALUES(99,'OLD','OLD','2026-09-26T03:00:00+00:00',1,1.01,1,.6,'CLOSED','2026-09-26T03:01:00+00:00',.9,'STOP_10',-11,-11)""")
        db.close()
        out = _run(path)
    assert out["trades_used"] == 4 and out["tokens_used"] == 2
    ce = out["census"]
    assert ce["runners"]["tokens"] == 1 and ce["other_tokens"]["tokens"] == 1
    lost = ce["runners_bot_lost_money_on"]
    assert [r["token"] for r in lost] == ["RUN"] and lost[0]["run_up_pct"] == 200.0 and lost[0]["stops"] == 2


def test_wider_stop_found_only_when_it_survives_holdout():
    with tempfile.TemporaryDirectory() as d:
        g = str(Path(d) / "g.db"); _stops_db(g, holdout_edge=True); good = _run(g)["wider_stops"]
        b = str(Path(d) / "b.db"); _stops_db(b, holdout_edge=False); bad = _run(b)["wider_stops"]
    assert good["trades_replayed"] == 20 and good["trades_excluded_incomplete_path"] == 0
    assert good["chosen_on_train"] != er.BASELINE and good["verdict"].startswith("candidate"), good["verdict"]
    assert good["all"][er.BASELINE]["holdout"]["avg_net_return_pct"] < 0                    # live rule stops out on the dip
    assert bad["chosen_on_train"] == good["chosen_on_train"]                                  # same train data, same choice
    assert bad["verdict"].startswith("not promotable"), bad["verdict"]


def test_reentry_policy_found_only_when_it_survives_holdout():
    with tempfile.TemporaryDirectory() as d:
        g = str(Path(d) / "g.db"); _reentry_db(g, holdout_reentries_win=False); good = _run(g)["reentry_policy"]
        b = str(Path(d) / "b.db"); _reentry_db(b, holdout_reentries_win=True); bad = _run(b)["reentry_policy"]
    assert good["chosen_on_train"] != rs.LIVE_POLICY
    assert good["chosen"]["holdout"]["pnl_per_token_usd"] > good["live"]["holdout"]["pnl_per_token_usd"]
    assert good["verdict"].startswith("improves"), good["verdict"]          # fewer losses, but still not profitable
    assert bad["verdict"].startswith("not promotable"), bad["verdict"]      # skipping winners in holdout


def test_endpoint_read_only_and_cached():
    import research_worker as rw
    import memecoin_shadow
    assert "/paper-runner-study" in rw.PATHS
    with tempfile.TemporaryDirectory() as d:
        path = str(Path(d) / "e.db"); _reentry_db(path, holdout_reentries_win=False)
        real_init = memecoin_shadow.init_db
        rw._results.clear()
        before = Path(path).read_bytes()
        with patch.object(memecoin_shadow, "init_db", lambda p=None: real_init(path)):
            jobs = rw.default_jobs()
            list(rw.run_once({"runner_study": jobs["runner_study"]}))
        after = Path(path).read_bytes()
        server = HTTPServer(("127.0.0.1", 0), fc.Health)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        r = json.load(urllib.request.urlopen(f"http://127.0.0.1:{server.server_address[1]}/paper-runner-study?v=3"))
        server.shutdown()
    assert before == after, "research must not modify the database"
    assert r["mode"] == "read_only_runner_study" and r["trades_used"] == 60 and "_computed_at" in r


if __name__ == "__main__":
    test_keep_trades_policies()
    test_census_finds_runner_the_bot_lost_on()
    test_wider_stop_found_only_when_it_survives_holdout()
    test_reentry_policy_found_only_when_it_survives_holdout()
    test_endpoint_read_only_and_cached()
    print("runner study tests passed")
