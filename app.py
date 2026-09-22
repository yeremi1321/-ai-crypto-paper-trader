import os
import sqlite3


import pandas as pd
import streamlit as st




DB = "paper_trader_v4.db"
HORIZONS = [("15m", 15), ("1h", 60), ("4h", 240), ("24h", 1440)]


st.set_page_config(
    page_title="AI Crypto Paper Trader V4", page_icon="📡", layout="wide"
)
st.markdown(
    """
    <style>
    .block-container {padding-top: 1.4rem; padding-bottom: 3rem;}
    [data-testid="stMetric"] {
        background: rgba(120, 120, 120, 0.08);
        border: 1px solid rgba(120, 120, 120, 0.18);
        border-radius: 14px;
        padding: 12px 14px;
    }
    </style>
    <meta http-equiv="refresh" content="60">
    """,
    unsafe_allow_html=True,
)
st.title("AI Crypto Paper Trader — V4")
st.caption(
    "Live scanner control center • Refreshes every 60 seconds • "
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

st.subheader("Live Scanner Control Center")
m1, m2, m3, m4, m5, m6 = st.columns(6)
m1.metric("Scanner", fresh_label, f"{age_minutes} min ago")
m2.metric("Market filter", regime_label)
m3.metric("Open positions", f"{len(open_now)}/5")
m4.metric("Open P/L", f"${open_pnl:+.2f}")
m5.metric("V5 realized P/L", f"${realized_pnl:+.2f}")
m6.metric("V5 win rate", f"{win_rate_now:.1f}%")
st.info(f"**Latest market check:** {regime_detail}")
st.caption(
    f"Last completed scan: {last_time.strftime('%b %d %H:%M UTC')} • "
    f"{scan_count} scan cycles recorded • {int(watches)} WATCH and "
    f"{int(signals)} SIGNAL observations"
)

st.markdown("**What the scanner sees right now**")
st.dataframe(
    current[
        [
            "product", "price", "score", "score_change", "status", "state",
            "action", "rsi", "rel_volume", "chart",
        ]
    ],
    column_config={
        "product": "Coin",
        "price": st.column_config.NumberColumn("Price", format="$%.8g"),
        "score": st.column_config.ProgressColumn(
            "Score", min_value=0, max_value=85, format="%.1f"
        ),
        "score_change": st.column_config.NumberColumn("Change", format="%+.1f"),
        "status": "Scanner",
        "state": "Sequence",
        "action": "Current action",
        "rsi": st.column_config.NumberColumn("RSI", format="%.1f"),
        "rel_volume": st.column_config.NumberColumn("Volume", format="%.2fx"),
        "chart": st.column_config.LinkColumn(
            "TradingView", display_text="Open chart ↗"
        ),
    },
    use_container_width=True,
    hide_index=True,
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

with st.expander("Recent decisions and paper-trade activity", expanded=True):
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
        open_trades["chart"] = open_trades["product"].map(tradingview_url)
        st.dataframe(
            open_trades[
                [
                    "opened_at", "product", "entry_score", "entry_market_price",
                    "current_price", "current_pnl_usd", "current_return_pct",
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
    st.markdown("**Filtered paper entries**")
    current_skips = paper_entry_skips[
        paper_entry_skips.strategy_version == "V5"
    ].copy()
    skip_summary = (
        current_skips.groupby("reason", dropna=False)
        .size()
        .reset_index(name="events")
    )
    st.dataframe(skip_summary, use_container_width=True, hide_index=True)
    st.dataframe(
        paper_entry_skips.sort_values("id", ascending=False).head(100),
        use_container_width=True,
        hide_index=True,
    )



st.subheader("Signal Outcome Tracker")
st.caption(
    "Compares independent BLOCKED and ALLOWED samples with identical paper costs "
    "and exit rules. One active sample per coin/decision prevents duplicate counting."
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

    if not finalized_outcomes.empty:
        bucket_summary = (
            finalized_outcomes.groupby(["decision", "final_result"], dropna=False)
            .agg(
                samples=("id", "size"),
                avg_return_pct=("final_return_pct", "mean"),
            )
            .reset_index()
        )
        st.markdown("**Four-bucket comparison**")
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
    .set_index("seen_at")
)
chart_1, chart_2 = st.columns(2)
with chart_1:
    st.markdown("**Scanner score**")
    st.line_chart(history["score"], height=280)
with chart_2:
    st.markdown("**Recorded market price**")
    st.line_chart(history["price"], height=280)
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


st.info(
    "V4's scanner is scheduled by GitHub Actions. GitHub may delay scheduled jobs "
    "during high load, so scans are not guaranteed to occur at the exact minute."
)
