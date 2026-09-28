"""Predictor: no look-ahead, same exit semantics as the study, dedup, and learning."""
import json
import random
from datetime import datetime, timedelta, timezone

import memecoin_candidate_study as study
import memecoin_predictor as mp
from memecoin_shadow import init_db

T0 = datetime(2026, 9, 26, 6, 0, tzinfo=timezone.utc)


def db():
    c = init_db(":memory:")
    c.execute("CREATE TABLE meme_price_snapshots(id INTEGER PRIMARY KEY,observed_at TEXT,token_address TEXT,"
              "pair_address TEXT,price REAL,liquidity_usd REAL,volume_1h_usd REAL)")
    return c


def add(c, cid, at, tok, x=None, decision=None, path=()):
    x = {"token": tok, "token_address": tok, "price_usd": 1.0, "observed_at": at.isoformat(), **(x or {})}
    c.execute("INSERT INTO meme_candidates(id,seen_at,token,eligible,raw_json,token_address) VALUES(?,?,?,?,?,?)",
              (cid, at.isoformat(), tok, 1, json.dumps(x), tok))
    if decision:
        c.execute("INSERT INTO meme_decision_ledger(candidate_id,decision) VALUES(?,?)", (cid, decision))
    for sec, price in path:
        c.execute("INSERT INTO meme_price_snapshots(observed_at,token_address,price) VALUES(?,?,?)",
                  ((at + timedelta(seconds=sec)).isoformat(), tok, price))
    c.commit()


def test_outcome_matches_live_study_rule():
    rng = random.Random(3)
    for _ in range(300):
        t, path = 0, []
        while t < 1400:
            t += rng.randint(20, 400)
            path.append((t, rng.uniform(.8, 1.3)))
        path = [p for p in path if p[0] <= study.HORIZON_S + study.END_TOLERANCE_S]  # as study.build_rows loads it
        mine = mp.outcome(1.01, path, window_closed=True)
        ref = study.simulate_live(1.01, path)
        assert (mine is None) == (ref is None)
        if ref:
            assert mine[0] == ref[0] and abs(mine[1] - ref[1]) < 1e-9


def test_open_window_does_not_resolve_early():
    near_end = [(1150, 1.02)]
    assert mp.outcome(1.01, near_end, window_closed=False) is None
    assert mp.outcome(1.01, near_end, window_closed=True)[0] == "TIME"


def test_prediction_is_stored_before_outcome_and_resolves_later():
    c = db()
    add(c, 1, T0, "a", path=[(300, 1.5)])
    r = mp.step(c, T0 + timedelta(seconds=60))
    assert r["predicted"] == 1 and r["resolved"] == 0
    assert c.execute("SELECT status FROM meme_predictions").fetchone()[0] == "PENDING"
    r = mp.step(c, T0 + timedelta(minutes=10))
    assert r["resolved"] == 1
    row = c.execute("SELECT status,actual_reason,won FROM meme_predictions").fetchone()
    assert row == ("RESOLVED", "TARGET", 1)
    assert mp.load_model(c).n == 1


def test_no_quotes_becomes_unresolvable_without_learning():
    c = db()
    add(c, 1, T0, "a")
    mp.step(c, T0 + timedelta(minutes=5))
    assert mp.step(c, T0 + timedelta(hours=1))["unresolvable"] == 1
    assert mp.load_model(c).n == 0


def test_repeat_observation_skipped_unless_bot_traded():
    c = db()
    add(c, 1, T0, "a")
    add(c, 2, T0 + timedelta(minutes=2), "a")
    add(c, 3, T0 + timedelta(minutes=3), "a", decision=mp.TRADED)
    add(c, 4, T0 + timedelta(minutes=25), "a")
    mp.step(c, T0 + timedelta(minutes=30))
    assert [r[0] for r in c.execute("SELECT candidate_id FROM meme_predictions ORDER BY candidate_id")] == [1, 3, 4]


def test_backfill_learns_only_from_outcomes_known_at_prediction_time():
    c = db()
    add(c, 1, T0, "a", path=[(600, 1.5)])            # decided at +10 min
    add(c, 2, T0 + timedelta(minutes=5), "b")         # predicted before a's outcome existed
    add(c, 3, T0 + timedelta(minutes=15), "c")        # predicted after
    mp.catch_up(c, T0 + timedelta(minutes=16))
    upd = dict(c.execute("SELECT candidate_id,model_updates FROM meme_predictions"))
    assert upd == {1: 0, 2: 0, 3: 1}


def test_learns_a_real_signal_and_reports():
    c = db()
    for i in range(150):
        good = i % 3 == 0
        add(c, i + 1, T0 + timedelta(minutes=i), f"t{i}", {"volume_accel": 6 if good else .3},
            path=[(240, 1.4 if good else .8)])
    mp.catch_up(c, T0 + timedelta(hours=4))
    rep = mp.report(c)
    assert rep["counts"]["resolved"] == 150
    assert rep["model"]["top_positive_signals"][0]["feature"] == "volume_accel"
    assert rep["accuracy"]["skill_vs_baseline_pct"] > 0
    assert rep["policies"]["predictor_picks"]["win_rate_pct"] > rep["policies"]["buy_every_discovery"]["win_rate_pct"]
    assert rep["suggestions"]
