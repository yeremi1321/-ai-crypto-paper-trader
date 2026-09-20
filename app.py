import streamlit as st
import pandas as pd
import numpy as np
import requests, sqlite3, time
from datetime import datetime, timezone

st.set_page_config(page_title="AI Crypto Paper Trader V2", page_icon="📈", layout="wide")

STARTING_BALANCE = 500.0
RISK_PER_TRADE = 5.0
DAILY_LOSS_LIMIT = 15.0
MAX_OPEN_POSITIONS = 3
MIN_SCORE = 80
FEE_RATE = 0.006       # conservative paper estimate; tune to actual venue/tier later
SLIPPAGE_RATE = 0.001  # conservative paper estimate
DB = "paper_trader_v2.db"

PRODUCTS = {
    "BTC":"BTC-USD","ETH":"ETH-USD","SOL":"SOL-USD","DOGE":"DOGE-USD",
    "SHIB":"SHIB-USD","AVAX":"AVAX-USD","LINK":"LINK-USD","ADA":"ADA-USD",
    "XRP":"XRP-USD","LTC":"LTC-USD","BCH":"BCH-USD"
}

def con():
    c = sqlite3.connect(DB)
    c.execute("""CREATE TABLE IF NOT EXISTS trades(
      id INTEGER PRIMARY KEY AUTOINCREMENT, opened_at TEXT, closed_at TEXT,
      product TEXT, entry REAL, stop REAL, target REAL, qty REAL, score REAL,
      status TEXT, exit_price REAL, gross_pnl REAL, costs REAL, net_pnl REAL, reason TEXT)""")
    c.execute("""CREATE TABLE IF NOT EXISTS signals(
      id INTEGER PRIMARY KEY AUTOINCREMENT, seen_at TEXT, product TEXT, price REAL,
      score REAL, status TEXT, rsi REAL, rel_volume REAL, reason TEXT)""")
    c.commit()
    return c

def candles(product, granularity, limit=220):
    u=f"https://api.exchange.coinbase.com/products/{product}/candles"
    r=requests.get(u,params={"granularity":granularity},headers={"User-Agent":"paper-v2"},timeout=12)
    r.raise_for_status()
    d=pd.DataFrame(r.json()[:limit],columns=["time","low","high","open","close","volume"])
    if len(d)<60: raise ValueError("Not enough candle history")
    d=d.sort_values("time").reset_index(drop=True)
    for x in ["low","high","open","close","volume"]: d[x]=pd.to_numeric(d[x])
    return d

def completed(df, granularity):
    now=time.time()
    # Exclude any candle whose interval has not fully closed.
    return df[df.time + granularity <= now].copy()

def ind(d):
    x=d.copy()
    x["ema20"]=x.close.ewm(span=20,adjust=False).mean()
    x["ema50"]=x.close.ewm(span=50,adjust=False).mean()
    delta=x.close.diff()
    gain=delta.clip(lower=0).ewm(alpha=1/14,adjust=False).mean()
    loss=(-delta.clip(upper=0)).ewm(alpha=1/14,adjust=False).mean()
    rs=gain/loss.replace(0,np.nan)
    x["rsi"]=100-(100/(1+rs))
    x["vavg"]=x.volume.rolling(20).mean()
    x["rv"]=x.volume/x.vavg
    tr=pd.concat([(x.high-x.low),(x.high-x.close.shift()).abs(),(x.low-x.close.shift()).abs()],axis=1).max(axis=1)
    x["atr"]=tr.rolling(14).mean()
    return x

def score(product):
    d15=ind(completed(candles(product,900),900))
    d1h=ind(completed(candles(product,3600),3600))
    a,h=d15.iloc[-1],d1h.iloc[-1]
    s=0.; why=[]
    # Momentum 25
    if a.close>a.ema20: s+=10; why.append("15m > EMA20")
    if a.ema20>a.ema50: s+=8; why.append("15m trend")
    if 52<=a.rsi<=72: s+=7; why.append("healthy RSI")
    # Volume 25
    rv=float(a.rv) if pd.notna(a.rv) else 0
    volpts=min(25,max(0,(rv-.8)*18))
    s+=volpts
    if rv>=1.5: why.append("elevated volume")
    # Structure 20
    ph=d15.high.iloc[-21:-1].max()
    if a.close>ph: s+=12; why.append("20-bar breakout")
    if h.close>h.ema20: s+=8; why.append("1h trend")
    # Tradability 15
    atrp=(a.atr/a.close)*100
    if .15 <= atrp <= 4: s+=10; why.append("tradable volatility")
    if a.volume>0: s+=5
    # Keep 15 points reserved for future catalyst research; do not fake them.
    s=round(min(s,85),1)
    status="SIGNAL" if s>=MIN_SCORE else ("WATCH" if s>=70 else "IGNORE")
    return dict(product=product,price=float(a.close),score=s,status=status,
                rsi=round(float(a.rsi),1),rel_volume=round(rv,2),atr=float(a.atr),
                reason=", ".join(why))

def save_signals(c, rows):
    ts=datetime.now(timezone.utc).isoformat()
    for r in rows:
        if r["status"]=="ERROR": continue
        c.execute("""INSERT INTO signals(seen_at,product,price,score,status,rsi,rel_volume,reason)
                     VALUES(?,?,?,?,?,?,?,?)""",
                  (ts,r["product"],r["price"],r["score"],r["status"],r["rsi"],r["rel_volume"],r["reason"]))
    c.commit()

def stats(c):
    tr=pd.read_sql_query("SELECT * FROM trades",c)
    closed=tr[tr.status=="CLOSED"] if len(tr) else tr
    opened=tr[tr.status=="OPEN"] if len(tr) else tr
    net=float(closed.net_pnl.fillna(0).sum()) if len(closed) else 0
    bal=STARTING_BALANCE+net
    wins=int((closed.net_pnl>0).sum()) if len(closed) else 0
    wr=(wins/len(closed)*100) if len(closed) else 0
    gp=closed.loc[closed.net_pnl>0,"net_pnl"].sum() if len(closed) else 0
    gl=-closed.loc[closed.net_pnl<0,"net_pnl"].sum() if len(closed) else 0
    pf=(gp/gl) if gl>0 else (float("inf") if gp>0 else 0)
    if len(closed):
        curve=STARTING_BALANCE+closed.net_pnl.fillna(0).cumsum()
        dd=((curve-curve.cummax())/curve.cummax()*100).min()
    else: dd=0
    return bal,opened,closed,wr,pf,dd

def open_paper(c,r):
    bal,op,cl,*_=stats(c)
    if r["status"]!="SIGNAL": return "Not a qualifying signal."
    if len(op)>=MAX_OPEN_POSITIONS: return "Maximum open positions reached."
    today=datetime.now(timezone.utc).date().isoformat()
    today_net=cl[cl.closed_at.fillna("").str.startswith(today)].net_pnl.sum() if len(cl) else 0
    if today_net<=-DAILY_LOSS_LIMIT: return "Daily loss cutoff reached."
    entry=r["price"]*(1+SLIPPAGE_RATE)
    dist=max(r["atr"]*1.25,entry*.0075)
    stop=entry-dist; target=entry+2*dist
    qty=min(RISK_PER_TRADE/dist,bal/entry)
    c.execute("""INSERT INTO trades(opened_at,product,entry,stop,target,qty,score,status,reason)
                 VALUES(?,?,?,?,?,?,?,?,?)""",
              (datetime.now(timezone.utc).isoformat(),r["product"],entry,stop,target,qty,r["score"],"OPEN",r["reason"]))
    c.commit()
    return f"Simulated {r['product']} position opened."

def mark(c,rows):
    _,op,*_=stats(c)
    px={r["product"]:r["price"] for r in rows if r["status"]!="ERROR"}
    for _,t in op.iterrows():
        p=px.get(t["product"])
        if p is None: continue
        exitp=None; why=""
        if p<=t.stop: exitp=t.stop*(1-SLIPPAGE_RATE); why="STOP"
        elif p>=t.target: exitp=t.target*(1-SLIPPAGE_RATE); why="TARGET"
        if exitp:
            gross=(exitp-t.entry)*t.qty
            costs=(t.entry*t.qty+exitp*t.qty)*FEE_RATE
            net=gross-costs
            c.execute("""UPDATE trades SET closed_at=?,status='CLOSED',exit_price=?,
                         gross_pnl=?,costs=?,net_pnl=?,reason=reason||? WHERE id=?""",
                      (datetime.now(timezone.utc).isoformat(),exitp,gross,costs,net,f" | {why}",int(t.id)))
    c.commit()

st.title("AI Crypto Paper Trader — V2")
st.caption("Research prototype • Paper trading only • Completed candles • No exchange credentials")

c=con()
if st.button("Run V2 scanner",type="primary"):
    rows=[]
    with st.spinner("Scanning completed candles..."):
        for _,p in PRODUCTS.items():
            try: rows.append(score(p))
            except Exception as e:
                rows.append(dict(product=p,price=np.nan,score=0,status="ERROR",rsi=np.nan,
                                 rel_volume=np.nan,atr=np.nan,reason=str(e)))
    st.session_state["scan"]=rows
    save_signals(c,rows)
    mark(c,rows)

rows=st.session_state.get("scan",[])
bal,op,cl,wr,pf,dd=stats(c)
a,b,d,e=st.columns(4)
a.metric("Paper balance",f"${bal:,.2f}")
b.metric("Net realized P/L",f"${bal-STARTING_BALANCE:,.2f}")
d.metric("Open positions",len(op))
e.metric("Risk / trade",f"${RISK_PER_TRADE:.2f}")

m1,m2,m3=st.columns(3)
m1.metric("Win rate",f"{wr:.1f}%")
m2.metric("Profit factor","—" if pf==0 else ("∞" if np.isinf(pf) else f"{pf:.2f}"))
m3.metric("Max realized drawdown",f"{dd:.1f}%")

if rows:
    st.caption("Last scan: "+datetime.now().astimezone().strftime("%Y-%m-%d %I:%M:%S %p %Z"))
    st.subheader("Live Scanner")
    df=pd.DataFrame(rows)
    st.dataframe(df[["product","price","score","status","rsi","rel_volume","reason"]],
                 use_container_width=True,hide_index=True)
    sig=[r for r in rows if r["status"]=="SIGNAL"]
    if sig:
        pick=st.selectbox("Qualifying signal",[r["product"] for r in sig])
        st.warning("V2 logs signals automatically, but simulated entries still require your tap while we validate the 80+ threshold.")
        if st.button("Open simulated trade"):
            st.success(open_paper(c,next(r for r in sig if r["product"]==pick)))
            st.rerun()
    else:
        st.info("No 80+ setup. V2 will not lower the threshold just to create a trade.")

st.subheader("Open Paper Trades")
st.dataframe(op,use_container_width=True,hide_index=True)

st.subheader("Completed Trades")
st.dataframe(cl.sort_values("id",ascending=False) if len(cl) else cl,use_container_width=True,hide_index=True)

st.subheader("Signal Log")
signals=pd.read_sql_query("SELECT * FROM signals ORDER BY id DESC LIMIT 200",c)
st.dataframe(signals,use_container_width=True,hide_index=True)

st.caption("V2 uses estimated fees/slippage for testing. Exact costs depend on the eventual venue and fee tier. "
           "No strategy can eliminate losses; validate a meaningful sample before considering real money.")
