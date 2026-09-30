"""Backup/restore round trip and the health check the watchdog relies on."""
import gzip
import json
from datetime import datetime, timedelta, timezone

import pytest

import memecoin_backup as mb
import memecoin_fast_collector as fc
import memecoin_paper
import memecoin_predictor as mp
from memecoin_shadow import init_db

NOW = datetime(2026, 9, 30, 12, tzinfo=timezone.utc)


def source():
    c = init_db(":memory:"); memecoin_paper.migrate(c); mp.init(c)
    for i, status in ((5, "CLOSED"), (9, "OPEN")):
        c.execute("INSERT INTO meme_paper_trades(candidate_id,token,opened_at,status,net_return_pct) VALUES(?,?,?,?,?)",
                  (i, f"T{i}", NOW.isoformat(), status, 12.5 if status == "CLOSED" else None))
    for i, days in ((5, 1), (7, 10)):
        c.execute("INSERT INTO meme_predictions(candidate_id,predicted_at,status,features_json) VALUES(?,?,?,?)",
                  (i, (NOW - timedelta(days=days)).isoformat(), "RESOLVED", '{"x": 1}'))
    m = mp.Model(); m.n = 42; m.outcome_rules = mp.OUTCOME_RULES; m.severe = mp.Model(prior=mp.PRIOR_SEVERE_RATE)
    c.execute("INSERT INTO meme_predictor_state(id,updated_at,state_json) VALUES(1,?,?)", (NOW.isoformat(), json.dumps(m.state())))
    c.commit()
    return c


def test_round_trip_restores_closed_trades_predictions_and_state(tmp_path):
    data = json.loads(json.dumps(mb.export(source(), NOW)))  # must survive JSON
    fi = data["predictions"]["columns"].index("features_json")
    assert [r[fi] for r in data["predictions"]["rows"]] == ['{"x": 1}', None]  # old features dropped
    path = tmp_path / "b.json.gz"
    with gzip.open(path, "wt") as f:
        json.dump(data, f)
    c = init_db(":memory:")
    out = mb.restore_if_fresh(c, str(path))
    assert out == {"paper_trades": 1, "predictions": 2, "candidate_stubs": 2}  # open position not restored
    assert c.execute("SELECT net_return_pct FROM meme_paper_trades").fetchone()[0] == 12.5
    assert mp.load_model(c).n == 42
    c.execute("INSERT INTO meme_candidates(seen_at) VALUES('x')")
    assert c.execute("SELECT MAX(id) FROM meme_candidates").fetchone()[0] == 8  # new ids start above every restored id
    assert mb.restore_if_fresh(c, str(path)) is None  # never restores twice


def test_refuses_to_restore_over_live_data():
    c = init_db(":memory:")
    c.execute("INSERT INTO meme_candidates(seen_at) VALUES('x')"); c.commit()
    with pytest.raises(RuntimeError):
        mb.restore(c, mb.export(source(), NOW))


def test_healthz_reports_database_and_stalled_discovery(monkeypatch):
    monkeypatch.setattr(fc, "init_db", lambda: init_db(":memory:"))
    monkeypatch.setitem(fc.STATE, "last_discovery", datetime.now(timezone.utc).isoformat())
    assert fc.healthz() == (True, [])
    monkeypatch.setitem(fc.STATE, "last_discovery", (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat())
    assert fc.healthz() == (False, ["discovery stalled"])
    def broken():
        raise OSError("no space left on device")
    monkeypatch.setattr(fc, "init_db", broken)
    ok, reasons = fc.healthz()
    assert not ok and reasons[0] == "database: OSError"
