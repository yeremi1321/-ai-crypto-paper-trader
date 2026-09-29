"""Live, paper-only memecoin dashboard backed by the Render collector."""
import os

import pandas as pd
import requests
import streamlit as st

SUMMARY_URL=os.getenv("MEME_PAPER_SUMMARY_URL",
    "https://meme-fast-paper-trader.onrender.com/paper-summary")
PREDICTIONS_URL=os.getenv("MEME_PREDICTIONS_URL",SUMMARY_URL.rsplit("/",1)[0]+"/paper-predictions")

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

@st.cache_data(ttl=60,show_spinner=False)
def prediction_report():
    response=requests.get(PREDICTIONS_URL,timeout=40)
    response.raise_for_status()
    payload=response.json()
    if payload.get("mode")!="paper_research":
        raise ValueError("Predictor returned an invalid report")
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
tab1,tab2,tab3,tab4=st.tabs(["⚡ Live","📈 Performance","🧾 History","🔮 Predictions"])

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

with tab4:
    st.subheader("Predict → observe → learn")
    try:
        pred=prediction_report()
    except (requests.RequestException,ValueError) as exc:
        pred=None
        st.info("Predictor report is not available yet.")
        st.caption(f"Connection: {type(exc).__name__}")
    if pred:
        counts,acc=pred["counts"],pred["accuracy"]
        st.caption(f"{pred['version']} • {pred['rule']} • record-only, never changes paper entries")
        sev=(pred.get("severe_loss") or {}).get("accuracy") or {}
        p1,p2,p3,p4,p5,p6=st.columns(6)
        p1.metric("Predictions",counts["predictions"])
        p2.metric("Learned from",counts["model_updates"])
        p3.metric("Pending",counts["pending"])
        p4.metric("Win-call skill",f"{acc['skill_vs_baseline_pct']:+.1f}%" if acc.get("skill_vs_baseline_pct") is not None else "—")
        p5.metric("Win-call AUC",f"{acc['auc']:.2f}" if acc.get("auc") is not None else "—")
        p6.metric("Severe-loss skill",f"{sev['skill_vs_baseline_pct']:+.1f}%" if sev.get("skill_vs_baseline_pct") is not None else "—")
        st.markdown("**What it thinks it can do better**")
        for line in pred.get("suggestions") or ["Waiting for outcomes."]:
            st.markdown(f"- {line}")
        left,right=st.columns(2)
        with left:
            st.markdown("**Would its picks have beaten the bot?**")
            pol=pd.DataFrame([{"policy":k.replace("_"," "),**v} for k,v in pred["policies"].items()])
            st.dataframe(pol,use_container_width=True,hide_index=True)
            curve=pd.DataFrame(pred.get("learning_curve") or [])
            if not curve.empty:
                st.markdown("**Learning curve (skill per time window)**")
                st.line_chart(curve.set_index("from")["skill_vs_baseline_pct"])
        with right:
            st.markdown("**Calibration: said vs actual win %**")
            cal=pd.DataFrame(pred.get("calibration") or [])
            if not cal.empty:
                st.dataframe(cal,use_container_width=True,hide_index=True)
            signals=pd.DataFrame(pred["model"].get("top_positive_signals",[])+pred["model"].get("top_negative_signals",[]))
            if not signals.empty:
                st.markdown("**Learned signals (weight > 0 favours a win)**")
                st.dataframe(signals,use_container_width=True,hide_index=True)
        severe=pred.get("severe_loss") or {}
        if severe:
            st.markdown("**Severe-loss radar (net loss at or beyond 2x the stop)**")
            s1,s2=st.columns(2)
            with s1:
                sev_cal=pd.DataFrame(severe.get("calibration") or [])
                if not sev_cal.empty:
                    st.dataframe(sev_cal,use_container_width=True,hide_index=True)
            with s2:
                sev_sig=pd.DataFrame(severe.get("raises_risk",[])+severe.get("lowers_risk",[]))
                if not sev_sig.empty:
                    st.caption("Weight > 0 raises severe-loss risk")
                    st.dataframe(sev_sig,use_container_width=True,hide_index=True)
        hyps=pred.get("preregistered_hypotheses") or []
        if hyps:
            st.markdown("**Pre-registered forward tests (real bot trades after registration)**")
            def side(h,key,field):
                return (h.get(key) or {}).get(field)
            st.dataframe(pd.DataFrame([{"test":h["name"],"since":h["registered_at"],"verdict":h["verdict"],
                "kept avg %":side(h,"kept","avg_net_return_pct"),"skipped avg %":side(h,"skipped","avg_net_return_pct"),
                "every entry avg %":side(h,"every_entry","avg_net_return_pct"),
                "trades":side(h,"every_entry","trades") or h.get("trades_so_far"),
                "skipped":side(h,"skipped","trades"),"bootstrap % better":h.get("bootstrap_pct_kept_beats_every")} for h in hyps]),
                use_container_width=True,hide_index=True)
        st.markdown("**Recent lessons from confident misses**")
        lessons=pd.DataFrame(pred.get("recent_lessons") or [])
        if lessons.empty:
            st.caption("No confident misses yet.")
        else:
            st.dataframe(lessons,use_container_width=True,hide_index=True)
        st.markdown("**Latest predictions**")
        st.dataframe(pd.DataFrame(pred.get("recent_predictions") or []),use_container_width=True,hide_index=True)

st.subheader("Recent activity")
if not recent.empty:
    cols=[x for x in ["token","status","opened_at","closed_at","current_return_pct","net_return_pct","exit_reason"] if x in recent]
    st.dataframe(recent[cols],use_container_width=True,hide_index=True)
