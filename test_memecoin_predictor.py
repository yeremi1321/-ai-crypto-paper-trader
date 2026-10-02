"""Predictor: no look-ahead, same exit semantics as the study, dedup, and learning."""
import json
import math
import random
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


def test_report_served_by_background_research_worker():
    import research_worker as rw
    assert "/paper-predictions" in rw.PATHS
    assert "predictions" in rw.default_jobs()


def test_severe_head_learns_and_prices_tail_risk():
    c = db()
    for i in range(150):
        rug = i % 4 == 0
        add(c, i + 1, T0 + timedelta(minutes=i), f"t{i}", {"volume_accel": 8 if rug else 1},
            path=[(240, .6 if rug else .88)])  # rugs gap to -40%, the rest stop out near -12%
    mp.catch_up(c, T0 + timedelta(hours=4))
    m = mp.load_model(c)
    assert m.severe_n == 38 and m.avg_severe() < -40 < m.avg_mild_loss()
    rep = mp.report(c)
    assert rep["severe_loss"]["raises_risk"][0]["feature"] == "volume_accel"
    assert rep["severe_loss"]["accuracy"]["auc"] > .9
    rug, calm = {"volume_accel": math.log1p(8)}, {"volume_accel": math.log1p(1)}
    assert m.predict_all(rug)[1] > .5 > m.predict_all(calm)[1]
    assert m.predict_all(rug)[2] < m.predict_all(calm)[2]  # tail risk lowers expected return
    lessons = [r[0] for r in c.execute("SELECT lesson FROM meme_predictions WHERE lesson LIKE 'Severe loss%'")]
    assert lessons  # early rugs it did not yet see coming


def test_v1_history_is_upgraded_without_look_ahead():
    c = db()
    for i in range(80):
        add(c, i + 1, T0 + timedelta(minutes=i), f"t{i}", {"volume_accel": 8 if i % 4 == 0 else 1},
            path=[(240, .6 if i % 4 == 0 else 1.3)])
    mp.catch_up(c, T0 + timedelta(hours=3))
    # Make it look like a V1 database: no severe head, no severe columns filled.
    state = json.loads(c.execute("SELECT state_json FROM meme_predictor_state").fetchone()[0])
    for k in ("severe", "severe_n", "severe_sum"):
        state.pop(k)
    c.execute("UPDATE meme_predictor_state SET state_json=?", (json.dumps(state),))
    c.execute("UPDATE meme_predictions SET p_severe_loss=NULL,severe_loss=NULL,brier_severe=NULL")
    c.commit()
    m = mp.load_model(c)
    assert m.severe is not None and m.severe.n == 80 and m.severe_n == 20
    ps = [r[0] for r in c.execute("SELECT p_severe_loss FROM meme_predictions ORDER BY predicted_at")]
    assert None not in ps
    assert abs(ps[0] - mp.PRIOR_SEVERE_RATE) < 1e-9  # the first prediction knew nothing yet
    assert c.execute("SELECT COUNT(*) FROM meme_predictions WHERE severe_loss=1").fetchone()[0] == 20
    assert mp.load_model(c).severe.n == 80  # upgrade runs once


def _paper(c, cid, opened, net):
    c.execute("INSERT INTO meme_paper_trades(candidate_id,opened_at,status,net_return_pct) VALUES(?,?,?,?)",
              (cid, opened, "CLOSED", net))


def _pred(c, cid, at, p_sev):
    c.execute("INSERT INTO meme_predictions(candidate_id,predicted_at,p_win,p_severe_loss,status) VALUES(?,?,?,?,?)",
              (cid, at, .3, p_sev, "RESOLVED"))


def test_forward_test_only_uses_trades_after_registration_and_judges_them():
    import memecoin_paper
    c = db(); mp.init(c); memecoin_paper.migrate(c)
    reg = datetime.fromisoformat(mp.HYPOTHESES[0]["registered_at"])
    before = (reg - timedelta(hours=1)).isoformat()
    _pred(c, 1, before, .9); _paper(c, 1, before, -50)    # pre-registration: must be ignored
    rng = random.Random(1)
    for i in range(60):
        at = (reg + timedelta(minutes=i)).isoformat()
        risky = i % 4 == 0
        _pred(c, i + 2, at, .5 if risky else .1)
        _paper(c, i + 2, at, -35 + rng.uniform(-3, 3) if risky else rng.uniform(-8, 8))
    c.commit()
    h = mp.preregistered(c)[0]
    assert h["every_entry"]["trades"] == 60 and h["skipped"]["trades"] == 15
    assert h["verdict"].startswith("SUPPORTED"), h
    c2 = db(); mp.init(c2); memecoin_paper.migrate(c2)
    _pred(c2, 1, reg.isoformat(), .5); _paper(c2, 1, reg.isoformat(), -30); c2.commit()
    assert mp.preregistered(c2)[0]["verdict"].startswith("collecting")


def test_fixed_horizon_test_is_blind_until_decided_then_uses_exactly_n_trades():
    import memecoin_paper
    h = next(x for x in mp.HYPOTHESES if x.get("decide_at_trades"))
    n, reg = h["decide_at_trades"], datetime.fromisoformat(h["registered_at"])
    c = db(); mp.init(c); memecoin_paper.migrate(c)
    for i in range(n - 1):
        at = (reg + timedelta(minutes=i)).isoformat()
        _pred(c, i + 1, at, .5 if i % 4 == 0 else .1); _paper(c, i + 1, at, -30 if i % 4 == 0 else 1)
    c.commit()
    r = next(x for x in mp.preregistered(c) if x["name"] == h["name"])
    assert r["verdict"].startswith("blind") and "kept" not in r and r["trades_so_far"] == n - 1
    for i in range(n - 1, n + 20):  # later trades beyond the horizon must not count
        at = (reg + timedelta(minutes=i)).isoformat()
        _pred(c, i + 1, at, .1); _paper(c, i + 1, at, -90)
    c.commit()
    r = next(x for x in mp.preregistered(c) if x["name"] == h["name"])
    assert r["every_entry"]["trades"] == n and r["verdict"].startswith("SUPPORTED"), r


def test_isolated_spikes_are_ignored_but_real_moves_are_kept():
    up = [(30, 1.0), (60, 900.0), (90, 1.0)]
    down = [(30, 1.0), (60, .001), (90, 1.0)]
    rug = [(30, 1.0), (60, .05), (90, .04)]
    assert mp.despike(up) == [(30, 1.0), (90, 1.0)]
    assert mp.despike(down) == [(30, 1.0), (90, 1.0)]
    assert mp.despike(rug) == rug
    assert mp.outcome(1.01, rug, True)[0] == "STOP"


def test_target_fill_is_capped():
    cap = study.net_return_pct(1.0, 1 + mp.MAX_FILL_UP_PCT / 100)
    reason, net, _, _ = mp.outcome(1.0, [(60, 1500.0)], True)  # last quote, so despike cannot judge it
    assert reason == "TARGET" and abs(net - cap) < 1e-9
    assert mp.outcome(1.0, [(60, 1.3)], True)[1] < cap  # ordinary targets unchanged


def test_history_with_glitched_wins_is_repaired_once():
    c = db()
    for i in range(80):
        add(c, i + 1, T0 + timedelta(minutes=i), f"t{i}", path=[(240, 1.3 if i % 2 else .85)])
    mp.catch_up(c, T0 + timedelta(hours=3))
    c.execute("UPDATE meme_predictions SET actual_net_return_pct=150000 WHERE candidate_id=2")  # a glitched win
    state = json.loads(c.execute("SELECT state_json FROM meme_predictor_state").fetchone()[0])
    state.pop("outcome_rules"); state["win_sum"] += 150000
    c.execute("UPDATE meme_predictor_state SET state_json=?", (json.dumps(state),)); c.commit()
    m = mp.load_model(c)
    cap = study.net_return_pct(1.0, 1 + mp.MAX_FILL_UP_PCT / 100)
    assert abs(c.execute("SELECT actual_net_return_pct FROM meme_predictions WHERE candidate_id=2").fetchone()[0] - cap) < 1e-9
    assert m.avg_win() < 30 and m.n == 80 and m.outcome_rules == mp.OUTCOME_RULES
    assert mp.report(c)["policies"]["buy_every_discovery"]["avg_net_return_pct"] < 20


def test_every_new_forward_test_has_a_fixed_decision_point():
    # Lesson from skip_high_severe_risk (62% -> 90% -> 76% while being re-checked): rules registered after the
    # fixed-horizon policy must decide once, blind.
    for h in mp.HYPOTHESES:
        if h["registered_at"] > "2026-09-29T06:59:59+00:00":
            assert h.get("decide_at_trades"), h["name"]


def test_picks_vs_bot_is_blind_then_decides_on_the_same_measuring_stick():
    h = next(x for x in mp.HYPOTHESES if x.get("kind") == "picks_vs_bot")
    reg = datetime.fromisoformat(h["registered_at"])
    c = db(); mp.init(c)
    def row(i, wt, ps, dec, net):
        c.execute("""INSERT INTO meme_predictions(candidate_id,predicted_at,would_trade,p_severe_loss,bot_decision,
            status,actual_net_return_pct) VALUES(?,?,?,?,?,'RESOLVED',?)""",
                  (i, (reg + timedelta(minutes=i)).isoformat(), wt, ps, dec, net))
    for i in range(149):
        row(i, 1, .1, None, 2.0)
    for i in range(149, 200):
        row(i, 0, .5, mp.TRADED, -6.0)
    c.commit()
    r = next(x for x in mp.preregistered(c) if x["name"] == h["name"])
    assert r["verdict"].startswith("blind") and "kept" not in r
    row(300, 1, .1, None, 2.0); c.commit()
    r = next(x for x in mp.preregistered(c) if x["name"] == h["name"])
    assert r["verdict"].startswith("SUPPORTED") and r["kept"]["trades"] == 150 and r["every_entry"]["trades"] == 51


def test_bot_window_version_decides_and_the_stuck_one_is_void():
    h = next(x for x in mp.HYPOTHESES if x.get("window") == "bot")
    old = next(x for x in mp.HYPOTHESES if x["name"] == "predictor_low_risk_picks_beat_bot_fixed_150")
    reg = datetime.fromisoformat(h["registered_at"])
    c = db(); mp.init(c)
    def row(i, wt, ps, dec, net):
        c.execute("""INSERT INTO meme_predictions(candidate_id,predicted_at,would_trade,p_severe_loss,bot_decision,
            status,actual_net_return_pct) VALUES(?,?,?,?,?,'RESOLVED',?)""",
                  (i, (reg + timedelta(minutes=i)).isoformat(), wt, ps, dec, net))
    for i in range(600):  # picks every minute, a bot entry every 4th minute
        row(i, 1, .1, mp.TRADED if i % 4 == 0 else None, 3.0 if i % 4 else -6.0)
    c.commit()
    res = {r["name"]: r for r in mp.preregistered(c)}
    r = res[h["name"]]
    assert r["every_entry"]["trades"] == 150 and r["verdict"].startswith("SUPPORTED"), r
    assert res[old["name"]]["verdict"].startswith("VOID")
