import html
import os
import sqlite3


import altair as alt
import numpy as np
import pandas as pd
import streamlit as st




DB = "paper_trader_v4.db"
SHADOW_DB = "research_shadow.db"
BACKTEST_DB = "research_backtest.db"
SIMULATED_FEE_RATE = 0.006
SIMULATED_SLIPPAGE_RATE = 0.001
HORIZONS = [("15m", 15), ("1h", 60), ("4h", 240), ("24h", 1440)]


st.set_page_config(
    page_title="AI Crypto Paper Trader V4", page_icon="📡", layout="wide"
)
st.markdown(
    """
    <style>
    .block-container {max-width: 1500px; padding-top: .8rem; padding-bottom: 4rem;}
    #MainMenu, footer {visibility: hidden;}
    h1 {font-size: 1.75rem !important; margin-bottom: 0 !important;}
    [data-testid="stMetric"] {
        background: #101622;
        border: 1px solid #273044;
        border-radius: 16px;
        padding: 12px 14px;
        min-height: 102px;
    }
    [data-testid="stMetricLabel"] {color: #aeb7c8;}
    [data-testid="stMetricValue"] {color: #f4f7fb;}
    .health-row {display:flex; gap:8px; flex-wrap:wrap; margin:.4rem 0 1rem;}
    .health-pill {border-radius:999px; padding:7px 11px; background:#101622;
        border:1px solid #273044; font-size:.83rem; color:#f4f7fb;}
    .signal-grid {display:grid; grid-template-columns:repeat(auto-fit,minmax(220px,1fr));
        gap:10px; margin:.4rem 0 1rem;}
    .signal-card {border:1px solid #273044; border-left:5px solid var(--state);
        border-radius:16px; padding:14px; background:#101622; color:#f4f7fb;
        min-height:170px;}
    .signal-head {display:flex; justify-content:space-between; align-items:center; gap:8px;}
    .coin {font-size:1.08rem; font-weight:750;}
    .state-badge {font-size:.68rem; font-weight:800; border:1px solid var(--state);
        color:var(--state); padding:4px 7px; border-radius:999px;}
    .signal-price {font-size:1.22rem; font-weight:750; margin:.55rem 0;}
    .signal-stats {display:grid; grid-template-columns:repeat(3,1fr); gap:7px;}
    .signal-stat {font-size:.72rem; color:#aeb7c8;}
    .signal-stat b {display:block; color:#f4f7fb; font-size:.92rem; margin-top:2px;}
    .sequence {font-size:.76rem; color:#c9d1df; margin-top:10px; white-space:nowrap;
        overflow:hidden; text-overflow:ellipsis;}
    .up {color:#16c784}.down {color:#ff8c42}.flat {color:#aeb7c8}
    @media (max-width: 700px) {
        .block-container {padding:.45rem .7rem 5rem;}
        h1 {font-size:1.45rem !important;}
        [data-testid="column"] {min-width:46% !important; flex:1 1 46% !important;}
        [data-testid="stMetric"] {min-height:92px; padding:10px;}
        .signal-grid {grid-template-columns:1fr 1fr; gap:8px;}
        .signal-card {padding:11px; min-height:160px;}
        .signal-stats {grid-template-columns:1fr 1fr;}
        .signal-stat:last-child {display:none;}
        .coin {font-size:.94rem}.state-badge {font-size:.58rem}
        .signal-price {font-size:1.04rem;}
    }
    </style>
    <meta http-equiv="refresh" content="60">
    """,
    unsafe_allow_html=True,
)
st.title("📈 V5 Trading Control Center")
st.caption(
    "Mobile-first trading dashboard • Refreshes every 60 seconds • "
    "Paper research only • No real-money execution"
)


if not os.path.exists(DB):
    st.warning(
        "No automated scan database yet. After the GitHub Actions workflow runs, "
        "data will appear here."
    )
    st.stop()




def table_exists(conn, table_name):
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table_name,)
    ).fetchone()
    return row is not None


def tradingview_url(product):
    symbol = product.replace("-", "")
    return f"https://www.tradingview.com/chart/?symbol=COINBASE%3A{symbol}"


def scanner_action(state, status):
    if state == "CONFIRMED":
        return "✅ Confirmed setup"
    if state == "STRENGTHENING":
        return "📈 Strengthening"
    if state == "WEAKENING":
        return "📉 Weakening"
    if state == "FAILED":
        return "❌ Failed"
    if state == "EARLY":
        return "🚨 Early move"
    if status == "SIGNAL":
        return "🟢 Signal"
    if status == "WATCH":
        return "🟡 Watch"
    return "⚪ No trade"


def state_color(state):
    return {
        "CONFIRMED": ("#16c784", "rgba(22,199,132,.13)"),
        "STRENGTHENING": ("#16c784", "rgba(22,199,132,.13)"),
        "HOLD": ("#f4c542", "rgba(244,197,66,.12)"),
        "WATCH": ("#f4c542", "rgba(244,197,66,.12)"),
        "EARLY": ("#f4c542", "rgba(244,197,66,.12)"),
        "WEAKENING": ("#ff8c42", "rgba(255,140,66,.13)"),
        "FAILED": ("#ff4b4b", "rgba(255,75,75,.13)"),
    }.get(state, ("#8b93a7", "rgba(139,147,167,.10)"))


def price_text(value):
    value = float(value or 0)
    if value < 0.001:
        return "$" + f"{value:.8f}"
    if value < 1:
        return "$" + f"{value:.5f}"
    return "$" + f"{value:,.2f}"


def signal_sequence(product):
    if state_events.empty:
        return "No active sequence"
    items = (
        state_events[state_events["product"] == product]
        .sort_values("id")["state"].tail(5).tolist()
    )
    compact = []
    for item in items:
        if not compact or compact[-1] != item:
            compact.append(item)
    return " → ".join(compact) if compact else "No active sequence"




def add_forward_returns(events, scans):
    """Use the first recorded market price at or after each research horizon."""
    if events.empty:
        return events.copy()


    output = events.copy()
    for label, _ in HORIZONS:
        output[f"return_{label}_pct"] = pd.NA


    scan_groups = {
        product: group.sort_values("seen_at").reset_index(drop=True)
        for product, group in scans.groupby("product")
    }
    for index, event in output.iterrows():
        history = scan_groups.get(event["product"])
        if history is None or history.empty or not event["price"]:
            continue
        for label, minutes in HORIZONS:
            target = event["seen_at"] + pd.Timedelta(minutes=minutes)
            future = history[history["seen_at"] >= target]
            if not future.empty:
                outcome_price = future.iloc[0]["price"]
                output.at[index, f"return_{label}_pct"] = (
                    (outcome_price / event["price"]) - 1
                ) * 100


    for label, _ in HORIZONS:
        output[f"return_{label}_pct"] = pd.to_numeric(
            output[f"return_{label}_pct"], errors="coerce"
        )
    return output




def performance_summary(frame, group_column):
    rows = []
    for group_name, group in frame.groupby(group_column):
        row = {group_column: group_name, "events": len(group)}
        for label, _ in HORIZONS:
            column = f"return_{label}_pct"
            evaluated = group[column].dropna()
            row[f"evaluated_{label}"] = len(evaluated)
            row[f"avg_{label}_pct"] = evaluated.mean() if len(evaluated) else None
            row[f"win_rate_{label}_pct"] = (
                (evaluated > 0).mean() * 100 if len(evaluated) else None
            )
        rows.append(row)
    return pd.DataFrame(rows)




conn = sqlite3.connect(DB)
scans = pd.read_sql_query("SELECT * FROM scans ORDER BY id", conn)
if table_exists(conn, "momentum_tracking"):
    state_events = pd.read_sql_query(
        "SELECT * FROM momentum_tracking ORDER BY id", conn
    )
else:
    state_events = pd.DataFrame(
        columns=["id", "seen_at", "product", "state", "score", "previous_score", "price"]
    )
if table_exists(conn, "paper_trades"):
    paper_trades = pd.read_sql_query("SELECT * FROM paper_trades ORDER BY id", conn)
else:
    paper_trades = pd.DataFrame()
if table_exists(conn, "paper_entry_skips"):
    paper_entry_skips = pd.read_sql_query(
        "SELECT * FROM paper_entry_skips ORDER BY id", conn
    )
else:
    paper_entry_skips = pd.DataFrame()
if table_exists(conn, "signal_outcomes"):
    signal_outcomes = pd.read_sql_query(
        "SELECT * FROM signal_outcomes ORDER BY id", conn
    )
else:
    signal_outcomes = pd.DataFrame()
if table_exists(conn, "market_regime_log"):
    market_regime_log = pd.read_sql_query(
        "SELECT * FROM market_regime_log ORDER BY id", conn
    )
else:
    market_regime_log = pd.DataFrame()
conn.close()

shadow_evaluations = pd.DataFrame()
if os.path.exists(SHADOW_DB):
    research_conn = sqlite3.connect(SHADOW_DB)
    if table_exists(research_conn, "shadow_evaluations"):
        shadow_evaluations = pd.read_sql_query(
            "SELECT * FROM shadow_evaluations ORDER BY id", research_conn
        )
    research_conn.close()

backtest_runs = pd.DataFrame()
backtest_results = pd.DataFrame()
if os.path.exists(BACKTEST_DB):
    research_conn = sqlite3.connect(BACKTEST_DB)
    if table_exists(research_conn, "runs"):
        backtest_runs = pd.read_sql_query(
            "SELECT * FROM runs ORDER BY created_at", research_conn
        )
    if table_exists(research_conn, "results"):
        backtest_results = pd.read_sql_query(
            "SELECT * FROM results", research_conn
        )
    research_conn.close()


if scans.empty:
    st.info("Waiting for the first scheduled scan.")
    st.stop()


scans["seen_at"] = pd.to_datetime(scans["seen_at"], utc=True)
if not state_events.empty:
    state_events["seen_at"] = pd.to_datetime(state_events["seen_at"], utc=True)
if not paper_trades.empty:
    if "strategy_version" not in paper_trades.columns:
        paper_trades["strategy_version"] = "V4"
    paper_trades["strategy_version"] = paper_trades["strategy_version"].fillna("V4")
    paper_trades["opened_at"] = pd.to_datetime(paper_trades["opened_at"], utc=True)
    paper_trades["closed_at"] = pd.to_datetime(
        paper_trades["closed_at"], utc=True, errors="coerce"
    )
if not signal_outcomes.empty:
    if "strategy_version" not in signal_outcomes.columns:
        signal_outcomes["strategy_version"] = "V4"
    signal_outcomes["strategy_version"] = signal_outcomes[
        "strategy_version"
    ].fillna("V4")
    signal_outcomes["created_at"] = pd.to_datetime(
        signal_outcomes["created_at"], utc=True
    )
    signal_outcomes["final_at"] = pd.to_datetime(
        signal_outcomes["final_at"], utc=True, errors="coerce"
    )
if not market_regime_log.empty:
    market_regime_log["seen_at"] = pd.to_datetime(
        market_regime_log["seen_at"], utc=True
    )
if not paper_entry_skips.empty:
    if "strategy_version" not in paper_entry_skips.columns:
        paper_entry_skips["strategy_version"] = "V4"
    paper_entry_skips["strategy_version"] = paper_entry_skips[
        "strategy_version"
    ].fillna("V4")
if not shadow_evaluations.empty:
    shadow_evaluations["seen_at"] = pd.to_datetime(
        shadow_evaluations["seen_at"], utc=True
    )
if not backtest_runs.empty:
    backtest_runs["created_at"] = pd.to_datetime(
        backtest_runs["created_at"], utc=True
    )


latest_scan_id = scans.scan_id.iloc[-1]
current = scans[scans.scan_id == latest_scan_id].copy()
last_time = scans.seen_at.max()
scan_count = scans.scan_id.nunique()
signals = (scans.status == "SIGNAL").sum()
watches = (scans.status == "WATCH").sum()

latest_state = {}
if not state_events.empty:
    latest_state = (
        state_events.sort_values("id").groupby("product").tail(1)
        .set_index("product")["state"].to_dict()
    )

score_delta = {}
for product, group in scans.sort_values("id").groupby("product"):
    recent = group.tail(2)
    score_delta[product] = (
        float(recent.score.iloc[-1] - recent.score.iloc[-2])
        if len(recent) == 2 else 0.0
    )

current["score_change"] = current["product"].map(score_delta).fillna(0.0)
current["state"] = current["product"].map(latest_state)
current["action"] = current.apply(
    lambda row: scanner_action(row["state"], row["status"]), axis=1
)
current["sequence"] = current["product"].map(signal_sequence)
current["chart"] = current["product"].map(tradingview_url)
current = current.sort_values(["score", "product"], ascending=[False, True])

open_now = (
    paper_trades[paper_trades.status == "OPEN"].copy()
    if not paper_trades.empty else pd.DataFrame()
)
closed_now = (
    paper_trades[
        (paper_trades.status == "CLOSED")
        & (paper_trades.strategy_version == "V5")
    ].copy()
    if not paper_trades.empty else pd.DataFrame()
)
open_pnl = open_now.current_pnl_usd.sum() if not open_now.empty else 0.0
realized_pnl = closed_now.net_pnl_usd.sum() if not closed_now.empty else 0.0
win_rate_now = (
    (closed_now.net_pnl_usd > 0).mean() * 100 if not closed_now.empty else 0.0
)
today = pd.Timestamp.now(tz="America/New_York").date()
today_closed = (
    closed_now[
        closed_now.closed_at.dt.tz_convert("America/New_York").dt.date == today
    ].copy()
    if not closed_now.empty else pd.DataFrame()
)
today_pnl = today_closed.net_pnl_usd.sum() if not today_closed.empty else 0.0
today_wins = (today_closed.net_pnl_usd > 0).sum() if not today_closed.empty else 0
today_losses = (today_closed.net_pnl_usd <= 0).sum() if not today_closed.empty else 0
active_alerts = current.state.isin(
    ["EARLY", "HOLD", "WATCH", "STRENGTHENING", "CONFIRMED"]
).sum()
age_minutes = max(
    0, int((pd.Timestamp.now(tz="UTC") - last_time).total_seconds() / 60)
)
fresh_label = "LIVE" if age_minutes <= 30 else "DELAYED"

regime_label = "WAITING FOR NEXT SCAN"
regime_detail = "The next scan will record BTC alignment and market breadth."
if not market_regime_log.empty:
    latest_regime = market_regime_log.iloc[-1]
    regime_label = (
        "ENTRIES ALLOWED" if latest_regime.allows_entries else "ENTRIES BLOCKED"
    )
    regime_detail = latest_regime.detail

scanner_color = "#16c784" if fresh_label == "LIVE" else "#ff4b4b"
regime_color = "#16c784" if regime_label == "ENTRIES ALLOWED" else "#ff4b4b"
st.markdown(
    f'<div class="health-row">'
    f'<span class="health-pill">Scanner: <b style="color:{scanner_color}">{fresh_label}</b></span>'
    f'<span class="health-pill">Last scan: <b>{age_minutes} min ago</b></span>'
    f'<span class="health-pill">Market: <b style="color:{regime_color}">{regime_label}</b></span>'
    f'<span class="health-pill">{html.escape(str(regime_detail))}</span></div>',
    unsafe_allow_html=True,
)
st.subheader("Trading summary")
m1, m2, m3, m4, m5, m6 = st.columns(6)
m1.metric("Open paper trades", f"{len(open_now)}/5")
m2.metric("Today's P/L", "$" + f"{today_pnl:+.2f}")
m3.metric("Today's record", f"{today_wins}W / {today_losses}L")
m4.metric("Active alerts", int(active_alerts))
m5.metric("V5 closed trades", len(closed_now))
m6.metric("Open P/L", "$" + f"{open_pnl:+.2f}")
st.caption(
    f"Last completed scan: {last_time.strftime('%b %d %H:%M UTC')} • "
    f"{scan_count} scan cycles recorded • {int(watches)} WATCH and "
    f"{int(signals)} SIGNAL observations"
)

st.subheader("Live signals")
state_rank = {
    "CONFIRMED": 0, "STRENGTHENING": 1, "HOLD": 2, "WATCH": 2, "EARLY": 3,
    "WEAKENING": 4, "FAILED": 5,
}
current["state_rank"] = current["state"].map(state_rank).fillna(9)
current = current.sort_values(["state_rank", "score"], ascending=[True, False])
cards = ['<div class="signal-grid">']
for _, row in current.iterrows():
    card_state = row["state"] if pd.notna(row["state"]) else row["status"]
    color, background = state_color(card_state)
    delta = float(row["score_change"])
    trend_class = "up" if delta > 1 else "down" if delta < -1 else "flat"
    trend_icon = "▲" if delta > 1 else "▼" if delta < -1 else "•"
    cards.append(
        f'<div class="signal-card" style="--state:{color};--bg:{background}">'
        f'<div class="signal-head"><span class="coin">{html.escape(row["product"])}</span>'
        f'<span class="state-badge">{html.escape(str(card_state))}</span></div>'
        f'<div class="signal-price">{price_text(row["price"])}</div>'
        f'<div class="signal-stats"><span class="signal-stat">SCORE<b>{row["score"]:.1f}</b></span>'
        f'<span class="signal-stat">VOLUME<b>{row["rel_volume"]:.2f}x</b></span>'
        f'<span class="signal-stat">RSI<b>{row["rsi"]:.1f}</b></span></div>'
        f'<div class="sequence"><span class="{trend_class}">{trend_icon} {delta:+.1f}</span>'
        f' · {html.escape(row["sequence"])}</div></div>'
    )
cards.append("</div>")
st.markdown("".join(cards), unsafe_allow_html=True)

st.subheader("Best opportunities")
opportunities = current.copy()
opportunities["rank_score"] = (
    opportunities.score * 0.58
    + opportunities.rel_volume.clip(upper=5) * 6
    + opportunities.score_change.clip(-10, 10) * 0.8
    + opportunities.state.map(
        {"CONFIRMED": 15, "STRENGTHENING": 10, "HOLD": 5, "WATCH": 5, "EARLY": 3}
    ).fillna(0)
)
opportunities["trend"] = np.where(
    opportunities.score_change > 1, "Improving ↑",
    np.where(opportunities.score_change < -1, "Fading ↓", "Flat →"),
)
st.dataframe(
    opportunities.sort_values("rank_score", ascending=False)[
        ["product", "state", "score", "rel_volume", "trend", "chart"]
    ].head(6),
    column_config={
        "product": "Coin", "state": "State",
        "score": st.column_config.ProgressColumn(
            "Score", min_value=0, max_value=85, format="%.1f"
        ),
        "rel_volume": st.column_config.NumberColumn("Volume", format="%.2fx"),
        "trend": "Trend",
        "chart": st.column_config.LinkColumn("Chart", display_text="Open ↗"),
    },
    use_container_width=True, hide_index=True,
)

with st.expander("All scanner details"):
    st.dataframe(
        current[[
            "product", "price", "score", "score_change", "status", "state",
            "rsi", "rel_volume", "chart",
        ]],
        column_config={
            "product": "Coin",
            "price": st.column_config.NumberColumn("Price", format="$%.8g"),
            "score": st.column_config.ProgressColumn(
                "Score", min_value=0, max_value=85, format="%.1f"
            ),
            "score_change": st.column_config.NumberColumn("Change", format="%+.1f"),
            "rel_volume": st.column_config.NumberColumn("Volume", format="%.2fx"),
            "chart": st.column_config.LinkColumn("TradingView", display_text="Open ↗"),
        },
        use_container_width=True, hide_index=True,
    )

activity_rows = []
if not state_events.empty:
    for _, row in state_events.sort_values("id", ascending=False).head(40).iterrows():
        activity_rows.append(
            {
                "time": row.seen_at,
                "coin": row["product"],
                "event": row.state,
                "details": f"Score {row.score:.1f}",
                "chart": tradingview_url(row["product"]),
            }
        )
if not paper_entry_skips.empty:
    skip_times = pd.to_datetime(paper_entry_skips["seen_at"], utc=True)
    for index, row in paper_entry_skips.sort_values("id", ascending=False).head(30).iterrows():
        activity_rows.append(
            {
                "time": skip_times.loc[index],
                "coin": row["product"],
                "event": "BLOCKED",
                "details": row.detail,
                "chart": tradingview_url(row["product"]),
            }
        )
if not paper_trades.empty:
    for _, row in paper_trades.sort_values("id", ascending=False).head(30).iterrows():
        activity_rows.append(
            {
                "time": row.opened_at,
                "coin": row["product"],
                "event": "PAPER OPEN",
                "details": f"Entry score {row.entry_score:.1f}",
                "chart": tradingview_url(row["product"]),
            }
        )
        if row.status == "CLOSED" and pd.notna(row.closed_at):
            activity_rows.append(
                {
                    "time": row.closed_at,
                    "coin": row["product"],
                    "event": "PAPER CLOSE",
                    "details": (
                        f"{row.exit_reason} • ${row.net_pnl_usd:+.2f} "
                        f"({row.net_return_pct:+.2f}%)"
                    ),
                    "chart": tradingview_url(row["product"]),
                }
            )

with st.expander("Recent decisions and paper-trade activity", expanded=False):
    if activity_rows:
        activity = pd.DataFrame(activity_rows).sort_values(
            "time", ascending=False
        ).head(40)
        st.dataframe(
            activity,
            column_config={
                "time": st.column_config.DatetimeColumn(
                    "Time", format="MMM D, h:mm a"
                ),
                "coin": "Coin",
                "event": "Decision",
                "details": "Why / result",
                "chart": st.column_config.LinkColumn(
                    "Chart", display_text="View ↗"
                ),
            },
            use_container_width=True,
            hide_index=True,
        )
    else:
        st.info("The activity timeline will fill in after the next scan.")


st.subheader("Automatic Paper Trading")
st.caption(
    "V5 research simulation only: $100 per CONFIRMED entry • 3% stop • 4% target • "
    "1% trailing stop after a 2% gain • 24-hour maximum hold • "
    "maximum 5 open trades / $500 exposure • "
    "2 V5-quality scans to enter • loss/profit-aware weakening exit • "
    "2-hour re-entry cooldown • "
    "BTC plus 70% market trend filter for new entries • "
    "$15 daily realized-loss cutoff • "
    "0.6% estimated fee and 0.1% slippage per side"
)
if paper_trades.empty:
    st.info("Waiting for the first CONFIRMED setup to open a simulated trade.")
else:
    open_trades = paper_trades[paper_trades.status == "OPEN"].copy()
    closed_trades = paper_trades[
        (paper_trades.status == "CLOSED")
        & (paper_trades.strategy_version == "V5")
    ].copy()
    legacy_closed_trades = paper_trades[
        (paper_trades.status == "CLOSED")
        & (paper_trades.strategy_version != "V5")
    ].copy()


    open_count = len(open_trades)
    closed_count = len(closed_trades)
    total_net_pnl = closed_trades.net_pnl_usd.sum() if closed_count else 0.0
    win_rate = (
        (closed_trades.net_pnl_usd > 0).mean() * 100 if closed_count else 0.0
    )
    average_return = (
        closed_trades.net_return_pct.mean() if closed_count else 0.0
    )
    expectancy = total_net_pnl / closed_count if closed_count else 0.0
    winning_trades = closed_trades[closed_trades.net_pnl_usd > 0]
    losing_trades = closed_trades[closed_trades.net_pnl_usd <= 0]
    average_win = winning_trades.net_pnl_usd.mean() if len(winning_trades) else 0.0
    average_loss = losing_trades.net_pnl_usd.mean() if len(losing_trades) else 0.0
    gross_wins = winning_trades.net_pnl_usd.sum() if len(winning_trades) else 0.0
    gross_losses = abs(losing_trades.net_pnl_usd.sum()) if len(losing_trades) else 0.0
    profit_factor = gross_wins / gross_losses if gross_losses else 0.0
    realized_drawdown = 0.0
    if closed_count:
        ordered = closed_trades.sort_values("closed_at")
        equity = ordered.net_pnl_usd.cumsum()
        running_peak = equity.cummax().clip(lower=0)
        realized_drawdown = (equity - running_peak).min()


    p1, p2, p3, p4, p5, p6 = st.columns(6)
    p1.metric("Open paper trades (max 5)", open_count)
    p2.metric("V5 closed trades", closed_count)
    p3.metric("V5 win rate", f"{win_rate:.1f}%")
    p4.metric("V5 net paper P/L", f"${total_net_pnl:+.2f}")
    p5.metric("V5 avg return", f"{average_return:+.2f}%")
    p6.metric("V5 expectancy/trade", f"${expectancy:+.2f}")
    st.caption(f"V5 realized paper P/L drawdown: ${realized_drawdown:.2f}")

    q1, q2, q3 = st.columns(3)
    q1.metric("Average win", "$" + f"{average_win:+.2f}")
    q2.metric("Average loss", "$" + f"{average_loss:+.2f}")
    q3.metric("Profit factor", f"{profit_factor:.2f}")

    # Show the cost hurdle explicitly; small gross gains can still lose money.
    if closed_count:
        gross_pnl = closed_trades.gross_pnl_usd.fillna(0).sum()
        total_fees = (
            closed_trades.entry_fee.fillna(0)
            + closed_trades.exit_fee.fillna(0)
        ).sum()
        c1, c2, c3 = st.columns(3)
        c1.metric("V5 gross P/L before fees", f"${gross_pnl:+.2f}")
        c2.metric("V5 simulated fees", f"${total_fees:.2f}")
        c3.metric("Average fees per trade", f"${total_fees / closed_count:.2f}")
        st.caption(
            "Gross P/L includes simulated slippage. Net P/L subtracts both "
            "entry and exit fees. Review V5 alone before changing its rules."
        )

    if closed_count == 0:
        st.info("V5 starts clean. Waiting for the first completed V5 paper trade.")
    if len(legacy_closed_trades):
        legacy_net = legacy_closed_trades.net_pnl_usd.sum()
        legacy_wins = (legacy_closed_trades.net_pnl_usd > 0).mean() * 100
        with st.expander("V4 baseline preserved for comparison"):
            st.write(
                f"{len(legacy_closed_trades)} closed trades • "
                f"{legacy_wins:.1f}% win rate • ${legacy_net:+.2f} net P/L"
            )


    if open_count:
        st.markdown("**Open simulated positions**")
        open_trades["stop_price"] = open_trades.entry_market_price * 0.97
        open_trades["target_price"] = open_trades.entry_market_price * 1.04
        # The market price that would cover the initial outlay, exit slippage,
        # and the estimated exit fee at today's configured rates.
        open_trades["break_even_market_price"] = (
            open_trades.notional_usd
            / (open_trades.quantity * (1 - SIMULATED_FEE_RATE)
               * (1 - SIMULATED_SLIPPAGE_RATE))
        )
        open_trades["time_open_hours"] = (
            pd.Timestamp.now(tz="UTC") - open_trades.opened_at
        ).dt.total_seconds() / 3600
        open_trades["chart"] = open_trades["product"].map(tradingview_url)
        st.dataframe(
            open_trades[
                [
                    "opened_at", "product", "entry_score", "entry_market_price",
                    "current_price", "current_pnl_usd", "current_return_pct",
                    "stop_price", "target_price", "break_even_market_price",
                    "time_open_hours",
                    "highest_price", "chart",
                ]
            ].sort_values("opened_at", ascending=False),
            column_config={
                "chart": st.column_config.LinkColumn(
                    "TradingView", display_text="Open chart ↗"
                ),
            },
            use_container_width=True,
            hide_index=True,
        )


    if closed_count:
        by_coin = (
            closed_trades.groupby("product")
            .agg(
                trades=("id", "size"),
                wins=("net_pnl_usd", lambda values: int((values > 0).sum())),
                net_pnl_usd=("net_pnl_usd", "sum"),
                average_return_pct=("net_return_pct", "mean"),
            )
            .reset_index()
        )
        by_coin["win_rate_pct"] = by_coin.wins / by_coin.trades * 100
        st.markdown("**Results by coin**")
        st.dataframe(
            by_coin.sort_values("net_pnl_usd", ascending=False),
            use_container_width=True, hide_index=True,
        )
        st.markdown("**Completed simulated trades**")
        closed_trades["chart"] = closed_trades["product"].map(tradingview_url)
        st.dataframe(
            closed_trades[
                [
                    "opened_at", "closed_at", "product", "entry_score",
                    "entry_market_price", "exit_market_price", "exit_reason",
                    "net_pnl_usd", "net_return_pct", "chart",
                ]
            ].sort_values("closed_at", ascending=False),
            column_config={
                "chart": st.column_config.LinkColumn(
                    "TradingView", display_text="Review chart ↗"
                ),
            },
            use_container_width=True,
            hide_index=True,
        )
        exit_summary = (
            closed_trades.groupby("exit_reason", dropna=False)
            .agg(
                trades=("id", "size"),
                wins=("net_pnl_usd", lambda values: (values > 0).sum()),
                net_pnl_usd=("net_pnl_usd", "sum"),
                avg_return_pct=("net_return_pct", "mean"),
            )
            .reset_index()
        )
        st.markdown("**Results by exit rule**")
        st.dataframe(exit_summary, use_container_width=True, hide_index=True)


if not paper_entry_skips.empty:
    st.subheader("Why entries were blocked")
    current_skips = paper_entry_skips[
        paper_entry_skips.strategy_version == "V5"
    ].copy()
    reason_labels = {
        "MARKET_REGIME": "BTC not aligned / market breadth weak",
        "DAILY_LOSS_LIMIT": "Daily loss limit reached",
        "AWAITING_CONFIRMATION": "Waiting for confirmation",
        "COOLDOWN": "Re-entry cooldown active",
        "EXPOSURE_LIMIT": "Maximum exposure reached",
        "ENTRY_QUALITY": "V5 quality filter",
    }
    current_skips["blocked_by"] = current_skips.reason.map(reason_labels).fillna(
        current_skips.reason.str.replace("_", " ").str.title()
    )
    skip_summary = (
        current_skips.groupby("blocked_by", dropna=False)
        .size()
        .reset_index(name="events")
    )
    st.dataframe(skip_summary, use_container_width=True, hide_index=True)
    st.dataframe(
        current_skips.sort_values("id", ascending=False)[
            ["seen_at", "product", "score", "blocked_by", "detail"]
        ].head(100),
        use_container_width=True,
        hide_index=True,
    )



st.subheader("Signal Outcome Tracker")
st.caption(
    "Compares BLOCKED and ALLOWED samples with identical paper costs and exits. "
    "EARLY_SHADOW tests acceleration before confirmation with faster exits. "
    "One active sample per coin/decision prevents duplicate counting."
)
if signal_outcomes.empty:
    st.info("Waiting for the first blocked or allowed signal outcome.")
else:
    outcome_view = signal_outcomes[
        signal_outcomes.strategy_version == "V5"
    ].copy()
    outcome_view["btc_aligned"] = outcome_view["btc_aligned"].map(
        {1: "YES", 0: "NO"}
    )
    outcome_view["market_breadth_pct"] = (
        pd.to_numeric(outcome_view["market_breadth"], errors="coerce") * 100
    )
    finalized_outcomes = outcome_view[outcome_view.status == "FINAL"].copy()
    active_outcomes = outcome_view[outcome_view.status == "OPEN"].copy()

    def bucket_count(decision, result):
        return len(
            finalized_outcomes[
                (finalized_outcomes.decision == decision)
                & (finalized_outcomes.final_result == result)
            ]
        )

    o1, o2, o3, o4, o5 = st.columns(5)
    o1.metric("BLOCKED → WIN", bucket_count("BLOCKED", "WIN"))
    o2.metric("BLOCKED → LOSS", bucket_count("BLOCKED", "LOSS"))
    o3.metric("ALLOWED → WIN", bucket_count("ALLOWED", "WIN"))
    o4.metric("ALLOWED → LOSS", bucket_count("ALLOWED", "LOSS"))
    o5.metric("Active samples", len(active_outcomes))

    early_samples = finalized_outcomes[
        finalized_outcomes.decision == "EARLY_SHADOW"
    ]
    early_count = len(early_samples)
    early_wins = int((early_samples.final_return_pct > 0).sum())
    early_avg = early_samples.final_return_pct.mean() if early_count else 0.0
    e1, e2, e3 = st.columns(3)
    e1.metric("Early shadow exits", early_count)
    e2.metric("Early shadow wins", early_wins)
    e3.metric("Early shadow avg net return", f"{early_avg:+.2f}%")
    st.caption(
        "Early shadow: acceleration with rising price and volume, simulated "
        "0.6% fee + 0.1% slippage per side; 1.5% stop, 2.8% target, "
        "trail after a 2% gain, exit on weakening or after 4 hours. "
        "Prices are checked on completed scanner cycles, so spikes between "
        "cycles may be missed. No early shadow orders are placed."
    )

    if not finalized_outcomes.empty:
        bucket_summary = (
            finalized_outcomes.groupby(["decision", "final_result"], dropna=False)
            .agg(
                samples=("id", "size"),
                avg_return_pct=("final_return_pct", "mean"),
            )
            .reset_index()
        )
        st.markdown("**Signal outcome comparison**")
        st.dataframe(bucket_summary, use_container_width=True, hide_index=True)

    tracker_columns = [
        "created_at", "final_at", "product", "decision", "signal_score",
        "entry_price", "btc_aligned", "market_breadth_pct", "highest_price",
        "lowest_price", "last_price", "status", "final_result",
        "final_return_pct", "exit_reason", "regime_detail",
    ]
    st.markdown("**Tracked signal samples**")
    st.dataframe(
        outcome_view.sort_values("id", ascending=False)[tracker_columns].head(250),
        use_container_width=True,
        hide_index=True,
    )


st.subheader("Momentum State Tracking")
if state_events.empty:
    st.info("No EARLY momentum sequence has been recorded yet.")
else:
    journey_rows = []
    for product, group in state_events.sort_values("id").groupby("product"):
        recent = group.tail(8)
        journey_rows.append(
            {
                "coin": product,
                "started": recent.seen_at.iloc[0],
                "latest": recent.seen_at.iloc[-1],
                "sequence": " → ".join(recent.state.tolist()),
                "latest_score": recent.score.iloc[-1],
            }
        )
    st.markdown("**Signal journeys**")
    st.dataframe(
        pd.DataFrame(journey_rows).sort_values("latest", ascending=False),
        use_container_width=True, hide_index=True,
    )
    state_performance = add_forward_returns(state_events, scans)
    latest_columns = [
        "seen_at", "product", "state", "score", "previous_score", "price",
        "return_15m_pct", "return_1h_pct", "return_4h_pct", "return_24h_pct",
    ]
    st.dataframe(
        state_performance.sort_values("seen_at", ascending=False)[latest_columns].head(250),
        use_container_width=True,
        hide_index=True,
    )


    st.caption(
        "Performance by state — win means price was above the state-event price "
        "at that horizon. Pending horizons stay blank."
    )
    st.dataframe(
        performance_summary(state_performance, "state"),
        use_container_width=True,
        hide_index=True,
    )


st.subheader("Status Changes")
changes = []
for product, group in scans.groupby("product"):
    group = group.sort_values("id")
    previous_row = None
    for _, row in group.iterrows():
        if previous_row is not None and row.status != previous_row.status:
            changes.append(
                {
                    "product": product,
                    "from": previous_row.status,
                    "to": row.status,
                    "old_score": previous_row.score,
                    "new_score": row.score,
                    "seen_at": row.seen_at,
                }
            )
        previous_row = row
change_frame = pd.DataFrame(changes)
if change_frame.empty:
    change_frame = pd.DataFrame(
        columns=["product", "from", "to", "old_score", "new_score", "seen_at"]
    )
else:
    change_frame = change_frame.sort_values("seen_at", ascending=False).head(100)
st.dataframe(change_frame, use_container_width=True, hide_index=True)


st.subheader("Coin Inspector")
selected_product = st.selectbox(
    "Asset", sorted(scans["product"].dropna().unique().tolist())
)
history = (
    scans[scans["product"] == selected_product]
    .sort_values("seen_at")
    .tail(100)
)
selected_events = (
    state_events[state_events["product"] == selected_product]
    .sort_values("seen_at").tail(40)
    if not state_events.empty else pd.DataFrame()
)
price_line = alt.Chart(history).mark_line(color="#4da3ff", strokeWidth=2).encode(
    x=alt.X("seen_at:T", title=None),
    y=alt.Y("price:Q", scale=alt.Scale(zero=False), title="Price"),
    tooltip=[
        "seen_at:T",
        alt.Tooltip("price:Q", format=".8g"),
        alt.Tooltip("score:Q", format=".1f"),
    ],
)
price_chart = price_line
if not selected_events.empty:
    markers = alt.Chart(selected_events).mark_point(size=100, filled=True).encode(
        x="seen_at:T",
        y=alt.Y("price:Q", scale=alt.Scale(zero=False)),
        color=alt.Color(
            "state:N",
            scale=alt.Scale(
                domain=["CONFIRMED", "STRENGTHENING", "HOLD", "EARLY", "WEAKENING", "FAILED"],
                range=["#16c784", "#16c784", "#f4c542", "#f4c542", "#ff8c42", "#ff4b4b"],
            ),
        ),
        tooltip=["seen_at:T", "state:N", alt.Tooltip("score:Q", format=".1f")],
    )
    price_chart = price_line + markers
st.markdown("**Price with signal markers**")
st.altair_chart(price_chart.properties(height=320), use_container_width=True)
score_chart = alt.Chart(history).mark_area(
    line={"color": "#16c784"}, color="#163d35"
).encode(
    x=alt.X("seen_at:T", title=None),
    y=alt.Y("score:Q", scale=alt.Scale(domain=[0, 85]), title="Scanner score"),
    tooltip=["seen_at:T", alt.Tooltip("score:Q", format=".1f"), "status:N"],
)
st.markdown("**Score history**")
st.altair_chart(score_chart.properties(height=220), use_container_width=True)
st.link_button(
    f"Open {selected_product} on TradingView ↗",
    tradingview_url(selected_product),
)


st.subheader("Forward Performance Research")
scan_events = scans[["product", "seen_at", "score", "status", "price"]].copy()
scan_performance = add_forward_returns(scan_events, scans)
st.dataframe(
    scan_performance.sort_values("seen_at", ascending=False).head(250),
    use_container_width=True,
    hide_index=True,
)


evaluated = scan_performance.dropna(subset=["return_1h_pct"]).copy()
if not evaluated.empty:
    evaluated["score_bucket"] = pd.cut(
        evaluated.score, bins=[0, 40, 50, 60, 70, 80, 101], right=False
    )
    score_summary = (
        evaluated.groupby("score_bucket", observed=True)
        .agg(
            observations=("score", "size"),
            avg_1h_return_pct=("return_1h_pct", "mean"),
            median_1h_return_pct=("return_1h_pct", "median"),
        )
        .reset_index()
    )
    st.caption("Score-bucket research — descriptive results, not a recommendation")
    st.dataframe(score_summary, use_container_width=True, hide_index=True)


st.subheader("Performance by Scanner Status")
status_summary = performance_summary(scan_performance, "status")
st.dataframe(status_summary, use_container_width=True, hide_index=True)

st.subheader("Research Lab — shadow only")
st.info(
    "These experiments cannot open, close, or resize V5 trades. They compare "
    "4-hour alignment, market regimes, pullback/retest entries, and parameter "
    "combinations before any rule is considered for promotion."
)

if shadow_evaluations.empty:
    st.caption(
        "The next scanner cycle will create the first shadow evaluation. "
        "V5 continues operating normally."
    )
else:
    latest_shadow_id = shadow_evaluations.scan_id.iloc[-1]
    latest_shadow = shadow_evaluations[
        shadow_evaluations.scan_id == latest_shadow_id
    ].copy()
    shadow_regime = latest_shadow.market_regime.mode().iloc[0]
    s1, s2, s3, s4 = st.columns(4)
    s1.metric("Shadow market", shadow_regime)
    s2.metric(
        "4h bullish",
        f"{int(latest_shadow.trend_4h.sum())}/{len(latest_shadow)}",
    )
    s3.metric("Retest ready", int(latest_shadow.pullback_ready.sum()))
    s4.metric(
        "Would enter",
        int((latest_shadow.shadow_decision == "WOULD_ENTER").sum()),
    )
    latest_shadow["trend_4h"] = latest_shadow.trend_4h.map(
        {1: "Bullish", 0: "Not bullish"}
    )
    latest_shadow["pullback_ready"] = latest_shadow.pullback_ready.map(
        {1: "Ready", 0: "Waiting"}
    )
    st.dataframe(
        latest_shadow[
            [
                "product", "score", "rel_volume", "state", "trend_4h",
                "market_regime", "pullback_ready", "shadow_decision", "detail",
            ]
        ].sort_values(["shadow_decision", "score"], ascending=[False, False]),
        use_container_width=True,
        hide_index=True,
    )
    shadow_entries = shadow_evaluations[
        shadow_evaluations.shadow_decision == "WOULD_ENTER"
    ]
    if not shadow_entries.empty:
        outcome_summary = []
        for label in ["1h", "4h", "24h"]:
            values = shadow_entries[f"return_{label}_pct"].dropna()
            outcome_summary.append(
                {
                    "horizon": label,
                    "evaluated": len(values),
                    "win_rate_pct": (values > 0).mean() * 100 if len(values) else None,
                    "average_return_pct": values.mean() if len(values) else None,
                }
            )
        st.markdown("**Shadow-entry forward results**")
        st.dataframe(
            pd.DataFrame(outcome_summary),
            use_container_width=True,
            hide_index=True,
        )

if backtest_results.empty or backtest_runs.empty:
    st.caption(
        "Historical parameter results will appear after the first offline "
        "research workflow finishes."
    )
else:
    latest_run = backtest_runs.iloc[-1]
    test_results = backtest_results[
        (backtest_results.run_id == latest_run.run_id)
        & (backtest_results.segment == "TEST")
    ].copy()
    train_results = backtest_results[
        (backtest_results.run_id == latest_run.run_id)
        & (backtest_results.segment == "TRAIN")
    ][["parameter_id", "expectancy", "profit_factor"]].rename(
        columns={
            "expectancy": "train_expectancy",
            "profit_factor": "train_profit_factor",
        }
    )
    comparison = test_results.merge(train_results, on="parameter_id", how="left")
    comparison["expectancy_gap"] = (
        comparison.expectancy - comparison.train_expectancy
    ).abs()
    minimum_samples = max(10, int(comparison.trades.quantile(0.35)))
    ranked = comparison[comparison.trades >= minimum_samples].copy()
    ranked = ranked.sort_values(
        ["expectancy", "profit_factor", "expectancy_gap"],
        ascending=[False, False, True],
    )
    st.markdown(
        f"**Offline backtest:** {int(latest_run.days)} days • "
        f"{int(latest_run.products)} coins • "
        f"{int(latest_run.parameter_sets)} parameter sets • "
        "30% unseen test segment"
    )
    st.dataframe(
        ranked[
            [
                "min_score", "min_volume", "confirmation_scans", "require_4h",
                "entry_mode", "trades", "win_rate", "net_pnl", "expectancy",
                "profit_factor", "max_drawdown", "train_expectancy",
                "expectancy_gap",
            ]
        ].head(12),
        use_container_width=True,
        hide_index=True,
    )
    st.caption(
        "Results are ranked for research only. No winning parameter set is "
        "automatically copied into V5."
    )

st.subheader("Settings & emergency controls")
with st.expander("Open control panel"):
    st.warning(
        "Read-only safety mode: these show the live V5 rules. The scheduled scanner "
        "runs on GitHub, so phone controls stay locked until a private GitHub control "
        "token is connected through Streamlit Secrets."
    )
    settings_left, settings_right = st.columns(2)
    with settings_left:
        st.number_input("Minimum EARLY score", value=45.0, disabled=True)
        st.number_input("Entry volume threshold", value=1.50, step=0.05, disabled=True)
        st.number_input("Confirmation scans", value=2, disabled=True)
    with settings_right:
        st.number_input("Stop loss %", value=3.0, step=0.25, disabled=True)
        st.number_input("Profit target %", value=4.0, step=0.25, disabled=True)
        st.number_input("Maximum open trades", value=5, disabled=True)
    e1, e2, e3 = st.columns(3)
    e1.button("⏸ Pause scanner", disabled=True, use_container_width=True)
    e2.button("🛑 Pause entries", disabled=True, use_container_width=True)
    e3.button("▶ Resume", disabled=True, use_container_width=True)
    e4, e5 = st.columns(2)
    e4.button("🧹 Clear stale sequences", disabled=True, use_container_width=True)
    e5.button("🔄 Run manual scan", disabled=True, use_container_width=True)
    st.link_button(
        "Open GitHub Actions controls ↗",
        "https://github.com/yeremi1321/-ai-crypto-paper-trader/actions",
        use_container_width=True,
    )


st.info(
    "V4's scanner is scheduled by GitHub Actions. GitHub may delay scheduled jobs "
    "during high load, so scans are not guaranteed to occur at the exact minute."
)
