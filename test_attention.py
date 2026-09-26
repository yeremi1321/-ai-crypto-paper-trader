"""Attention recorder: parses DEX Screener data correctly, caches boosts, fail-safe, stored, studied, no trading effect."""
import json
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

import attention as at
import memecoin_candidate_study as cs
import memecoin_shadow as ms
from memecoin_paper import migrate

PROFILE = {"tokenAddress": "tok1", "chainId": "solana",
           "links": [{"type": "twitter", "url": "https://x.com/meme"}, {"label": "Website", "url": "https://meme.fun"}]}
PAIR = {"boosts": {"active": 3},
        "info": {"socials": [{"type": "telegram", "url": "https://t.me/meme"}, {"type": "twitter", "url": "https://x.com/meme"}],
                 "websites": [{"url": "https://meme.fun"}]},
        "txns": {"m5": {"buys": 30, "sells": 10}, "h1": {"buys": 120, "sells": 120}},
        "volume": {"m5": 5000, "h1": 24000}}


def fresh():
    at._cache.update(at=-1e9, value=None)


def test_signals_parse_dexscreener_shapes():
    s = at.signals(PROFILE, PAIR, {"tok1": 500.0})
    assert s["attn_boosts_active"] == 3.0 and s["attn_boost_top_amount"] == 500.0
    assert s["attn_social_count"] == 3.0          # twitter + website deduplicated across profile and pair, + telegram
    assert (s["attn_has_twitter"], s["attn_has_telegram"], s["attn_has_website"]) == (1.0, 1.0, 1.0)
    assert s["attn_txns_5m"] == 40.0
    assert s["attn_tx_accel_5m"] == 2.0           # 40 trades in 5m vs 240/12 = 20 per 5m on average
    assert s["attn_volume_accel_5m"] == 2.5       # 5000 vs 24000/12
    assert s["attn_buy_ratio_5m"] == 0.75 and s["attn_buy_ratio_1h"] == 0.5
    empty = at.signals({}, {}, None)
    assert empty["attn_social_count"] == 0.0 and "attn_buy_ratio_5m" not in empty and "attn_boost_top_amount" not in empty


def test_boosts_cached_and_fail_safe():
    fresh(); calls = []; t = [0.0]
    fetch = lambda: (calls.append(1), [{"chainId": "solana", "tokenAddress": "tok1", "totalAmount": 700},
                                       {"chainId": "ethereum", "tokenAddress": "eth1", "totalAmount": 9}])[1]
    assert at.top_boosts(fetch, lambda: t[0]) == {"tok1": 700.0}
    t[0] = 59.0; at.top_boosts(fetch, lambda: t[0])
    assert len(calls) == 1
    fresh()
    def boom():
        raise TimeoutError()
    row = {"token": "X"}
    out = at.annotate(row, PROFILE, PAIR, boom, lambda: 0.0)
    assert "attn_boost_top_amount" not in out and out["attn_boosts_active"] == 3.0, "pair-based fields still recorded"
    assert row == {"token": "X"}, "input not mutated"
    assert at.annotate(row, None, "not a dict", boom, lambda: 1.0) == row, "bad input never raises"


def test_attention_stored_and_entry_unchanged():
    fresh()
    base = {"token": "TEST", "token_address": "tok1", "pair_address": "pair", "chain": "solana", "price_usd": .01,
            "liquidity_usd": 100000, "makers": 500, "top10_holder_pct": 30, "dev_holder_pct": 3,
            "mint_authority_active": False, "freeze_authority_active": False, "sellable": True, "liquidity_locked": True,
            "volume_1h_usd": 100000, "price_change_1h_pct": 25, "volume_accel": 4, "holder_growth_1h_pct": 15,
            "higher_highs": True, "narrative_momentum": True}
    row = at.annotate(base, PROFILE, PAIR, lambda: [], lambda: 0.0)
    assert ms.evaluate(row) == ms.evaluate(base), "attention fields must not change the score or eligibility"
    c = ms.init_db(":memory:"); migrate(c)
    ms.record(c, row, ms.evaluate(row))
    raw = json.loads(c.execute("SELECT raw_json FROM meme_candidates").fetchone()[0])
    assert raw["attn_tx_accel_5m"] == 2.0 and raw["attn_boost_top_amount"] == 0.0
    assert c.execute("SELECT COUNT(*) FROM meme_paper_trades").fetchone()[0] == 1


def test_forward_attention_section():
    start = datetime.fromisoformat(cs.FORWARD_START).replace(tzinfo=timezone.utc) + timedelta(minutes=5)
    with tempfile.TemporaryDirectory() as d:
        path = str(Path(d) / "a.db")
        c = ms.init_db(path); migrate(c)
        c.execute("""CREATE TABLE IF NOT EXISTS meme_price_snapshots(id INTEGER PRIMARY KEY AUTOINCREMENT,observed_at TEXT NOT NULL,
            token_address TEXT NOT NULL,pair_address TEXT,price REAL NOT NULL,liquidity_usd REAL,volume_1h_usd REAL)""")
        for i in range(30):
            tok = f"A{i:02d}"; seen = start + timedelta(minutes=30 * i); hot = i % 2 == 0
            x = {"token": tok, "token_address": tok, "price_usd": 1.0, "liquidity_usd": 80000, "makers": 100 + i,
                 "attn_tx_accel_5m": 3.0 if hot else 0.5}
            c.execute("""INSERT INTO meme_candidates(seen_at,version,token,chain,score,eligible,blocked_reasons,raw_json,token_address)
                VALUES(?,?,?,?,?,?,?,?,?)""", (seen.isoformat(), "V", tok, "solana", 70, 1, "[]", json.dumps(x), tok))
            for s, p in ([(30, 1.1), (60, 1.25)] if hot else [(30, 0.95), (60, 0.7)]):
                c.execute("INSERT INTO meme_price_snapshots(observed_at,token_address,price,liquidity_usd) VALUES(?,?,?,?)",
                          ((seen + timedelta(seconds=s)).isoformat(), tok, p, 80000))
        c.commit(); out = cs.run(c, "now"); c.close()
    a = out["forward_test"]["attention"]
    assert a["tokens_with_attention"] == 30
    feats = a["feature_test"]["features"]
    assert set(feats) == {"attn_tx_accel_5m"}, "only attention fields are tested in this section"
    assert any("attn_tx_accel_5m >" in x for x in a["feature_test"]["candidates"])


if __name__ == "__main__":
    test_signals_parse_dexscreener_shapes()
    test_boosts_cached_and_fail_safe()
    test_attention_stored_and_entry_unchanged()
    test_forward_attention_section()
    print("attention tests passed")
