"""Live, paper-only memecoin dashboard backed by the Render collector."""
import os

import pandas as pd
import requests
import streamlit as st

SUMMARY_URL=os.getenv("MEME_PAPER_SUMMARY_URL",
    "https://meme-fast-paper-trader.onrender.com/paper-summary")

st.set_page_config(page_title="Memecoin Paper Trader",page_icon="🚀",layout="wide")
st.title("🚀 Meme Command Center")
st.caption("Fast memecoin paper-trading monitor • simulated execution only • no real-money orders")
st.markdown("""<style>.block-container{padding-top:1.5rem;max-width:1500px}div[data-testid="stMetric"]{background:rgba(128,128,128,.08);border:1px solid rgba(128,128,128,.18);padding:14px;border-radius:14px}[data-testid="stDataFrame"]{border-radius:12px;overflow:hidden}</style>""",unsafe_allow_html=True)

@st.cache_data(ttl=15,show_spinner=False)
def live_summary():
    response=requests.get(SUMMARY_URL,timeout=40)
    response.raise_for_status()
    payload=response.json()
    if payload.get("mode")!="paper_trading" or not isinstance(payload.get("totals"),dict):
        raise ValueError("Paper service returned an invalid summary")
    return payload

try:
    data=live_summary()
except (requests.RequestException,ValueError) as exc:
    st.error("Live paper-trading data is temporarily unavailable. No saved database snapshot is shown as current data.")
    st.caption(f"Connection: {type(exc).__name__}")
    st.stop()

totals=data["totals"]
closed_count=int(totals.get("paper_closed") or 0)
win_count=int(totals.get("paper_wins") or 0)
open_count=int(totals.get("paper_open") or 0)
st.caption(f"Live Render paper database • updated {data.get('as_of','unknown')} • refresh the page for current data")

m1,m2,m3,m4,m5,m6=st.columns(6)
m1.metric("Open positions",open_count)
m2.metric("Closed trades",closed_count)
m3.metric("Record",f"{win_count}W / {closed_count-win_count}L")
m4.metric("Win rate",f"{100*win_count/closed_count:.1f}%" if closed_count else "—")
m5.metric("Realized P/L",f"${float(totals.get('realized_pnl_usd') or 0):+.2f}")
m6.metric("Best trade",f"${float(totals['best_trade']):+.2f}" if totals.get("best_trade") is not None else "—")
st.caption("MEME_PAPER_V1 • $100 simulated positions • +20% target • -10% stop • 20-minute max hold • simulated fees/slippage")

recent=pd.DataFrame(data.get("recent_trades") or [])
open_positions=pd.DataFrame(data.get("open_positions") or [])
curve=pd.DataFrame(data.get("closed_pnl_series") or [])
tab1,tab2,tab3=st.tabs(["⚡ Live","📈 Performance","🧾 History"])

with tab1:
    st.subheader("Open positions")
    if open_positions.empty:
        st.caption("No open positions right now.")
    else:
        st.dataframe(open_positions,use_container_width=True,hide_index=True)

with tab2:
    st.subheader("Performance")
    if curve.empty:
        st.info("Performance charts unlock after paper trades close.")
    else:
        curve["net_pnl_usd"]=pd.to_numeric(curve["net_pnl_usd"],errors="coerce").fillna(0)
        curve["Cumulative P/L"]=curve["net_pnl_usd"].cumsum()
        st.line_chart(curve.set_index("closed_at")["Cumulative P/L"])
        a,b,c=st.columns(3)
        for slot,label,key in ((a,"Avg return","avg_return"),(b,"Avg MFE","avg_mfe"),(c,"Avg MAE","avg_mae")):
            value=totals.get(key)
            slot.metric(label,f"{float(value):+.2f}%" if value is not None else "—")

with tab3:
    st.subheader("Recent closed trades")
    if recent.empty or "status" not in recent:
        st.caption("No trades yet.")
    else:
        closed=recent[recent.status=="CLOSED"]
        cols=[x for x in ["token","opened_at","closed_at","entry_price","exit_price","exit_reason","net_return_pct","net_pnl_usd","mfe_pct","mae_pct"] if x in closed]
        st.dataframe(closed[cols],use_container_width=True,hide_index=True)
        st.caption("Showing the most recent 300 positions; totals and chart use all closed positions.")

st.subheader("Recent activity")
if not recent.empty:
    cols=[x for x in ["token","status","opened_at","closed_at","current_return_pct","net_return_pct","exit_reason"] if x in recent]
    st.dataframe(recent[cols],use_container_width=True,hide_index=True)
