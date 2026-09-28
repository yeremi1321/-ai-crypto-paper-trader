"""Re-entry rules. The live default is the no-re-entry paper trial (ALLOW_REENTRY=False); the older
stop-reclaim tests below run with ALLOW_REENTRY=True, which is the rollback path.

After a stop-loss, a bounce must not count as a fresh setup until price reclaims the failed entry.

Regression for BUTTPHIL on 2026-09-26: stopped at -28.12% at 08:03:50, re-entered ~50s later on a
small bounce, stopped again at -28.88% at 08:06:16.
"""
from datetime import datetime, timezone, timedelta
from unittest.mock import patch

import memecoin_shadow as ms
from memecoin_paper import migrate

BASE = {"token": "TEST", "token_address": "tok", "pair_address": "pair", "chain": "solana",
        "liquidity_usd": 100000, "makers": 500, "top10_holder_pct": 30, "dev_holder_pct": 3,
        "mint_authority_active": False, "freeze_authority_active": False, "sellable": True,
        "liquidity_locked": True, "volume_1h_usd": 100000, "price_change_1h_pct": 25,
        "volume_accel": 4, "holder_growth_1h_pct": 15, "higher_highs": True, "narrative_momentum": True}


def _db_with_closed_trade(exit_reason, entry_market_price, snapshot_prices):
    c = ms.init_db(":memory:"); migrate(c)
    c.execute("CREATE TABLE meme_price_snapshots(observed_at TEXT,token_address TEXT,price REAL)")
    now = datetime.now(timezone.utc)
    closed_at = (now - timedelta(minutes=2)).isoformat()
    c.execute("""INSERT INTO meme_paper_trades(candidate_id,token,token_address,opened_at,entry_market_price,entry_price,
        quantity,entry_fee,status,closed_at,exit_reason) VALUES(999,'TEST','tok',?,?,?,1,.6,'CLOSED',?,?)""",
              ((now - timedelta(minutes=5)).isoformat(), entry_market_price, entry_market_price * 1.01, closed_at, exit_reason))
    for n, p in enumerate(snapshot_prices):
        c.execute("INSERT INTO meme_price_snapshots VALUES(?,?,?)",
                  ((now - timedelta(seconds=60 - n * 20)).isoformat(), "tok", p))
    c.commit()
    return c


def _try_entry(c, price):
    x = dict(BASE, price_usd=price)
    before = c.execute("SELECT COUNT(*) FROM meme_paper_trades WHERE status='OPEN'").fetchone()[0]
    ms.record(c, x, ms.evaluate(x))
    after = c.execute("SELECT COUNT(*) FROM meme_paper_trades WHERE status='OPEN'").fetchone()[0]
    veto = c.execute("SELECT vetoes FROM meme_decision_ledger ORDER BY id DESC LIMIT 1").fetchone()[0]
    return after > before, veto


@patch.object(ms, "ALLOW_REENTRY", True)
def test_bounce_after_stop_is_blocked():
    # Entered at 1.00, crashed ~30%, small bounce. The old gate alone would allow this.
    c = _db_with_closed_trade("STOP_10", 1.00, [0.70, 0.72])
    assert ms.fresh_reentry(c, "tok", 0.75, c.execute("SELECT closed_at FROM meme_paper_trades").fetchone()[0],
                            False, datetime.now(timezone.utc)), "precondition: old gate passes"
    opened, veto = _try_entry(c, 0.75)
    assert not opened and veto == '["STOP_NOT_RECLAIMED"]'


@patch.object(ms, "ALLOW_REENTRY", True)
def test_real_recovery_after_stop_is_allowed():
    c = _db_with_closed_trade("STOP_10", 1.00, [0.95, 0.98])
    opened, veto = _try_entry(c, 1.05)
    assert opened and veto == "[]"


@patch.object(ms, "ALLOW_REENTRY", True)
def test_target_exit_keeps_existing_rule():
    # Wins are unchanged: a fresh setup below the prior entry is still allowed.
    c = _db_with_closed_trade("TARGET_20", 1.00, [0.70, 0.72])
    opened, veto = _try_entry(c, 0.75)
    assert opened and veto == "[]"


@patch.object(ms, "ALLOW_REENTRY", True)
def test_existing_fresh_setup_veto_still_applies_after_stop():
    c = _db_with_closed_trade("STOP_10", 1.00, [1.10, 1.20])
    opened, veto = _try_entry(c, 1.05)  # above prior entry, but not a new high
    assert not opened and veto == '["NO_FRESH_REENTRY_SETUP"]'


def test_no_reentry_trial_blocks_any_retrade():
    """Trial rule (default): once a token has been traded, it is never bought again - after a stop or a target."""
    assert ms.ALLOW_REENTRY is False
    for reason, prices, entry in (("STOP_10", [0.95, 0.98], 1.05), ("TARGET_20", [1.10, 1.20], 1.30)):
        c = _db_with_closed_trade(reason, 1.00, prices)
        opened, veto = _try_entry(c, entry)   # would pass the old reclaim + fresh-setup rules
        assert not opened and veto == '["NO_REENTRY_TRIAL"]', (reason, veto)


def test_no_reentry_trial_still_opens_new_tokens():
    c = _db_with_closed_trade("STOP_10", 1.00, [0.95, 0.98])
    x = dict(BASE, token="NEW", token_address="new", pair_address="pair2", price_usd=0.5)
    ms.record(c, x, ms.evaluate(x))
    assert c.execute("SELECT COUNT(*) FROM meme_paper_trades WHERE status='OPEN' AND token_address='new'").fetchone()[0] == 1


if __name__ == "__main__":
    test_bounce_after_stop_is_blocked()
    test_real_recovery_after_stop_is_allowed()
    test_target_exit_keeps_existing_rule()
    test_existing_fresh_setup_veto_still_applies_after_stop()
    test_no_reentry_trial_blocks_any_retrade()
    test_no_reentry_trial_still_opens_new_tokens()
    print("stop-loss re-entry tests passed")
