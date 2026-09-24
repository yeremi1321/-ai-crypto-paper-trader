import argparse
import sqlite3
import time
from datetime import datetime, timezone

import numpy as np
import pandas as pd
import requests


LIVE_DB = "paper_trader_v4.db"
SHADOW_DB = "research_shadow.db"


KRAKEN_PAIRS = {
    "BTC-USD": "XBTUSD", "ETH-USD": "ETHUSD", "SOL-USD": "SOLUSD",
    "DOGE-USD": "DOGEUSD", "SHIB-USD": "SHIBUSD", "AVAX-USD": "AVAXUSD",
    "LINK-USD": "LINKUSD", "ADA-USD": "ADAUSD", "XRP-USD": "XRPUSD",
    "LTC-USD": "LTCUSD", "BCH-USD": "BCHUSD",
}


def _coinbase_candles(product, granularity, limit):
    last_error = None
    for attempt in range(4):
        try:
            response = requests.get(
                f"https://api.exchange.coinbase.com/products/{product}/candles",
                params={"granularity": granularity},
                headers={"User-Agent": "v5-shadow-research"},
                timeout=20,
            )
            if response.status_code != 200:
                print(
                    f"{product} Coinbase candles HTTP {response.status_code} "
                    f"(attempt {attempt + 1}/4)"
                )
            response.raise_for_status()
            payload = response.json()
            if not isinstance(payload, list):
                raise RuntimeError(f"Unexpected Coinbase response: {payload!r}")
            return payload[:limit]
        except (requests.RequestException, ValueError, RuntimeError) as exc:
            last_error = exc
            if attempt < 3:
                time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(
        f"Coinbase candle request failed after 4 attempts: {last_error}"
    ) from last_error


def _kraken_candles(product, granularity, limit):
    pair = KRAKEN_PAIRS.get(product)
    interval = {900: 15, 14400: 240}.get(granularity)
    if not pair or not interval:
        raise RuntimeError("No Kraken fallback mapping for request")
    response = requests.get(
        "https://api.kraken.com/0/public/OHLC",
        params={"pair": pair, "interval": interval},
        headers={"User-Agent": "v5-shadow-research"},
        timeout=20,
    )
    response.raise_for_status()
    payload = response.json()
    if payload.get("error"):
        raise RuntimeError(f"Kraken API error: {payload['error']!r}")
    result = payload.get("result", {})
    key = next((key for key in result if key != "last"), None)
    if key is None:
        raise RuntimeError("Kraken returned no OHLC series")
    rows = result[key][-limit:]
    # Kraken: time, open, high, low, close, vwap, volume, count.
    return [
        [row[0], row[3], row[2], row[1], row[4], row[6]]
        for row in rows
    ]


def candles(product, granularity, limit=220):
    source = "Coinbase"
    try:
        payload = _coinbase_candles(product, granularity, limit)
    except Exception as coinbase_error:
        print(f"{product} Coinbase unavailable; trying Kraken fallback: {coinbase_error}")
        source = "Kraken"
        payload = _kraken_candles(product, granularity, limit)
    frame = pd.DataFrame(
        payload,
        columns=["time", "low", "high", "open", "close", "volume"],
    )
    frame = frame.sort_values("time").reset_index(drop=True)
    for column in ["time", "low", "high", "open", "close", "volume"]:
        frame[column] = pd.to_numeric(frame[column])
    completed = frame[frame.time + granularity <= time.time()].copy()
    if len(completed) < 55:
        raise RuntimeError(
            f"{source} returned only {len(completed)} completed candles for "
            f"{product} at {granularity}s"
        )
    print(f"{product} {granularity}s shadow candles source={source} rows={len(completed)}")
    completed.attrs["data_source"] = source
    return completed


def trend_4h(frame):
    close = frame.close
    ema20 = close.ewm(span=20, adjust=False).mean()
    ema50 = close.ewm(span=50, adjust=False).mean()
    return bool(close.iloc[-1] > ema20.iloc[-1] > ema50.iloc[-1])


def pullback_retest(frame):
    frame = frame.copy()
    frame["ema20"] = frame.close.ewm(span=20, adjust=False).mean()
    frame["breakout_level"] = frame.high.shift(1).rolling(20).max()
    frame["breakout"] = frame.close > frame.breakout_level
    breakout_rows = frame.iloc[-5:-1]
    breakout_rows = breakout_rows[breakout_rows.breakout]
    if breakout_rows.empty:
        return False, None
    level = float(breakout_rows.breakout_level.iloc[-1])
    current = frame.iloc[-1]
    ready = bool(
        current.low <= level * 1.004
        and current.close >= level * 0.998
        and current.close > current.ema20
    )
    return ready, level


def classify_regime(btc_4h, breadth):
    if btc_4h and breadth >= 0.70:
        return "TRENDING_UP"
    if not btc_4h and breadth < 0.40:
        return "RISK_OFF"
    return "CHOPPY"


def init_db(path):
    conn = sqlite3.connect(path)
    conn.execute(
        """CREATE TABLE IF NOT EXISTS shadow_evaluations(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            scan_id TEXT,
            seen_at TEXT,
            product TEXT,
            score REAL,
            price REAL,
            rel_volume REAL,
            state TEXT,
            trend_4h INTEGER,
            market_regime TEXT,
            pullback_ready INTEGER,
            retest_level REAL,
            shadow_decision TEXT,
            detail TEXT,
            return_1h_pct REAL,
            return_4h_pct REAL,
            return_24h_pct REAL,
            UNIQUE(scan_id, product)
        )"""
    )
    columns = {row[1] for row in conn.execute("PRAGMA table_info(shadow_evaluations)").fetchall()}
    if "data_source" not in columns:
        conn.execute("ALTER TABLE shadow_evaluations ADD COLUMN data_source TEXT")
    conn.commit()
    return conn


def latest_live_rows(path):
    conn = sqlite3.connect(path)
    latest_scan_id = conn.execute(
        "SELECT scan_id FROM scans ORDER BY id DESC LIMIT 1"
    ).fetchone()[0]
    rows = pd.read_sql_query(
        "SELECT * FROM scans WHERE scan_id=? ORDER BY product",
        conn,
        params=(latest_scan_id,),
    )
    states = pd.read_sql_query(
        """SELECT m.product, m.state
           FROM momentum_tracking m
           JOIN (
             SELECT product, MAX(id) AS max_id
             FROM momentum_tracking GROUP BY product
           ) latest ON latest.max_id=m.id""",
        conn,
    )
    regime = conn.execute(
        """SELECT market_breadth FROM market_regime_log
           ORDER BY id DESC LIMIT 1"""
    ).fetchone()
    conn.close()
    rows = rows.merge(states, on="product", how="left")
    return latest_scan_id, rows, float(regime[0]) if regime else 0.0


def update_outcomes(conn, now, current_prices):
    open_rows = conn.execute(
        """SELECT id, seen_at, product, price, return_1h_pct,
                  return_4h_pct, return_24h_pct
           FROM shadow_evaluations
           WHERE shadow_decision='WOULD_ENTER'
             AND (return_1h_pct IS NULL OR return_4h_pct IS NULL
                  OR return_24h_pct IS NULL)"""
    ).fetchall()
    for row in open_rows:
        row_id, seen_at, product, entry_price, r1, r4, r24 = row
        current_price = current_prices.get(product)
        if current_price is None:
            continue
        age_hours = (now - datetime.fromisoformat(seen_at)).total_seconds() / 3600
        result = (current_price / entry_price - 1) * 100
        if age_hours >= 1 and r1 is None:
            r1 = result
        if age_hours >= 4 and r4 is None:
            r4 = result
        if age_hours >= 24 and r24 is None:
            r24 = result
        conn.execute(
            """UPDATE shadow_evaluations
               SET return_1h_pct=?, return_4h_pct=?, return_24h_pct=?
               WHERE id=?""",
            (r1, r4, r24, row_id),
        )



def print_research_summary(conn):
    total = conn.execute("SELECT COUNT(*) FROM shadow_evaluations").fetchone()[0]
    entries = conn.execute(
        "SELECT COUNT(*) FROM shadow_evaluations WHERE shadow_decision='WOULD_ENTER'"
    ).fetchone()[0]
    print(f"SHADOW SUMMARY observations={total} would_enter={entries}")
    for column, label in (
        ("return_1h_pct", "1h"), ("return_4h_pct", "4h"), ("return_24h_pct", "24h")
    ):
        values = [
            float(row[0]) for row in conn.execute(
                f"""SELECT {column} FROM shadow_evaluations
                    WHERE shadow_decision='WOULD_ENTER' AND {column} IS NOT NULL"""
            ).fetchall()
        ]
        if values:
            wins = sum(value > 0 for value in values)
            print(
                f"SHADOW {label} samples={len(values)} "
                f"win_rate={wins / len(values) * 100:.1f}% "
                f"avg_return={sum(values) / len(values):+.3f}%"
            )
        else:
            print(f"SHADOW {label} samples=0")
    regimes = conn.execute(
        """SELECT market_regime, COUNT(*),
                  SUM(CASE WHEN shadow_decision='WOULD_ENTER' THEN 1 ELSE 0 END)
           FROM shadow_evaluations GROUP BY market_regime ORDER BY market_regime"""
    ).fetchall()
    for regime, observations, would_enter in regimes:
        print(
            f"SHADOW REGIME {regime} observations={observations} "
            f"would_enter={would_enter or 0}"
        )

def run_shadow(live_db, shadow_db):
    scan_id, current, breadth = latest_live_rows(live_db)
    now = datetime.now(timezone.utc)
    research = []
    for _, row in current.iterrows():
        try:
            four_hour = candles(row["product"], 14400)
            quarter_hour = candles(row["product"], 900)
            aligned_4h = trend_4h(four_hour)
            retest_ready, retest_level = pullback_retest(quarter_hour)
            sources = {four_hour.attrs.get("data_source"), quarter_hour.attrs.get("data_source")}
            data_source = "Kraken fallback" if "Kraken" in sources else "Coinbase"
            research.append(
                {
                    **row.to_dict(),
                    "trend_4h": aligned_4h,
                    "pullback_ready": retest_ready,
                    "retest_level": retest_level,
                    "data_source": data_source,
                }
            )
        except Exception as error:
            print(f"{row['product']} shadow error: {error}")
    if not research:
        # Coinbase can temporarily rate-limit/block GitHub-hosted runners.
        # Shadow research is optional and must not take down the production scan.
        print("::warning::Shadow research skipped: Coinbase candle data unavailable for all products")
        return False
    btc_4h = next(
        (item["trend_4h"] for item in research if item["product"] == "BTC-USD"),
        False,
    )
    regime = classify_regime(btc_4h, breadth)
    conn = init_db(shadow_db)
    current_prices = {item["product"]: float(item["price"]) for item in research}
    update_outcomes(conn, now, current_prices)
    for item in research:
        eligible_state = item.get("state") in (
            "CONFIRMED", "STRENGTHENING", "WATCH"
        )
        checks = {
            "score>=75": item["score"] >= 75,
            "volume>=1.25x": item["rel_volume"] >= 1.25,
            "state ready": eligible_state,
            "4h bullish": item["trend_4h"],
            "trending market": regime == "TRENDING_UP",
            "pullback/retest": item["pullback_ready"],
        }
        decision = "WOULD_ENTER" if all(checks.values()) else "OBSERVE"
        detail = "; ".join(
            f"{name}={'yes' if passed else 'no'}" for name, passed in checks.items()
        )
        conn.execute(
            """INSERT OR IGNORE INTO shadow_evaluations(
                scan_id, seen_at, product, score, price, rel_volume, state,
                trend_4h, market_regime, pullback_ready, retest_level,
                shadow_decision, detail, data_source
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (
                scan_id, now.isoformat(), item["product"], item["score"],
                item["price"], item["rel_volume"], item.get("state"),
                int(item["trend_4h"]), regime, int(item["pullback_ready"]),
                item["retest_level"], decision, detail, item["data_source"],
            ),
        )
        print(item["product"], regime, decision)
    conn.commit()
    print_research_summary(conn)
    conn.close()


def self_test():
    assert classify_regime(True, 0.75) == "TRENDING_UP"
    assert classify_regime(False, 0.20) == "RISK_OFF"
    assert classify_regime(True, 0.45) == "CHOPPY"
    periods = 80
    close = np.linspace(100, 110, periods)
    frame = pd.DataFrame(
        {
            "open": close - .1, "high": close + .2, "low": close - .2,
            "close": close, "volume": np.ones(periods) * 100,
        }
    )
    assert isinstance(trend_4h(frame), bool)
    ready, level = pullback_retest(frame)
    assert isinstance(ready, bool)
    assert level is None or isinstance(level, float)
    print("shadow_research self-test passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--live-db", default=LIVE_DB)
    parser.add_argument("--shadow-db", default=SHADOW_DB)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    else:
        run_shadow(args.live_db, args.shadow_db)
