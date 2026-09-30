"""Retention: prunes bulk research data, never trades, predictions or first sightings."""
import json
from datetime import datetime, timedelta, timezone

import memecoin_paper
import memecoin_predictor as mp
import memecoin_retention as mr
from memecoin_outcomes import ensure_snapshot_table
from memecoin_shadow import init_db

NOW = datetime(2026, 9, 30, 12, tzinfo=timezone.utc)


def ago(days):
    return (NOW - timedelta(days=days)).isoformat()


def setup():
    c = init_db(":memory:"); memecoin_paper.migrate(c); ensure_snapshot_table(c); mp.init(c)
    rows = [  # id, seen_at, token
        (1, ago(10), "old"), (2, ago(9), "old"),        # first + repeat, old
        (3, ago(10), "traded"), (4, ago(9), "traded"),  # repeat 4 was traded
        (5, ago(0.1), "new"), (6, ago(0.05), "new"),    # recent repeat
    ]
    for cid, at, tok in rows:
        c.execute("INSERT INTO meme_candidates(id,seen_at,token_address,raw_json) VALUES(?,?,?,?)",
                  (cid, at, tok, json.dumps({"price_usd": 1})))
        c.execute("INSERT INTO meme_decision_ledger(candidate_id,recorded_at,raw_json) VALUES(?,?,?)", (cid, at, "{}"))
    c.execute("INSERT INTO meme_paper_trades(candidate_id,token_address,opened_at,status) VALUES(4,'traded',?,'CLOSED')",
              (ago(9),))
    c.execute("INSERT INTO meme_predictions(candidate_id,predicted_at,status) VALUES(2,?,'RESOLVED')", (ago(9),))
    for tok, days in (("old", 10), ("old", 1.5), ("traded", 10), ("traded", 40), ("new", 0.01)):
        c.execute("INSERT INTO meme_price_snapshots(observed_at,token_address,price) VALUES(?,?,1)", (ago(days), tok))
    c.commit()
    return c


def test_prunes_bulk_but_keeps_what_research_reads():
    c = setup()
    r = mr.run(c, NOW)
    kept = {r[0] for r in c.execute("SELECT id FROM meme_candidates WHERE raw_json IS NOT NULL")}
    assert kept == {1, 3, 4, 5, 6}  # first sightings, the traded sighting, recent repeats
    assert {r[0] for r in c.execute("SELECT id FROM meme_candidates")} == {1, 2, 3, 4, 5, 6}  # rows never deleted
    snaps = sorted((t, a) for t, a in c.execute("SELECT token_address,observed_at FROM meme_price_snapshots"))
    assert snaps == sorted([("old", ago(1.5)), ("traded", ago(10)), ("new", ago(0.01))])
    ledger = {r[0] for r in c.execute("SELECT candidate_id FROM meme_decision_ledger WHERE raw_json IS NOT NULL")}
    assert ledger == {4, 5, 6}
    assert c.execute("SELECT COUNT(*) FROM meme_paper_trades").fetchone()[0] == 1
    assert c.execute("SELECT COUNT(*) FROM meme_predictions").fetchone()[0] == 1
    assert r["snapshots_deleted"] == 2 and r["payloads_cleared"] == 1 and not r["tight_mode"]
    assert mr.run(c, NOW)["snapshots_deleted"] == 0  # idempotent


def test_tight_mode_when_database_is_large(monkeypatch):
    c = setup()
    monkeypatch.setattr(mr, "SOFT_LIMIT_BYTES", 1)
    r = mr.run(c, NOW)
    assert r["tight_mode"]
    assert c.execute("SELECT COUNT(*) FROM meme_price_snapshots WHERE token_address='old'").fetchone()[0] == 0


def test_empty_database_is_fine():
    c = init_db(":memory:")
    assert mr.run(c, NOW)["snapshots_deleted"] == 0
