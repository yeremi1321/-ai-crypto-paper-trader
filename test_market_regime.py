"""Market-regime recorder: correct SOL returns, caching, fail-safe, stored with discoveries, forward study."""
import json
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

import market_regime as mr
import memecoin_candidate_study as cs
import memecoin_shadow as ms
from memecoin_paper import migrate


def candles(prices_oldest_first, t_end=1_790_000_000):
    """5-minute bars, returned newest first like Coinbase."""
    n = len(prices_oldest_first)
    rows = [[t_end - (n - 1 - i) * 300, p, p, p, p, 1.0] for i, p in enumerate(prices_oldest_first)]
    return list(reversed(rows))


def fresh():
    mr._cache.update(at=-1e9, value=None)


def test_compute_returns_and_label():
    # 49 bars = 4 hours; price 100 four hours ago, 101 one hour ago, 102 fifteen minutes ago, 103 now.
    px = [100.0] * 36 + [101.0] * 9 + [102.0] * 3 + [103.0]  # bars: 240m ago=100, 60m ago=101, 15m ago=102, now=103
    out = mr.compute(candles(px))
    assert out["sol_ret_15m_pct"] == round((103 / 102 - 1) * 100, 3)
    assert out["sol_ret_60m_pct"] == round((103 / 101 - 1) * 100, 3)
    assert out["sol_ret_240m_pct"] == 3.0
    assert out["market_regime"] == "SOL_UP"
    assert mr.compute(candles([100.0] * 13 + [99.0]))["market_regime"] == "SOL_DOWN"
    assert mr.compute(candles([100.0] * 13 + [100.2]))["market_regime"] == "SOL_FLAT"
    assert mr.compute([]) is None


def test_cached_and_fail_safe():
    fresh(); calls = []; t = [0.0]
    fetch = lambda: (calls.append(1), candles([100.0] * 13 + [101.0]))[1]
    a = mr.annotate({"token": "X"}, fetch, lambda: t[0])
    t[0] = 30.0; mr.annotate({"token": "Y"}, fetch, lambda: t[0])
    assert len(calls) == 1, "second call inside 60s must use the cache"
    assert a["market_regime"] == "SOL_UP" and a["token"] == "X"
    fresh()
    def boom():
        raise TimeoutError()
    b = mr.annotate({"token": "Z"}, boom, lambda: 100.0)
    assert b == {"token": "Z", "market_regime": "UNKNOWN"}
    fail_calls = []
    mr.annotate({"token": "Z"}, lambda: (fail_calls.append(1), boom())[1], lambda: 110.0)
    assert fail_calls == [], "a failure is cached too, so an outage cannot stall discovery repeatedly"
    original = {"token": "Q"}
    mr.annotate(original, boom, lambda: 1000.0)
    assert original == {"token": "Q"}, "input must not be mutated"


def test_regime_is_stored_with_every_discovery_and_changes_nothing_else():
    fresh()
    x = {"token": "TEST", "token_address": "abc", "pair_address": "pair", "chain": "solana", "price_usd": .01,
         "liquidity_usd": 100000, "makers": 500, "top10_holder_pct": 30, "dev_holder_pct": 3,
         "mint_authority_active": False, "freeze_authority_active": False, "sellable": True, "liquidity_locked": True,
         "volume_1h_usd": 100000, "price_change_1h_pct": 25, "volume_accel": 4, "holder_growth_1h_pct": 15,
         "higher_highs": True, "narrative_momentum": True}
    with patch.object(mr, "_fetch_candles", lambda: candles([100.0] * 13 + [98.0])):
        c = ms.init_db(":memory:"); migrate(c)
        ms.record(c, x, ms.evaluate(x))
    raw = json.loads(c.execute("SELECT raw_json FROM meme_candidates").fetchone()[0])
    assert raw["market_regime"] == "SOL_DOWN" and raw["sol_ret_60m_pct"] == -2.0
    assert c.execute("SELECT regime,decision FROM meme_decision_ledger").fetchone() == ("SOL_DOWN", "PAPER_TRADE_CANDIDATE")
    assert c.execute("SELECT COUNT(*) FROM meme_paper_trades").fetchone()[0] == 1  # entry unaffected


def test_forward_sections():
    start = datetime.fromisoformat(cs.FORWARD_START).replace(tzinfo=timezone.utc) + timedelta(minutes=5)
    with tempfile.TemporaryDirectory() as d:
        path = str(Path(d) / "f.db")
        c = ms.init_db(path); migrate(c)
        c.execute("""CREATE TABLE IF NOT EXISTS meme_price_snapshots(id INTEGER PRIMARY KEY AUTOINCREMENT,observed_at TEXT NOT NULL,
            token_address TEXT NOT NULL,pair_address TEXT,price REAL NOT NULL,liquidity_usd REAL,volume_1h_usd REAL)""")
        for i in range(30):
            tok = f"F{i:02d}"; seen = start + timedelta(minutes=30 * i)
            up = i % 2 == 0
            x = {"token": tok, "token_address": tok, "price_usd": 1.0, "liquidity_usd": 80000,
                 "sol_ret_60m_pct": 1.5 if up else -1.5, "pair_created_at": 1_790_000_000_000 + i}
            c.execute("""INSERT INTO meme_candidates(seen_at,version,token,chain,score,eligible,blocked_reasons,raw_json,token_address)
                VALUES(?,?,?,?,?,?,?,?,?)""", (seen.isoformat(), "V", tok, "solana", 70, 1, "[]", json.dumps(x), tok))
            for s, p in ([(30, 1.1), (60, 1.25)] if up else [(30, 0.95), (60, 0.7)]):
                c.execute("INSERT INTO meme_price_snapshots(observed_at,token_address,price,liquidity_usd) VALUES(?,?,?,?)",
                          ((seen + timedelta(seconds=s)).isoformat(), tok, p, 80000))
        c.commit()
        out = cs.run(c, "now"); c.close()
    f = out["forward_test"]
    assert f["realistic_pools"]["n"] == 30 and f["sol_regime"]["tokens_with_regime"] == 30
    assert f["sol_regime"]["by_sol_60m_trend"]["SOL_UP"]["win_rate"] == 100.0
    assert f["sol_regime"]["by_sol_60m_trend"]["SOL_DOWN"]["win_rate"] == 0.0
    assert "sol_ret_60m_pct" in f["sol_regime"]["feature_test"]["features"]
    assert f["pair_age_hypothesis"]["older_half"]["n"] == 15
    json.dumps(out)


if __name__ == "__main__":
    test_compute_returns_and_label()
    test_cached_and_fail_safe()
    test_regime_is_stored_with_every_discovery_and_changes_nothing_else()
    test_forward_sections()
    print("market regime tests passed")
