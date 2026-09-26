"""Open paper positions must refresh independently of slow discovery."""
import sqlite3
import tempfile
import threading
import time
from datetime import datetime, timezone, timedelta
from pathlib import Path
from unittest.mock import patch

import memecoin_fast_collector as fc
import memecoin_outcomes
import memecoin_paper
from memecoin_shadow import init_db


def test_open_refresh_not_blocked_by_slow_discovery():
    calls = {"open": [], "full": [], "paper": 0}
    discovery_running = threading.Event()

    def slow_scan(limit):
        discovery_running.set()
        time.sleep(1.0)

    def fake_outcomes(only_open=False, exclude_open=False):
        (calls["open"] if only_open else calls["full"]).append((time.monotonic(), exclude_open))

    def fake_paper():
        calls["paper"] += 1

    stop = threading.Event()
    with patch.object(fc, "scan", slow_scan), \
         patch.object(fc, "update_outcomes", fake_outcomes), \
         patch.object(fc, "paper_run", fake_paper):
        t1 = threading.Thread(target=fc.collector, args=(stop,), daemon=True)
        t2 = threading.Thread(target=fc.open_position_watcher, args=(stop, 0.1), daemon=True)
        t1.start(); t2.start()
        assert discovery_running.wait(2)
        started = time.monotonic()
        time.sleep(0.9)
        during = [t for t, _ in calls["open"] if t >= started]
        stop.set(); t1.join(3); t2.join(3)

    assert len(during) >= 5, f"open refresh starved during discovery: {len(during)} runs"
    assert calls["paper"] >= len(calls["open"]) - 1
    assert all(excl for _, excl in calls["full"])


def test_full_refresh_skips_open_positions():
    with tempfile.TemporaryDirectory() as directory:
        path = str(Path(directory) / "paper.db")
        now = datetime.now(timezone.utc).isoformat()
        conn = init_db(path)
        conn.execute("INSERT INTO meme_outcomes(candidate_id,token_address,detected_at,entry_price,highest_price,lowest_price) VALUES(1,'held',?,1,1,1)", (now,))
        conn.execute("INSERT INTO meme_outcomes(candidate_id,token_address,detected_at,entry_price,highest_price,lowest_price) VALUES(2,'watching',?,1,1,1)", (now,))
        conn.execute("""INSERT INTO meme_paper_trades(candidate_id,token_address,opened_at,entry_price,status,highest_price,lowest_price,current_price)
            VALUES(1,'held',?,1,'OPEN',1,1,1)""", (now,))
        conn.commit(); conn.close()
        called = []

        def quote(address):
            called.append(address)
            return {"priceUsd": "1.05", "pairAddress": "pair", "liquidity": {"usd": 50000}}

        with patch.object(memecoin_outcomes, "init_db", lambda: init_db(path)), \
             patch.object(memecoin_outcomes, "best_pair", quote), \
             patch.object(memecoin_outcomes.time, "sleep"):
            memecoin_outcomes.run(exclude_open=True)
            assert sorted(called) == ["watching"]
            called.clear()
            memecoin_outcomes.run()
            assert sorted(called) == ["held", "watching"]


class _StaleReader:
    """Replay a SELECT captured before another caller closed the row."""
    def __init__(self, conn, stale_rows):
        self.conn, self.stale_rows = conn, stale_rows
    def execute(self, sql, *args):
        if sql.lstrip().upper().startswith("SELECT ID,CANDIDATE_ID"):
            rows = self.stale_rows
            class _Cur:
                def fetchall(self_inner): return rows
            return _Cur()
        return self.conn.execute(sql, *args)
    def commit(self):
        self.conn.commit()


def test_close_is_idempotent_across_callers():
    conn = init_db(":memory:"); memecoin_paper.migrate(conn)
    opened = (datetime.now(timezone.utc) - timedelta(minutes=2)).isoformat()
    conn.execute("""INSERT INTO meme_paper_trades(candidate_id,token,token_address,pair_address,opened_at,
        entry_market_price,entry_price,notional_usd,quantity,entry_fee,status,highest_price,lowest_price,
        current_price,current_return_pct,mfe_pct,mae_pct) VALUES(7,'RUG','a','p',?,1,1,100,99.4,.6,'OPEN',1,.8,.8,-20,0,-20)""", (opened,))
    conn.execute("INSERT INTO meme_decision_ledger(candidate_id,outcome_label) VALUES(7,'PENDING')"); conn.commit()
    stale = conn.execute("""SELECT id,candidate_id,token,entry_price,quantity,entry_fee,opened_at,current_price,
        highest_price,lowest_price FROM meme_paper_trades WHERE status='OPEN' ORDER BY id""").fetchall()
    first_now = datetime.now(timezone.utc)
    first = memecoin_paper.close_positions(conn, first_now)
    assert [x[1] for x in first] == ["STOP_10"]
    closed_at = conn.execute("SELECT closed_at FROM meme_paper_trades").fetchone()[0]
    second = memecoin_paper.close_positions(_StaleReader(conn, stale), first_now + timedelta(seconds=10))
    assert second == [], "a second caller must not re-close a CLOSED trade"
    assert conn.execute("SELECT closed_at FROM meme_paper_trades").fetchone()[0] == closed_at
    assert conn.execute("SELECT COUNT(*) FROM meme_paper_trades WHERE status='CLOSED'").fetchone()[0] == 1


if __name__ == "__main__":
    test_open_refresh_not_blocked_by_slow_discovery()
    test_full_refresh_skips_open_positions()
    test_close_is_idempotent_across_callers()
    print("open-position watcher tests passed")
