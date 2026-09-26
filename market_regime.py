"""Record-only market regime for memecoin discoveries. Never trades, never blocks an entry.

Adds SOL-USD trend fields to each discovery before it is stored, so later studies can test whether
memecoin outcomes depend on the broader Solana market:

    sol_ret_15m_pct, sol_ret_60m_pct, sol_ret_240m_pct   numeric SOL returns (for the studies)
    market_regime                                         SOL_UP / SOL_FLAT / SOL_DOWN / UNKNOWN (for humans)

Data: Coinbase public 5-minute SOL-USD candles, fetched at most once per CACHE_SECONDS. Any failure
(network, timeout, bad data) returns UNKNOWN and is itself cached, so a Coinbase outage can never
slow discovery by more than one short timeout per minute. Labels are descriptive only; no rule uses them.
"""
import json
import threading
import time
import urllib.request

CANDLES_URL = "https://api.exchange.coinbase.com/products/SOL-USD/candles?granularity=300"
CACHE_SECONDS = 60.0
TIMEOUT_SECONDS = 3.0
FLAT_BAND_PCT = 0.5
FIELDS = ("sol_ret_15m_pct", "sol_ret_60m_pct", "sol_ret_240m_pct")

_cache = {"at": -1e9, "value": None}
_lock = threading.Lock()


def _fetch_candles():
    req = urllib.request.Request(CANDLES_URL, headers={"User-Agent": "meme-paper-research/1.0"})
    with urllib.request.urlopen(req, timeout=TIMEOUT_SECONDS) as r:
        return json.loads(r.read().decode())


def compute(candles):
    """candles: Coinbase rows [time, low, high, open, close, volume], newest first, 5-minute bars."""
    rows = sorted((int(c[0]), float(c[4])) for c in candles if len(c) >= 5 and float(c[4]) > 0)
    if len(rows) < 4:
        return None
    by_time = dict(rows)
    now_t, now_px = rows[-1]

    def ret(minutes):
        target = now_t - minutes * 60
        past = [t for t in by_time if t <= target]
        if not past:
            return None
        return round((now_px / by_time[max(past)] - 1) * 100, 3)

    out = {"sol_ret_15m_pct": ret(15), "sol_ret_60m_pct": ret(60), "sol_ret_240m_pct": ret(240)}
    r60 = out["sol_ret_60m_pct"]
    out["market_regime"] = ("UNKNOWN" if r60 is None else "SOL_UP" if r60 > FLAT_BAND_PCT
                            else "SOL_DOWN" if r60 < -FLAT_BAND_PCT else "SOL_FLAT")
    return out


def current(fetch=None, clock=time.monotonic):
    fetch = fetch or _fetch_candles
    with _lock:
        if clock() - _cache["at"] < CACHE_SECONDS:
            return _cache["value"]
        try:
            value = compute(fetch())
        except Exception as e:
            print(f"::warning::market regime unavailable: {type(e).__name__}", flush=True)
            value = None
        _cache.update(at=clock(), value=value)
        return value


def annotate(x, fetch=None, clock=time.monotonic):
    """Return a copy of the discovery dict with regime fields added. Never raises."""
    try:
        y = dict(x)
        regime = current(fetch, clock)
        if regime:
            for k, v in regime.items():
                if v is not None:
                    y[k] = v
        else:
            y.setdefault("market_regime", "UNKNOWN")
        return y
    except Exception:
        return x
