import os, sqlite3
import pandas as pd
import streamlit as st

DB="memecoin_shadow.db"
st.set_page_config(page_title="Memecoin Paper Trader",page_icon="🚀",layout="wide")
st.title("🚀 Memecoin Paper Trader")
st.caption("Standalone simulated memecoin trading dashboard • No real-money execution")

def exists(c,t):
 return c.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",(t,)).fetchone() is not None

if not os.path.exists(DB):
 st.warning("Waiting for memecoin_shadow.db to be created by the scheduled scanner.")
 st.stop()

c=sqlite3.connect(DB)
if not exists(c,"meme_paper_trades"):
 st.info("Paper trader is ready; waiting for its table/data.")
 st.stop()
trades=pd.read_sql_query("SELECT * FROM meme_paper_trades ORDER BY id DESC",c)
c.close()

if trades.empty:
 st.info("Paper trader is active. Waiting for the first eligible memecoin trade.")
 st.stop()

for x in ["entry_price","current_price","current_return_pct","mfe_pct","mae_pct","net_pnl_usd","net_return_pct"]:
 if x in trades: trades[x]=pd.to_numeric(trades[x],errors="coerce")
open_t=trades[trades.status=="OPEN"].copy()
closed=trades[trades.status=="CLOSED"].copy()
pnl=closed.net_pnl_usd.sum() if "net_pnl_usd" in closed else 0
wins=int((closed.net_pnl_usd>0).sum()) if "net_pnl_usd" in closed else 0
wr=100*wins/len(closed) if len(closed) else 0
m1,m2,m3,m4,m5=st.columns(5)
m1.metric("Open positions",len(open_t))
m2.metric("Closed trades",len(closed))
m3.metric("Record",f"{wins}W / {len(closed)-wins}L")
m4.metric("Win rate",f"{wr:.1f}%")
m5.metric("Realized P/L",f"${pnl:+.2f}")
st.caption("MEME_PAPER_V1 • $100 simulated positions • +20% target • -10% stop • 20-minute max hold • simulated fees/slippage")

st.subheader("Open positions")
if open_t.empty: st.caption("No open positions right now.")
else:
 cols=[x for x in ["token","opened_at","entry_price","current_price","current_return_pct","mfe_pct","mae_pct"] if x in open_t]
 st.dataframe(open_t[cols],use_container_width=True,hide_index=True)

st.subheader("Trade history")
if closed.empty: st.caption("No closed paper trades yet.")
else:
 cols=[x for x in ["token","opened_at","closed_at","entry_price","exit_price","exit_reason","net_return_pct","net_pnl_usd","mfe_pct","mae_pct"] if x in closed]
 st.dataframe(closed[cols].head(300),use_container_width=True,hide_index=True)

st.subheader("Recent activity")
cols=[x for x in ["token","status","opened_at","closed_at","current_return_pct","net_return_pct","exit_reason"] if x in trades]
st.dataframe(trades[cols].head(100),use_container_width=True,hide_index=True)
