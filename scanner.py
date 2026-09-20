import pandas as pd
import numpy as np
import requests, sqlite3, time, os
from datetime import datetime, timezone

DB="paper_trader_v4.db"
PRODUCTS=["BTC-USD","ETH-USD","SOL-USD","DOGE-USD","SHIB-USD","AVAX-USD",
          "LINK-USD","ADA-USD","XRP-USD","LTC-USD","BCH-USD"]
EARLY_MIN_SCORE = 45
EARLY_MAX_SCORE = 69.9
SCORE_ACCEL_MIN = 8
VOLUME_ACCEL_MIN = 1.25
STRENGTHEN_SCORE_GAIN = 5
WEAKEN_SCORE_DROP = 8
FAIL_SCORE = 35


def db():
    c = sqlite3.connect(DB)

    c.execute("""CREATE TABLE IF NOT EXISTS scans(
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

    c.execute("""CREATE TABLE IF NOT EXISTS early_events(
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

    c.execute("""CREATE TABLE IF NOT EXISTS momentum_tracking(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        seen_at TEXT,
        product TEXT,
        state TEXT,
        score REAL,
        previous_score REAL,
        price REAL
    )""")

    c.execute("""CREATE TABLE IF NOT EXISTS momentum_sequences(
        product TEXT PRIMARY KEY,
        started_at TEXT,
        state TEXT,
        hold_count INTEGER,
        early_score REAL,
        last_score REAL
    )""")

    c.commit()
    return c

def candles(product,g,limit=220):
    u=f"https://api.exchange.coinbase.com/products/{product}/candles"
    r=requests.get(u,params={"granularity":g},headers={"User-Agent":"paper-v4"},timeout=15)
    r.raise_for_status()
    x=pd.DataFrame(r.json()[:limit],columns=["time","low","high","open","close","volume"])
    x=x.sort_values("time").reset_index(drop=True)
    for z in ["low","high","open","close","volume"]: x[z]=pd.to_numeric(x[z])
    return x[x.time+g<=time.time()].copy()

def indicators(x):
    x=x.copy()
    x["ema20"]=x.close.ewm(span=20,adjust=False).mean()
    x["ema50"]=x.close.ewm(span=50,adjust=False).mean()
    d=x.close.diff()
    gain=d.clip(lower=0).ewm(alpha=1/14,adjust=False).mean()
    loss=(-d.clip(upper=0)).ewm(alpha=1/14,adjust=False).mean()
    x["rsi"]=100-(100/(1+(gain/loss.replace(0,np.nan))))
    x["rv"]=x.volume/x.volume.rolling(20).mean()
    tr=pd.concat([(x.high-x.low),(x.high-x.close.shift()).abs(),
                  (x.low-x.close.shift()).abs()],axis=1).max(axis=1)
    x["atr"]=tr.rolling(14).mean()
    return x

def scan_one(p):
    q=indicators(candles(p,900)); h=indicators(candles(p,3600))
    a,b=q.iloc[-1],h.iloc[-1]
    s=0.; why=[]
    if a.close>a.ema20: s+=10; why.append("15m>EMA20")
    if a.ema20>a.ema50: s+=8; why.append("15m trend")
    if 52<=a.rsi<=72: s+=7; why.append("RSI momentum")
    rv=float(a.rv) if pd.notna(a.rv) else 0
    s+=min(25,max(0,(rv-.8)*18))
    if rv>=1.5: why.append("volume surge")
    if a.close>q.high.iloc[-21:-1].max(): s+=12; why.append("20-bar breakout")
    if b.close>b.ema20: s+=8; why.append("1h trend")
    atrp=(a.atr/a.close)*100
    if .15<=atrp<=4: s+=10; why.append("tradable ATR")
    if a.volume>0: s+=5
    s=round(min(s,85),1)
    status="SIGNAL" if s>=80 else ("WATCH" if s>=70 else "IGNORE")
    return (p,float(a.close),s,status,round(float(a.rsi),1),round(rv,2),", ".join(why))

c = db()
now = datetime.now(timezone.utc)
sid = now.strftime("%Y%m%dT%H%M%SZ")
alerts = []

for p in PRODUCTS:
    try:
        r = scan_one(p)
        prev = c.execute(
            """SELECT score, rel_volume
               FROM scans
               WHERE product=?
               ORDER BY id DESC
               LIMIT 1""",
            (p,)
        ).fetchone()

        early = False
        score_accel = 0
        volume_accel = 0

        if prev:
            prev_score, prev_rv = prev
            score_accel = r[2] - prev_score

            if prev_rv and prev_rv > 0:
                volume_accel = r[5] / prev_rv

            early = (
                EARLY_MIN_SCORE <= r[2] <= EARLY_MAX_SCORE
                and score_accel >= SCORE_ACCEL_MIN
                and volume_accel >= VOLUME_ACCEL_MIN
            )

        had_early = c.execute(
            "SELECT 1 FROM early_events WHERE product=? AND julianday(seen_at) >= julianday('now','-2 hours') ORDER BY id DESC LIMIT 1",
            (p,)
        ).fetchone()

        if early and not had_early:
            print("EARLY", r[0], r[2])

            alerts.append(
                f"🚨 EARLY {r[0]} — Score {r[2]} — "
                f"Jump +{score_accel:.1f} — Volume {volume_accel:.2f}x"
            )

            c.execute(
                "INSERT INTO early_events(scan_id, seen_at, product, price, score, score_accel, rel_volume, volume_accel) VALUES(?,?,?,?,?,?,?,?)",
                (sid, now.isoformat(), r[0], r[1], r[2], score_accel, r[5], volume_accel)
            )
            c.execute(
                "INSERT OR REPLACE INTO momentum_sequences(product, started_at, state, hold_count, early_score, last_score) VALUES(?,?,?,?,?,?)",
                (r[0], now.isoformat(), "EARLY", 0, r[2], r[2])
            )
        last_state = c.execute(
            "SELECT state FROM momentum_tracking WHERE product=? ORDER BY id DESC LIMIT 1",
            (p,)
        ).fetchone()
        sequence = c.execute(
            "SELECT state, hold_count, early_score, last_score FROM momentum_sequences WHERE product=?",
            (p,)
        ).fetchone()
        if sequence and had_early:
            seq_state, hold_count, early_score, last_score = sequence

            if seq_state == "EARLY" and r[2] > FAIL_SCORE and last_score - r[2] < WEAKEN_SCORE_DROP:
                hold_count += 1

                c.execute(
                    "UPDATE momentum_sequences SET hold_count=?, last_score=? WHERE product=?",
                    (hold_count, r[2], r[0])
                )

                if hold_count == 1:
                    alerts.append(
                        f"⏳ HOLD 1 {r[0]} — Score {r[2]} — Price ${r[1]}"
                    )

                elif hold_count >= 2:
                    c.execute(
                        "UPDATE momentum_sequences SET state=? WHERE product=?",
                        ("STRENGTHENING", r[0])
                    )

                    alerts.append(
                        f"✅ HOLD 2 {r[0]} — STRENGTHENING — Score {r[2]} — Price ${r[1]}"
                    )
        state = None
              if prev and sequence:
            prev_score = prev[0]
            

            if r[3] in ("WATCH", "SIGNAL"):
                state = "CONFIRMED"
            elif r[2] <= FAIL_SCORE:
                state = "FAILED"
            elif hold_count >= 2 and r[2] - prev_score >= STRENGTHEN_SCORE_GAIN:
                state = "STRENGTHENING"
            elif prev_score - r[2] >= WEAKEN_SCORE_DROP:
                state = "WEAKENING"
            if state == "FAILED":
                c.execute(
                    "DELETE FROM momentum_sequences WHERE product=?",
                    (r[0],)
                )
                sequence = None
            if state and (not last_state or last_state[0] != state):
             c.execute(
                "INSERT INTO momentum_tracking(seen_at, product, state, score, previous_score, price) VALUES(?,?,?,?,?,?)",
                (now.isoformat(), r[0], state, r[2], prev_score, r[1])
            )

             alerts.append(
                f"📊 {r[0]} — {state} — Score {r[2]} — Price ${r[1]}"
            )
        c.execute(
            "INSERT INTO scans(scan_id, seen_at, product, price, score, status, rsi, rel_volume, reason) VALUES(?,?,?,?,?,?,?,?,?)",
            (sid, now.isoformat(), *r)
        )

        print(r[0], r[2], r[3])

        if r[3] in ("WATCH", "SIGNAL"):
            alerts.append(
                f"{r[0]} → {r[3]} — Score {r[2]} — Price ${r[1]}"
            )

    except Exception as e:
        print("ERROR", p, e)

c.commit()
c.close()

if alerts:
    requests.post(
        "https://ntfy.sh/gonzaleztradealerts",
        data=("\n".join(alerts)).encode("utf-8"),
        headers={"Title": "Crypto Scanner Alert"},
        timeout=10
    )
