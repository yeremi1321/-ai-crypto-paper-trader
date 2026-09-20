import streamlit as st
import pandas as pd
import sqlite3, os
from datetime import datetime, timezone

st.set_page_config(page_title="AI Crypto Paper Trader V4",page_icon="📡",layout="wide")
DB="paper_trader_v4.db"
st.title("AI Crypto Paper Trader — V4")
st.caption("Automatic scheduled research scanner • Persistent GitHub history • Paper research only • No real-money execution")

if not os.path.exists(DB):
    st.warning("No automated scan database yet. After the GitHub Actions workflow runs for the first time, data will appear here.")
    st.stop()

c=sqlite3.connect(DB)
d=pd.read_sql_query("SELECT * FROM scans ORDER BY id",c)
c.close()
if not len(d):
    st.info("Waiting for the first scheduled scan.")
    st.stop()

d["seen_at"]=pd.to_datetime(d.seen_at,utc=True)
last_id=d.scan_id.iloc[-1]
cur=d[d.scan_id==last_id].copy()
last_time=d.seen_at.max()
scan_count=d.scan_id.nunique()
signals=(d.status=="SIGNAL").sum()
watches=(d.status=="WATCH").sum()

a,b,c1,d1=st.columns(4)
a.metric("Recorded scans",scan_count)
b.metric("Last scan",last_time.strftime("%b %d %H:%M UTC"))
c1.metric("WATCH observations",int(watches))
d1.metric("SIGNAL observations",int(signals))

st.subheader("Latest Automatic Scan")
st.dataframe(cur[["product","price","score","status","rsi","rel_volume","reason"]],
             use_container_width=True,hide_index=True)

st.subheader("Status Changes")
changes=[]
for p,g in d.groupby("product"):
    g=g.sort_values("id")
    prev=None
    for _,r in g.iterrows():
        if prev is not None and r.status!=prev.status:
            changes.append({"product":p,"from":prev.status,"to":r.status,
                            "old_score":prev.score,"new_score":r.score,"seen_at":r.seen_at})
        prev=r
chg=pd.DataFrame(changes)
st.dataframe(chg.sort_values("seen_at",ascending=False).head(100) if len(chg) else
             pd.DataFrame(columns=["product","from","to","old_score","new_score","seen_at"]),
             use_container_width=True,hide_index=True)

st.subheader("Score History")
product=st.selectbox("Asset",sorted(d.product.unique()))
h=d[d.product==product].set_index("seen_at")
st.line_chart(h["score"])

st.subheader("Forward Performance Research")
rows=[]
for p,g in d.groupby("product"):
    g=g.sort_values("seen_at")
    for _,r in g.iterrows():
        row={"product":p,"seen_at":r.seen_at,"score":r.score,"status":r.status,"price":r.price}
        for label,hours in [("1h",1),("4h",4),("24h",24)]:
            z=g[g.seen_at>=r.seen_at+pd.Timedelta(hours=hours)]
            row[f"return_{label}_pct"]=(z.iloc[0].price/r.price-1)*100 if len(z) else None
        rows.append(row)
fp=pd.DataFrame(rows)
st.dataframe(fp.sort_values("seen_at",ascending=False).head(250),use_container_width=True,hide_index=True)

m=fp.dropna(subset=["return_1h_pct"]).copy()
if len(m):
    m["score_bucket"]=pd.cut(m.score,bins=[0,40,50,60,70,80,101],right=False)
    summary=m.groupby("score_bucket",observed=True).agg(
        observations=("score","size"),
        avg_1h_return_pct=("return_1h_pct","mean"),
        median_1h_return_pct=("return_1h_pct","median")).reset_index()
    st.caption("Score-bucket research — descriptive results, not a recommendation")
    st.dataframe(summary,use_container_width=True,hide_index=True)

st.info("V4's scanner is scheduled by GitHub Actions. GitHub may delay scheduled jobs during high load, so scans are not guaranteed to occur at the exact minute.")
