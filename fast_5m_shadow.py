import argparse
import sqlite3
from datetime import datetime, timezone

from scanner import PRODUCTS, candles, indicators

DB = "fast_5m_shadow.db"
VERSION = "FAST_5M_SHADOW_V1"


def init_db(path):
    conn = sqlite3.connect(path)
    conn.execute("""CREATE TABLE IF NOT EXISTS fast_5m_shadow(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        observed_at TEXT NOT NULL,
        product TEXT NOT NULL,
        version TEXT NOT NULL,
        price REAL NOT NULL,
        score REAL NOT NULL,
        rel_volume REAL NOT NULL,
        rsi REAL,
        fast_signal INTEGER NOT NULL,
        return_15m_pct REAL,
        return_30m_pct REAL,
        return_60m_pct REAL,
        UNIQUE(observed_at, product)
    )""")
    conn.commit()
    return conn


def score_5m(product):
    five = indicators(candles(product, 300))
    hour = indicators(candles(product, 3600))
    current, h = five.iloc[-1], hour.iloc[-1]
    score = 0.0
    if current.close > current.ema20:
        score += 10
    if current.ema20 > current.ema50:
        score += 8
    if 52 <= current.rsi <= 72:
        score += 7
    rv = float(current.rv) if current.rv == current.rv else 0.0
    score += min(25, max(0, (rv - 0.8) * 18))
    if current.close > five.high.iloc[-21:-1].max():
        score += 12
    if h.close > h.ema20:
        score += 8
    atr_pct = (current.atr / current.close) * 100
    if 0.15 <= atr_pct <= 4:
        score += 10
    if current.volume > 0:
        score += 5
    score = round(min(score, 85), 1)
    return float(current.close), score, rv, float(current.rsi)


def update_outcomes(conn, now, prices):
    rows = conn.execute("""SELECT id, observed_at, product, price,
        return_15m_pct, return_30m_pct, return_60m_pct
        FROM fast_5m_shadow
        WHERE return_15m_pct IS NULL OR return_30m_pct IS NULL OR return_60m_pct IS NULL""").fetchall()
    for row_id, observed_at, product, entry, r15, r30, r60 in rows:
        price = prices.get(product)
        if price is None:
            continue
        age = (now - datetime.fromisoformat(observed_at)).total_seconds() / 60
        ret = (price / entry - 1) * 100
        if age >= 15 and r15 is None: r15 = ret
        if age >= 30 and r30 is None: r30 = ret
        if age >= 60 and r60 is None: r60 = ret
        conn.execute("""UPDATE fast_5m_shadow SET return_15m_pct=?,
            return_30m_pct=?, return_60m_pct=? WHERE id=?""",
            (r15, r30, r60, row_id))


def summary(conn):
    total = conn.execute("SELECT COUNT(*) FROM fast_5m_shadow").fetchone()[0]
    signals = conn.execute("SELECT COUNT(*) FROM fast_5m_shadow WHERE fast_signal=1").fetchone()[0]
    print(f"FAST5 SUMMARY observations={total} signals={signals}")
    for col, label in (("return_15m_pct","15m"),("return_30m_pct","30m"),("return_60m_pct","60m")):
        vals = [r[0] for r in conn.execute(
            f"SELECT {col} FROM fast_5m_shadow WHERE fast_signal=1 AND {col} IS NOT NULL")]
        if vals:
            print(f"FAST5 {label} samples={len(vals)} win_rate={sum(v>0 for v in vals)/len(vals)*100:.1f}% avg_return={sum(vals)/len(vals):+.3f}%")
        else:
            print(f"FAST5 {label} samples=0")


def run(path):
    conn = init_db(path)
    now = datetime.now(timezone.utc)
    observations = []
    for product in PRODUCTS:
        try:
            price, score, rv, rsi = score_5m(product)
            observations.append((product, price, score, rv, rsi))
        except Exception as exc:
            print(f"{product} FAST5 error: {exc}")
    prices = {x[0]: x[1] for x in observations}
    update_outcomes(conn, now, prices)
    stamp = now.isoformat()
    for product, price, score, rv, rsi in observations:
        signal = int(score >= 70)
        conn.execute("""INSERT OR IGNORE INTO fast_5m_shadow(
            observed_at, product, version, price, score, rel_volume, rsi, fast_signal
        ) VALUES(?,?,?,?,?,?,?,?)""", (stamp, product, VERSION, price, score, rv, rsi, signal))
        print(product, "FAST5_SIGNAL" if signal else "FAST5_OBSERVE", score)
    conn.commit()
    summary(conn)
    conn.close()


def self_test():
    conn = init_db(":memory:")
    assert conn.execute("SELECT COUNT(*) FROM fast_5m_shadow").fetchone()[0] == 0
    summary(conn)
    conn.close()
    print("fast_5m_shadow self-test passed")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--db", default=DB)
    p.add_argument("--self-test", action="store_true")
    a = p.parse_args()
    self_test() if a.self_test else run(a.db)
