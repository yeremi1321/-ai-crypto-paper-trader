import streamlit as st
import pandas as pd
import numpy as np
import requests, sqlite3, time
from datetime import datetime, timezone, timedelta

st.set_page_config(page_title="AI Crypto Paper Trader V3", page_icon="📈", layout="wide")

STARTING_BALANCE=500.0
RISK_PER_TRADE=5.0
DAILY_LOSS_LIMIT=15.0
MAX_OPEN_POSITIONS=3
MIN_SCORE=80
WATCH_SCORE=70
FEE_RATE=0.006
SLIPPAGE_RATE=0.001
DB="paper_trader_v3.db"

PRODUCTS=["BTC-USD","ETH-USD","SOL-USD","DOGE-USD","SHIB-USD","AVAX-USD",
          "LINK-USD","ADA-USD","XRP-USD","LTC-USD","BCH-USD"]

def db():
    c=sqlite3.connect(DB)
    c.execute("""CREATE TABLE IF NOT EXISTS scans(
      id INTEGER PRIMARY KEY AUTOINCREMENT, scan_id TEXT, seen_at TEXT, product TEXT,
      price REAL, score REAL, status TEXT, rsi REAL, rel_volume REAL, reason TEXT)""")
    c.execute("""CREATE TABLE IF NOT EXISTS trades(
      id INTEGER PRIMARY KEY AUTOINCREMENT, opened_at TEXT, closed_at TEXT, product TEXT,
      entry REAL, stop REAL, target REAL, qty REAL, score REAL, status TEXT,
      exit_price REAL, gross_pnl REAL, costs REAL, net_pnl REAL, reason TEXT)""")
    c.commit(); return c

def candles(product,g,limit=220):
    u=f"https://api.exchange.coinbase.com/products/{product}/candles"
    r=requests.get(u,params={"granularity":g},headers={"User-Agent":"paper-v3"},timeout=12)
    r.raise_for_status()
    x=pd.DataFrame(r.json()[:limit],columns=["time","low","high","open","close","volume"])
    if len(x)<60: raise ValueError("insufficient history")
    x=x.sort_values("time").reset_index(drop=True)
    for z in ["low","high","open","close","volume"]: x[z]=pd.to_numeric(x[z])
    return x[x.time+g<=time.time()].copy()

def indicators(x):
    x=x.copy()
    x["ema20"]=x.close.ewm(span=20,adjust=False).mean()
    x["ema50"]=x.close.ewm(span=50,adjust=False).mean()
    d=x.close.diff()
    g=d.clip(lower=0).ewm(alpha=1/14,adjust=False).mean()
    l=(-d.clip(upper=0)).ewm(alpha=1/14,adjust=False).mean()
    x["rsi"]=100-(100/(1+(g/l.replace(0,np.nan))))
    x["rv"]=x.volume/x.volume.rolling(20).mean()
    tr=pd.concat([(x.high-x.low),(x.high-x.close.shift()).abs(),(x.low-x.close.shift()).abs()],axis=1).max(axis=1)
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
    status="SIGNAL" if s>=MIN_SCORE else ("WATCH" if s>=WATCH_SCORE else "IGNORE")
    return dict(product=p,price=float(a.close),score=s,status=status,
                rsi=round(float(a.rsi),1),rel_volume=round(rv,2),atr=float(a.atr),
                reason=", ".join(why))

def run_scan(c):
    rows=[]
    for p in PRODUCTS:
        try: rows.append(scan_one(p))
        except Exception as e:
            rows.append(dict(product=p,price=np.nan,score=0,status="ERROR",rsi=np.nan,
                             rel_volume=np.nan,atr=np.nan,reason=str(e)))
    now=datetime.now(timezone.utc); sid=now.strftime("%Y%m%dT%H%M%SZ")
    for r in rows:
        if r["status"]!="ERROR":
            c.execute("""INSERT INTO scans(scan_id,seen_at,product,price,score,status,rsi,rel_volume,reason)
                         VALUES(?,?,?,?,?,?,?,?,?)""",
                      (sid,now.isoformat(),r["product"],r["price"],r["score"],r["status"],
                       r["rsi"],r["rel_volume"],r["reason"]))
    c.commit()
    return rows

def transitions(c):
    d=pd.read_sql_query("SELECT * FROM scans ORDER BY id",c)
    if len(d)<2: return pd.DataFrame()
    out=[]
    for p,g in d.groupby("product"):
        g=g.sort_values("id")
        if len(g)>=2:
            x,y=g.iloc[-2],g.iloc[-1]
            if x.status!=y.status:
                out.append({"product":p,"from":x.status,"to":y.status,
                            "old_score":x.score,"new_score":y.score,"seen_at":y.seen_at})
    return pd.DataFrame(out)

def forward_performance(c):
    d=pd.read_sql_query("SELECT * FROM scans ORDER BY seen_at",c)
    if not len(d): return pd.DataFrame()
    d["seen_at"]=pd.to_datetime(d.seen_at,utc=True)
    now=pd.Timestamp.now(tz="UTC")
    out=[]
    # Compare each historical observation with a later recorded scan nearest 1h/4h.
    for _,r in d.iterrows():
        future=d[(d["product"]==r["product"]) & (d["seen_at"]>r["seen_at"])]
        row={"product":r["product"],"seen_at":r["seen_at"],"score":r["score"],"status":r["status"],"price":r["price"]}
        for label,hours in [("1h",1),("4h",4)]:
            target=r["seen_at"]+pd.Timedelta(hours=hours)
            cand=future[future.seen_at>=target]
            if len(cand):
                z=cand.iloc[0]
                row[f"return_{label}_pct"]=(z.price/r.price-1)*100
            else: row[f"return_{label}_pct"]=np.nan
        out.append(row)
    return pd.DataFrame(out)

def trade_stats(c):
    t=pd.read_sql_query("SELECT * FROM trades",c)
    closed=t[t.status=="CLOSED"] if len(t) else t
    op=t[t.status=="OPEN"] if len(t) else t
    net=closed.net_pnl.fillna(0).sum() if len(closed) else 0
    wr=((closed.net_pnl>0).mean()*100) if len(closed) else 0
    gp=closed.loc[closed.net_pnl>0,"net_pnl"].sum() if len(closed) else 0
    gl=-closed.loc[closed.net_pnl<0,"net_pnl"].sum() if len(closed) else 0
    pf=gp/gl if gl>0 else (np.inf if gp>0 else 0)
    return STARTING_BALANCE+net,op,closed,wr,pf

def open_trade(c,r):
    bal,op,closed,*_=trade_stats(c)
    if r["status"]!="SIGNAL": return "Not a qualifying signal."
    if len(op)>=MAX_OPEN_POSITIONS: return "Maximum open positions reached."
    today=datetime.now(timezone.utc).date().isoformat()
    todaynet=closed[closed.closed_at.fillna("").str.startswith(today)].net_pnl.sum() if len(closed) else 0
    if todaynet<=-DAILY_LOSS_LIMIT: return "Daily loss cutoff reached."
    entry=r["price"]*(1+SLIPPAGE_RATE)
    dist=max(r["atr"]*1.25,entry*.0075)
    stop=entry-dist; target=entry+2*dist
    qty=min(RISK_PER_TRADE/dist,bal/entry)
    c.execute("""INSERT INTO trades(opened_at,product,entry,stop,target,qty,score,status,reason)
                 VALUES(?,?,?,?,?,?,?,?,?)""",
              (datetime.now(timezone.utc).isoformat(),r["product"],entry,stop,target,qty,r["score"],"OPEN",r["reason"]))
    c.commit(); return f"Opened simulated {r['product']} trade."

def mark(c,rows):
    _,op,*_=trade_stats(c)
    prices={r["product"]:r["price"] for r in rows if r["status"]!="ERROR"}
    for _,t in op.iterrows():
        p=prices.get(t["product"])
        if p is None: continue
        xp=None; why=""
        if p<=t.stop: xp=t.stop*(1-SLIPPAGE_RATE); why="STOP"
        elif p>=t.target: xp=t.target*(1-SLIPPAGE_RATE); why="TARGET"
        if xp:
            gross=(xp-t.entry)*t.qty
            costs=(t.entry*t.qty+xp*t.qty)*FEE_RATE
            net=gross-costs
            c.execute("""UPDATE trades SET closed_at=?,status='CLOSED',exit_price=?,gross_pnl=?,
                         costs=?,net_pnl=?,reason=reason||? WHERE id=?""",
                      (datetime.now(timezone.utc).isoformat(),xp,gross,costs,net,f" | {why}",int(t.id)))
    c.commit()

c=db()
st.title("AI Crypto Paper Trader — V3")
st.caption("Monitoring + evidence collection • Paper trading only • No real-money execution")

if st.button("Scan & record now",type="primary"):
    with st.spinner("Scanning completed candles and recording observations..."):
        rows=run_scan(c); mark(c,rows); st.session_state["rows"]=rows

rows=st.session_state.get("rows",[])
bal,op,closed,wr,pf=trade_stats(c)
scans=pd.read_sql_query("SELECT * FROM scans",c)
scan_count=scans.scan_id.nunique() if len(scans) else 0

a,b,d,e=st.columns(4)
a.metric("Paper balance",f"${bal:,.2f}")
b.metric("Recorded scans",scan_count)
d.metric("Open positions",len(op))
e.metric("Risk / trade",f"${RISK_PER_TRADE:.2f}")
x,y=st.columns(2)
x.metric("Win rate",f"{wr:.1f}%")
y.metric("Profit factor","—" if pf==0 else ("∞" if np.isinf(pf) else f"{pf:.2f}"))

if rows:
    st.subheader("Current Scanner")
    cur=pd.DataFrame(rows)
    st.dataframe(cur[["product","price","score","status","rsi","rel_volume","reason"]],
                 use_container_width=True,hide_index=True)
    sig=[r for r in rows if r["status"]=="SIGNAL"]
    if sig:
        pick=st.selectbox("80+ qualifying signal",[r["product"] for r in sig])
        if st.button("Open simulated trade"):
            st.success(open_trade(c,next(r for r in sig if r["product"]==pick))); st.rerun()
    else: st.info("No 80+ setup. Threshold remains unchanged.")

st.subheader("Status Changes")
tr=transitions(c)
st.dataframe(tr if len(tr) else pd.DataFrame(columns=["product","from","to","old_score","new_score","seen_at"]),
             use_container_width=True,hide_index=True)

st.subheader("Score History")
if len(scans):
    choice=st.selectbox("Asset",PRODUCTS)
    hist=scans[scans["product"]==choice].copy()
    hist["seen_at"]=pd.to_datetime(hist.seen_at)
    if len(hist): st.line_chart(hist.set_index("seen_at")["score"])
else: st.info("Run scans over time to build score history.")

st.subheader("Forward Performance Research")
fp=forward_performance(c)
if len(fp):
    st.dataframe(fp.sort_values("seen_at",ascending=False).head(200),use_container_width=True,hide_index=True)
    mature=fp.dropna(subset=["return_1h_pct"])
    if len(mature):
        buckets=pd.cut(mature.score,bins=[0,40,50,60,70,80,101],right=False)
        summary=mature.assign(score_bucket=buckets).groupby("score_bucket",observed=True).agg(
            observations=("score","size"),avg_1h_return_pct=("return_1h_pct","mean"),
            median_1h_return_pct=("return_1h_pct","median")).reset_index()
        st.caption("Research summary by score bucket (not a recommendation)")
        st.dataframe(summary,use_container_width=True,hide_index=True)
else: st.info("Forward-return measurements appear after enough scans are recorded at least an hour apart.")

st.subheader("Open Paper Trades")
st.dataframe(op,use_container_width=True,hide_index=True)
st.subheader("Completed Trades")
st.dataframe(closed.sort_values("id",ascending=False) if len(closed) else closed,use_container_width=True,hide_index=True)

st.warning("V3 records only while the app is running and a scan is triggered. Streamlit Community Cloud can hibernate "
           "inactive apps, and local files are not guaranteed permanent. Do not treat this deployment as 24/7 monitoring.")
