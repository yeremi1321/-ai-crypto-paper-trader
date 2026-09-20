import pandas as pd
import numpy as np
import requests, sqlite3, time, os
from datetime import datetime, timezone

DB="paper_trader_v4.db"
PRODUCTS=["BTC-USD","ETH-USD","SOL-USD","DOGE-USD","SHIB-USD","AVAX-USD",
          "LINK-USD","ADA-USD","XRP-USD","LTC-USD","BCH-USD"]

def db():
    c=sqlite3.connect(DB)
    c.execute("""CREATE TABLE IF NOT EXISTS scans(
      id INTEGER PRIMARY KEY AUTOINCREMENT, scan_id TEXT, seen_at TEXT, product TEXT,
      price REAL, score REAL, status TEXT, rsi REAL, rel_volume REAL, reason TEXT)""")
    c.commit(); return c

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

c=db()
now=datetime.now(timezone.utc)
sid=now.strftime("%Y%m%dT%H%M%SZ")
for p in PRODUCTS:
    try:
        r=scan_one(p)
        c.execute("""INSERT INTO scans(scan_id,seen_at,product,price,score,status,rsi,rel_volume,reason)
                     VALUES(?,?,?,?,?,?,?,?,?)""",(sid,now.isoformat(),*r))
        print(r[0],r[2],r[3])
    except Exception as e:
        print("ERROR",p,e)
c.commit(); c.close()
