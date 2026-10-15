"""FOMO paper bot: entry confirmation, rug filtering, exit ladder, cost math, risk caps."""
import json
from datetime import datetime, timedelta, timezone

import pytest

import memecoin_fomo as f
from memecoin_shadow import init_db

T0 = datetime(2026, 10, 15, 12, tzinfo=timezone.utc)
SAFE = {"lp_holders": [{"is_locked": "1"}], "holders": [{"percent": "0.15"}], "mintable": {"status": "0"},
        "freezable": {"status": "0"}, "non_transferable": "0", "creator_percent": "0.02"}


def pair(addr="TOK", price=1.0, m5=8, h1=60, m5vol=40000, h1vol=120000, buys=80, sells=40, liq=80000,
         age_min=90, now=T0):
    return {"pairAddress": "P" + addr, "baseToken": {"address": addr, "symbol": addr}, "priceUsd": str(price),
            "liquidity": {"usd": liq}, "priceChange": {"m5": m5, "h1": h1},
            "volume": {"m5": m5vol, "h1": h1vol, "h6": h1vol * 2},
            "txns": {"m5": {"buys": buys, "sells": sells}, "h1": {"buys": 400, "sells": 300}},
            "pairCreatedAt": (now - timedelta(minutes=age_min)).timestamp() * 1000}


@pytest.fixture
def c(monkeypatch):
    monkeypatch.delenv("MEME_FOMO_ENABLED", raising=False)
    conn = init_db(":memory:"); f.init(conn); yield conn; conn.close()


def scan(c, now, *pairs, sec=SAFE):
    return f.scan(c, now, addresses=[p["baseToken"]["address"] for p in pairs],
                  fetch_pairs=lambda a: {p["baseToken"]["address"]: p for p in pairs}, fetch_sec=lambda a: sec)


def stages(c):
    return [r[0] for r in c.execute("SELECT stage FROM meme_fomo_signals ORDER BY id")]


def test_needs_two_looks_and_rising_price(c):
    assert scan(c, T0, pair(price=1.0)) == []
    assert scan(c, T0 + timedelta(seconds=10), pair(price=1.1)) == []          # too soon to confirm
    assert scan(c, T0 + timedelta(seconds=40), pair(price=1.05)) == ["TOK"]    # confirmed, still >= first look
    assert stages(c) == ["FIRST_LOOK", "ENTERED"]
    t = c.execute("SELECT entry_price,quantity,entry_fee,status FROM meme_fomo_trades").fetchone()
    assert t[0] == pytest.approx(1.05 * 1.01) and t[2] == pytest.approx(0.6) and t[3] == "OPEN"
    assert t[1] == pytest.approx(99.4 / (1.05 * 1.01))


def test_lower_second_look_is_not_bought(c):
    scan(c, T0, pair(price=1.0))
    assert scan(c, T0 + timedelta(seconds=40), pair(price=0.98)) == []
    assert stages(c)[-1] == "FAILED_CONFIRM"


def test_stale_first_look_restarts(c):
    scan(c, T0, pair())
    assert scan(c, T0 + timedelta(seconds=200), pair()) == []  # outside the 150 s window: new first look
    assert stages(c) == ["FIRST_LOOK", "FIRST_LOOK"]


@pytest.mark.parametrize("kw", [dict(m5=1), dict(m5=55), dict(h1=5), dict(h1=500), dict(m5vol=3000),
                                dict(buys=40, sells=40), dict(age_min=2), dict(age_min=60 * 30)])
def test_momentum_filters(c, kw):
    scan(c, T0, pair(**kw)); scan(c, T0 + timedelta(seconds=40), pair(**kw))
    assert stages(c) == [] and c.execute("SELECT COUNT(*) FROM meme_fomo_trades").fetchone()[0] == 0


@pytest.mark.parametrize("sec", [{}, {**SAFE, "mintable": {"status": "1"}}, {**SAFE, "holders": [{"percent": "0.8"}]},
                                 {**SAFE, "lp_holders": [{"is_locked": "0"}]}])
def test_rug_filters_block(c, sec):
    scan(c, T0, pair(), sec=sec); scan(c, T0 + timedelta(seconds=40), pair(), sec=sec)
    assert set(stages(c)) == {"RUG_FILTERED"}


def test_risk_caps(c, monkeypatch):
    for i in range(4):
        a = f"T{i}"; scan(c, T0, pair(a)); scan(c, T0 + timedelta(seconds=40), pair(a))
    assert c.execute("SELECT COUNT(*) FROM meme_fomo_trades").fetchone()[0] == f.MAX_OPEN
    assert "MAX_OPEN" in c.execute("SELECT reasons FROM meme_fomo_signals WHERE stage='VETOED'").fetchone()[0]
    c.execute("UPDATE meme_fomo_trades SET status='CLOSED',closed_at=?,net_pnl_usd=-15", (T0.isoformat(),))
    n = c.execute("SELECT COUNT(*) FROM meme_fomo_signals").fetchone()[0]
    scan(c, T0 + timedelta(seconds=300), pair("T0")); scan(c, T0 + timedelta(seconds=340), pair("T0"))
    assert c.execute("SELECT COUNT(*) FROM meme_fomo_signals").fetchone()[0] == n  # traded tokens are skipped silently
    assert c.execute("SELECT COUNT(*) FROM meme_fomo_trades WHERE token_address='T0'").fetchone()[0] == 1
    scan(c, T0 + timedelta(seconds=300), pair("NEW")); scan(c, T0 + timedelta(seconds=340), pair("NEW"))
    assert "DAILY_LOSS_LIMIT" in c.execute("SELECT reasons FROM meme_fomo_signals ORDER BY id DESC").fetchone()[0]
    monkeypatch.setenv("MEME_FOMO_ENABLED", "0")
    assert f.entry_veto(c, "OTHER", T0 + timedelta(days=1)) == "FOMO_DISABLED"


def opened(c):
    scan(c, T0, pair(price=1.0)); scan(c, T0 + timedelta(seconds=40), pair(price=1.0))
    return T0 + timedelta(seconds=40)


def tick(c, at, price, **kw):
    p = pair(price=price, now=at, **kw)
    return f.manage(c, at, fetch=lambda addrs: {p["pairAddress"]: p})


def trade(c):
    r = c.execute("SELECT status,exit_reason,net_pnl_usd,remaining_qty,quantity,fills_json FROM meme_fomo_trades").fetchone()
    return {"status": r[0], "exit": r[1], "pnl": r[2], "left": r[3] / r[4], "fills": json.loads(r[5])}


def test_stop_fills_at_gap_price_not_stop_level(c):
    t = opened(c)
    out = tick(c, t + timedelta(seconds=10), 0.70)  # gapped through the -12 % stop
    x = trade(c)
    assert out[0][1] == "STOP_12" and x["status"] == "CLOSED"
    qty = 99.4 / 1.01
    assert x["pnl"] == pytest.approx(qty * 0.70 * 0.99 * 0.994 - 100)


def test_ladder_then_trail(c):
    t = opened(c)
    tick(c, t + timedelta(minutes=1), 1.30)
    assert trade(c)["left"] == pytest.approx(0.5)
    tick(c, t + timedelta(minutes=2), 1.70)
    assert trade(c)["left"] == pytest.approx(0.25)
    tick(c, t + timedelta(minutes=3), 2.00)                 # new peak
    assert trade(c)["status"] == "OPEN"
    out = tick(c, t + timedelta(minutes=4), 1.69)           # 15.5 % under the peak
    x = trade(c)
    assert out[0][1] == "TRAIL_15" and x["left"] == 0 and x["pnl"] > 0
    assert [fl["reason"] for fl in x["fills"]] == ["TP1_25", "TP2_60", "TRAIL_15"]


def test_breakeven_stop_after_tp1(c):
    t = opened(c)
    tick(c, t + timedelta(minutes=1), 1.28)
    out = tick(c, t + timedelta(minutes=2), 1.03)
    assert out[0][1] == "BREAKEVEN_STOP" and trade(c)["pnl"] > 0  # half sold at +28 % covers costs


def test_no_progress_fade_and_liquidity_pull(c):
    t = opened(c)
    assert tick(c, t + timedelta(minutes=12), 1.05)[0][1] == "NO_PROGRESS_12M"
    c.execute("DELETE FROM meme_fomo_trades"); c.execute("DELETE FROM meme_fomo_signals")
    t = opened(c)
    assert tick(c, t + timedelta(minutes=4), 0.95, buys=10, sells=30)[0][1] == "BUYERS_FADED"
    c.execute("DELETE FROM meme_fomo_trades"); c.execute("DELETE FROM meme_fomo_signals")
    t = opened(c)
    assert tick(c, t + timedelta(minutes=1), 1.02, liq=20000)[0][1] == "LIQUIDITY_PULL"


def test_vanished_pair_counts_as_zero(c):
    t = opened(c)
    assert f.manage(c, t + timedelta(minutes=30), fetch=lambda a: {}) == []
    out = f.manage(c, t + timedelta(minutes=46), fetch=lambda a: {})
    assert out[0][1] == "NO_PRICE_ASSUMED_ZERO" and trade(c)["pnl"] == pytest.approx(-100)


def test_summary(c):
    t = opened(c)
    tick(c, t + timedelta(seconds=10), 0.80)
    s = f.summary(c, t)
    assert s["closed"] == 1 and s["wins"] == 0 and s["net_pnl_usd"] < -20 and s["mode"] == "paper_only"
    assert s["by_exit_reason"]["STOP_12"]["trades"] == 1 and s["max_drawdown_usd"] == s["net_pnl_usd"]


def test_repeat_logs_are_throttled_and_pruned(c):
    bad = {**SAFE, "mintable": {"status": "1"}}
    for s in range(0, 600, 30):
        scan(c, T0 + timedelta(seconds=s), pair(), sec=bad)
    assert stages(c) == ["RUG_FILTERED"]  # once per hour per token, not every 30 s
    scan(c, T0 + timedelta(days=8), pair("OTHER", now=T0 + timedelta(days=8)))
    assert stages(c) == ["FIRST_LOOK"]  # week-old research rows pruned
