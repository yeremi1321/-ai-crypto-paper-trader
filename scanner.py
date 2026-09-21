import os
import sqlite3
import time
from datetime import datetime, timezone

import numpy as np
import pandas as pd
import requests


DB = "paper_trader_v4.db"
PRODUCTS = [
    "BTC-USD", "ETH-USD", "SOL-USD", "DOGE-USD", "SHIB-USD", "AVAX-USD",
    "LINK-USD", "ADA-USD", "XRP-USD", "LTC-USD", "BCH-USD",
]
EARLY_MIN_SCORE = 45
EARLY_MAX_SCORE = 69.9
SCORE_ACCEL_MIN = 8
VOLUME_ACCEL_MIN = 1.25
STRENGTHEN_SCORE_GAIN = 5
WEAKEN_SCORE_DROP = 8
FAIL_SCORE = 35


def db():
    conn = sqlite3.connect(DB)
    conn.execute("""CREATE TABLE IF NOT EXISTS scans(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scan_id TEXT,
        seen_at TEXT,
        product TEXT,
        price REAL,
        score REAL,
        status TEXT,
        rsi REAL,
        rel_volume REAL,
        reason TEXT
    )""")
    conn.execute("""CREATE TABLE IF NOT EXISTS early_events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scan_id TEXT,
        seen_at TEXT,
        product TEXT,
        price REAL,
        score REAL,
        score_accel REAL,
        rel_volume REAL,
        volume_accel REAL
    )""")
    conn.execute("""CREATE TABLE IF NOT EXISTS momentum_tracking(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        seen_at TEXT,
        product TEXT,
        state TEXT,
        score REAL,
        previous_score REAL,
        price REAL
    )""")
    conn.execute("""CREATE TABLE IF NOT EXISTS momentum_sequences(
        product TEXT PRIMARY KEY,
        started_at TEXT,
        state TEXT,
        hold_count INTEGER,
        early_score REAL,
        last_score REAL
    )""")
    conn.commit()
    return conn


def candles(product, granularity, limit=220):
    url = f"https://api.exchange.coinbase.com/products/{product}/candles"
    response = requests.get(
        url,
        params={"granularity": granularity},
        headers={"User-Agent": "paper-v4"},
        timeout=15,
    )
    response.raise_for_status()
    frame = pd.DataFrame(
        response.json()[:limit],
        columns=["time", "low", "high", "open", "close", "volume"],
    )
    frame = frame.sort_values("time").reset_index(drop=True)
    for column in ["low", "high", "open", "close", "volume"]:
        frame[column] = pd.to_numeric(frame[column])
    return frame[frame.time + granularity <= time.time()].copy()


def indicators(frame):
    frame = frame.copy()
    frame["ema20"] = frame.close.ewm(span=20, adjust=False).mean()
    frame["ema50"] = frame.close.ewm(span=50, adjust=False).mean()
    change = frame.close.diff()
    gain = change.clip(lower=0).ewm(alpha=1 / 14, adjust=False).mean()
    loss = (-change.clip(upper=0)).ewm(alpha=1 / 14, adjust=False).mean()
    frame["rsi"] = 100 - (100 / (1 + (gain / loss.replace(0, np.nan))))
    frame["rv"] = frame.volume / frame.volume.rolling(20).mean()
    true_range = pd.concat(
        [
            frame.high - frame.low,
            (frame.high - frame.close.shift()).abs(),
            (frame.low - frame.close.shift()).abs(),
        ],
        axis=1,
    ).max(axis=1)
    frame["atr"] = true_range.rolling(14).mean()
    return frame


def scan_one(product):
    quarter_hour = indicators(candles(product, 900))
    hourly = indicators(candles(product, 3600))
    current, hour = quarter_hour.iloc[-1], hourly.iloc[-1]
    score = 0.0
    reasons = []

    if current.close > current.ema20:
        score += 10
        reasons.append("15m>EMA20")
    if current.ema20 > current.ema50:
        score += 8
        reasons.append("15m trend")
    if 52 <= current.rsi <= 72:
        score += 7
        reasons.append("RSI momentum")

    relative_volume = float(current.rv) if pd.notna(current.rv) else 0
    score += min(25, max(0, (relative_volume - 0.8) * 18))
    if relative_volume >= 1.5:
        reasons.append("volume surge")
    if current.close > quarter_hour.high.iloc[-21:-1].max():
        score += 12
        reasons.append("20-bar breakout")
    if hour.close > hour.ema20:
        score += 8
        reasons.append("1h trend")

    atr_percent = (current.atr / current.close) * 100
    if 0.15 <= atr_percent <= 4:
        score += 10
        reasons.append("tradable ATR")
    if current.volume > 0:
        score += 5

    score = round(min(score, 85), 1)
    status = "SIGNAL" if score >= 80 else ("WATCH" if score >= 70 else "IGNORE")
    return (
        product,
        float(current.close),
        score,
        status,
        round(float(current.rsi), 1),
        round(relative_volume, 2),
        ", ".join(reasons),
    )


def record_state(conn, seen_at, product, state, score, previous_score, price):
    """Record a state transition once and return True when a row was added."""
    latest = conn.execute(
        "SELECT state FROM momentum_tracking WHERE product=? ORDER BY id DESC LIMIT 1",
        (product,),
    ).fetchone()
    if latest and latest[0] == state:
        return False
    conn.execute(
        """INSERT INTO momentum_tracking(
               seen_at, product, state, score, previous_score, price
           ) VALUES(?,?,?,?,?,?)""",
        (seen_at, product, state, score, previous_score, price),
    )
    return True


conn = db()
now = datetime.now(timezone.utc)
seen_at = now.isoformat()
scan_id = now.strftime("%Y%m%dT%H%M%SZ")
alerts = []

for product in PRODUCTS:
    try:
        result = scan_one(product)
        previous = conn.execute(
            """SELECT score, rel_volume
               FROM scans
               WHERE product=?
               ORDER BY id DESC
               LIMIT 1""",
            (product,),
        ).fetchone()

        previous_score = previous[0] if previous else result[2]
        score_acceleration = result[2] - previous_score if previous else 0
        volume_acceleration = 0
        if previous and previous[1] and previous[1] > 0:
            volume_acceleration = result[5] / previous[1]

        is_early = bool(
            previous
            and EARLY_MIN_SCORE <= result[2] <= EARLY_MAX_SCORE
            and score_acceleration >= SCORE_ACCEL_MIN
            and volume_acceleration >= VOLUME_ACCEL_MIN
        )
        recent_early = conn.execute(
            """SELECT seen_at, price, score
               FROM early_events
               WHERE product=?
                 AND julianday(seen_at) >= julianday('now','-2 hours')
               ORDER BY id DESC
               LIMIT 1""",
            (product,),
        ).fetchone()
        sequence = conn.execute(
            """SELECT state, hold_count, early_score, last_score
               FROM momentum_sequences WHERE product=?""",
            (product,),
        ).fetchone()
        latest_momentum_state = conn.execute(
            """SELECT state
               FROM momentum_tracking
               WHERE product=?
               ORDER BY id DESC
               LIMIT 1""",
            (product,),
        ).fetchone()

        started_early_now = False
        if is_early and not recent_early and not sequence:
            conn.execute(
                """INSERT INTO early_events(
                       scan_id, seen_at, product, price, score,
                       score_accel, rel_volume, volume_accel
                   ) VALUES(?,?,?,?,?,?,?,?)""",
                (
                    scan_id, seen_at, result[0], result[1], result[2],
                    score_acceleration, result[5], volume_acceleration,
                ),
            )
            conn.execute(
                """INSERT OR REPLACE INTO momentum_sequences(
                       product, started_at, state, hold_count, early_score, last_score
                   ) VALUES(?,?,?,?,?,?)""",
                (result[0], seen_at, "EARLY", 0, result[2], result[2]),
            )
            record_state(
                conn, seen_at, result[0], "EARLY", result[2], previous_score, result[1]
            )
            alerts.append(
                f"🚨 EARLY {result[0]} — Score {result[2]} — "
                f"Jump +{score_acceleration:.1f} — Volume {volume_acceleration:.2f}x"
            )
            sequence = ("EARLY", 0, result[2], result[2])
            started_early_now = True

        # Recover a recent sequence if an older run stored EARLY but stopped early.
        if (
            not sequence
            and recent_early
            and (
                not latest_momentum_state
                or latest_momentum_state[0] != "FAILED"
            )
        ):
            conn.execute(
                """INSERT OR REPLACE INTO momentum_sequences(
                       product, started_at, state, hold_count, early_score, last_score
                   ) VALUES(?,?,?,?,?,?)""",
                (product, recent_early[0], "EARLY", 0, recent_early[2], result[2]),
            )
            record_state(
                conn,
                recent_early[0],
                product,
                "EARLY",
                recent_early[2],
                recent_early[2],
                recent_early[1],
            )
            sequence = ("EARLY", 0, recent_early[2], result[2])

        next_state = None
        hold_alert = False
        if sequence and not started_early_now:
            sequence_state, hold_count, early_score, last_score = sequence

            if result[2] <= FAIL_SCORE:
                next_state = "FAILED"
            elif result[3] in ("WATCH", "SIGNAL") and sequence_state not in (
                "CONFIRMED", "WATCH"
            ):
                next_state = "CONFIRMED"
            elif result[3] == "WATCH" and sequence_state == "CONFIRMED":
                next_state = "WATCH"
            elif previous_score - result[2] >= WEAKEN_SCORE_DROP:
                next_state = "WEAKENING"
            elif sequence_state == "EARLY":
                hold_count += 1
                if hold_count >= 2:
                    next_state = "STRENGTHENING"
                elif hold_count == 1:
                    hold_alert = True
            elif (
                sequence_state == "WEAKENING"
                and result[2] - previous_score >= STRENGTHEN_SCORE_GAIN
            ):
                next_state = "STRENGTHENING"

            if hold_alert:
                alerts.append(
                    f"⏳ HOLD 1 {result[0]} — Score {result[2]} — Price ${result[1]}"
                )

            if next_state:
                added = record_state(
                    conn,
                    seen_at,
                    result[0],
                    next_state,
                    result[2],
                    previous_score,
                    result[1],
                )
                if added:
                    alerts.append(
                        f"📊 {result[0]} — {next_state} — "
                        f"Score {result[2]} — Price ${result[1]}"
                    )

                if next_state == "FAILED":
                    conn.execute(
                        "DELETE FROM momentum_sequences WHERE product=?", (result[0],)
                    )
                else:
                    conn.execute(
                        """UPDATE momentum_sequences
                           SET state=?, hold_count=?, last_score=?
                           WHERE product=?""",
                        (next_state, hold_count, result[2], result[0]),
                    )
            else:
                conn.execute(
                    """UPDATE momentum_sequences
                       SET hold_count=?, last_score=?
                       WHERE product=?""",
                    (hold_count, result[2], result[0]),
                )

        conn.execute(
            """INSERT INTO scans(
                   scan_id, seen_at, product, price, score,
                   status, rsi, rel_volume, reason
               ) VALUES(?,?,?,?,?,?,?,?,?)""",
            (scan_id, seen_at, *result),
        )
        print(result[0], result[2], result[3])

        if result[3] in ("WATCH", "SIGNAL"):
            alerts.append(
                f"{result[0]} → {result[3]} — Score {result[2]} — Price ${result[1]}"
            )

    except Exception as exc:
        print("ERROR", product, exc)

conn.commit()
conn.close()

if alerts:
    requests.post(
        "https://ntfy.sh/gonzaleztradealerts",
        data=("\n".join(alerts)).encode("utf-8"),
        headers={"Title": "Crypto Scanner Alert"},
        timeout=10,
    )
