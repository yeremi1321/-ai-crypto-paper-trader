import streamlit as st
import pandas as pd
import numpy as np
import requests, sqlite3, time
from datetime import datetime, timezone

st.set_page_config(page_title="AI Crypto Paper Trader V1", page_icon="📈", layout="wide")

STARTING_BALANCE = 500.0
RISK_PER_TRADE = 5.0
DAILY_LOSS_LIMIT = 15.0
MAX_OPEN_POSITIONS = 3
DB = "paper_trader.db"

PRODUCTS = {
    "BTC": "BTC-USD",
    "ETH": "ETH-USD",
    "SOL": "SOL-USD",
    "DOGE": "DOGE-USD",
    "SHIB": "SHIB-USD",
    "AVAX": "AVAX-USD",
    "LINK": "LINK-USD",
}

def db():
    con = sqlite3.connect(DB)
    con.execute("""CREATE TABLE IF NOT EXISTS trades(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        opened_at TEXT, closed_at TEXT, symbol TEXT, side TEXT,
        entry REAL, stop REAL, target REAL, qty REAL,
        score REAL, status TEXT, exit_price REAL, pnl REAL, reason TEXT
    )""")
    con.commit()
    return con

def candles(product, granularity=900, limit=220):
    # Coinbase Exchange public candles endpoint; no trading credentials required.
    url = f"https://api.exchange.coinbase.com/products/{product}/candles"
    r = requests.get(url, params={"granularity": granularity}, timeout=10,
                     headers={"User-Agent":"paper-trader-v1"})
    r.raise_for_status()
    data = r.json()[:limit]
    df = pd.DataFrame(data, columns=["time","low","high","open","close","volume"])
    df = df.sort_values("time").reset_index(drop=True)
    for c in ["low","high","open","close","volume"]:
        df[c] = pd.to_numeric(df[c])
    return df

def indicators(df):
    x = df.copy()
    x["ema20"] = x.close.ewm(span=20).mean()
    x["ema50"] = x.close.ewm(span=50).mean()
    d = x.close.diff()
    gain = d.clip(lower=0).rolling(14).mean()
    loss = (-d.clip(upper=0)).rolling(14).mean()
    rs = gain / loss.replace(0, np.nan)
    x["rsi"] = 100 - (100/(1+rs))
    x["vol_avg"] = x.volume.rolling(20).mean()
    x["rel_vol"] = x.volume / x.vol_avg
    tr = pd.concat([(x.high-x.low), (x.high-x.close.shift()).abs(),
                    (x.low-x.close.shift()).abs()], axis=1).max(axis=1)
    x["atr"] = tr.rolling(14).mean()
    return x

def score_symbol(product):
    d15 = indicators(candles(product, 900))
    d60 = indicators(candles(product, 3600))
    a, h = d15.iloc[-1], d60.iloc[-1]
    score = 0
    reasons = []
    # Momentum 25
    if a.close > a.ema20: score += 10; reasons.append("15m above EMA20")
    if a.ema20 > a.ema50: score += 8; reasons.append("15m trend aligned")
    if 52 <= a.rsi <= 72: score += 7; reasons.append("RSI momentum healthy")
    # Volume 25
    rv = float(a.rel_vol) if pd.notna(a.rel_vol) else 0
    score += min(25, max(0, (rv-0.8)*18))
    if rv >= 1.5: reasons.append("relative volume elevated")
    # Structure 20
    prior_high = d15.high.iloc[-21:-1].max()
    if a.close > prior_high: score += 12; reasons.append("20-bar breakout")
    if h.close > h.ema20: score += 8; reasons.append("1h trend supportive")
    # Liquidity proxy 15: established Coinbase USD listing + normalized ATR
    atrp = (a.atr/a.close)*100 if a.close else 99
    if atrp < 4: score += 10
    if a.volume > 0: score += 5
    # Catalyst/AI deliberately excluded from score until validated.
    score = round(min(score, 85), 1)
    status = "SIGNAL" if score >= 80 else ("WATCH" if score >= 70 else "IGNORE")
    return {
        "product": product, "price": float(a.close), "score": score,
        "status": status, "rsi": round(float(a.rsi),1) if pd.notna(a.rsi) else None,
        "rel_volume": round(rv,2), "atr": float(a.atr),
        "reason": ", ".join(reasons)
    }

def account_stats(con):
    closed = pd.read_sql_query("SELECT * FROM trades WHERE status='CLOSED'", con)
    open_ = pd.read_sql_query("SELECT * FROM trades WHERE status='OPEN'", con)
    realized = closed.pnl.fillna(0).sum() if len(closed) else 0
    return STARTING_BALANCE + realized, open_, closed

def paper_entry(con, row):
    if row["status"] != "SIGNAL": return "Not a qualifying signal."
    bal, opens, closed = account_stats(con)
    if len(opens) >= MAX_OPEN_POSITIONS: return "Maximum open positions reached."
    today = datetime.now(timezone.utc).date().isoformat()
    today_pnl = closed[closed.closed_at.fillna("").str.startswith(today)].pnl.sum() if len(closed) else 0
    if today_pnl <= -DAILY_LOSS_LIMIT: return "Daily loss limit reached."
    entry = row["price"]
    stop_distance = max(row["atr"] * 1.25, entry * 0.0075)
    stop = entry - stop_distance
    target = entry + stop_distance * 2
    qty = RISK_PER_TRADE / stop_distance
    # Never use more than available simulated balance.
    qty = min(qty, bal / entry)
    con.execute("""INSERT INTO trades(opened_at,symbol,side,entry,stop,target,qty,score,status,reason)
                   VALUES(?,?,?,?,?,?,?,?,?,?)""",
                (datetime.now(timezone.utc).isoformat(), row["product"], "LONG",
                 entry, stop, target, qty, row["score"], "OPEN", row["reason"]))
    con.commit()
    return f"Paper trade opened: {row['product']}"

def mark_positions(con, scan):
    _, opens, _ = account_stats(con)
    prices = {r["product"]: r["price"] for r in scan}
    for _, t in opens.iterrows():
        px = prices.get(t.symbol)
        if px is None: continue
        exit_px, why = None, None
        if px <= t.stop: exit_px, why = t.stop, "STOP"
        elif px >= t.target: exit_px, why = t.target, "TARGET"
        if exit_px is not None:
            pnl = (exit_px - t.entry) * t.qty
            con.execute("""UPDATE trades SET closed_at=?,status='CLOSED',exit_price=?,pnl=?,reason=reason||?
                           WHERE id=?""",
                        (datetime.now(timezone.utc).isoformat(), exit_px, pnl, f" | {why}", int(t.id)))
    con.commit()

st.title("AI Crypto Paper Trader — V1")
st.caption("Paper trading only • No exchange keys • No real-money execution")

con = db()
if st.button("Run scanner now", type="primary"):
    with st.spinner("Pulling public market data and calculating signals..."):
        scan = []
        for name, product in PRODUCTS.items():
            try:
                scan.append(score_symbol(product))
            except Exception as e:
                scan.append({"product":product,"price":np.nan,"score":0,"status":"ERROR",
                             "rsi":None,"rel_volume":None,"atr":np.nan,"reason":str(e)})
        st.session_state["scan"] = scan
        mark_positions(con, scan)

scan = st.session_state.get("scan", [])
balance, opens, closed = account_stats(con)
realized = balance - STARTING_BALANCE
c1,c2,c3,c4 = st.columns(4)
c1.metric("Paper balance", f"${balance:,.2f}")
c2.metric("Realized P/L", f"${realized:,.2f}")
c3.metric("Open positions", len(opens))
c4.metric("Max risk / trade", f"${RISK_PER_TRADE:.2f}")

if scan:
    st.subheader("Live Scanner")
    show = pd.DataFrame(scan)[["product","price","score","status","rsi","rel_volume","reason"]]
    st.dataframe(show, use_container_width=True, hide_index=True)
    candidates = [r for r in scan if r["status"]=="SIGNAL"]
    if candidates:
        pick = st.selectbox("Paper-trade qualifying signal", [r["product"] for r in candidates])
        if st.button("Open simulated trade"):
            row = next(r for r in candidates if r["product"]==pick)
            st.success(paper_entry(con,row))
            st.rerun()
    else:
        st.info("No 80+ signal right now. V1 does not force trades.")

st.subheader("Open Paper Trades")
balance, opens, closed = account_stats(con)
st.dataframe(opens, use_container_width=True, hide_index=True)

st.subheader("Completed Trades")
st.dataframe(closed.sort_values("id", ascending=False) if len(closed) else closed,
             use_container_width=True, hide_index=True)

st.subheader("Risk Controls")
st.write(f"$500 starting balance • $5 max planned loss/trade • 3 open positions max • "
         f"$15 realized daily-loss cutoff • ≥2:1 target/risk • no leverage • no averaging down")
st.warning("This is an experimental paper-trading tool, not a guarantee of profitability. "
           "Its scoring rules must be validated on a meaningful sample before considering real money.")
