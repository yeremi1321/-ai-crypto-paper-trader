import os
import sqlite3

import pandas as pd
import streamlit as st


DB = "paper_trader_v4.db"
HORIZONS = [("15m", 15), ("1h", 60), ("4h", 240), ("24h", 1440)]

st.set_page_config(
    page_title="AI Crypto Paper Trader V4", page_icon="📡", layout="wide"
)
st.title("AI Crypto Paper Trader — V4")
st.caption(
    "Automatic scheduled research scanner • Persistent GitHub history • "
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
conn.close()

if scans.empty:
    st.info("Waiting for the first scheduled scan.")
    st.stop()

scans["seen_at"] = pd.to_datetime(scans["seen_at"], utc=True)
if not state_events.empty:
    state_events["seen_at"] = pd.to_datetime(state_events["seen_at"], utc=True)
if not paper_trades.empty:
    paper_trades["opened_at"] = pd.to_datetime(paper_trades["opened_at"], utc=True)
    paper_trades["closed_at"] = pd.to_datetime(
        paper_trades["closed_at"], utc=True, errors="coerce"
    )

latest_scan_id = scans.scan_id.iloc[-1]
current = scans[scans.scan_id == latest_scan_id].copy()
last_time = scans.seen_at.max()
scan_count = scans.scan_id.nunique()
signals = (scans.status == "SIGNAL").sum()
watches = (scans.status == "WATCH").sum()

metric_1, metric_2, metric_3, metric_4 = st.columns(4)
metric_1.metric("Recorded scans", scan_count)
metric_2.metric("Last scan", last_time.strftime("%b %d %H:%M UTC"))
metric_3.metric("WATCH observations", int(watches))
metric_4.metric("SIGNAL observations", int(signals))

st.subheader("Latest Automatic Scan")
st.dataframe(
    current[["product", "price", "score", "status", "rsi", "rel_volume", "reason"]],
    use_container_width=True,
    hide_index=True,
)

st.subheader("Automatic Paper Trading")
st.caption(
    "Research simulation only: $100 per CONFIRMED entry • 3% stop • 6% target • "
    "3% trailing stop after a 3% gain • 24-hour maximum hold • "
    "maximum 5 open trades / $500 exposure • "
    "2 qualifying scans to enter • 2 weakening scans to exit • "
    "2-hour re-entry cooldown • "
    "0.6% estimated fee and 0.1% slippage per side"
)
if paper_trades.empty:
    st.info("Waiting for the first CONFIRMED setup to open a simulated trade.")
else:
    open_trades = paper_trades[paper_trades.status == "OPEN"].copy()
    closed_trades = paper_trades[paper_trades.status == "CLOSED"].copy()

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
    p2.metric("Closed paper trades", closed_count)
    p3.metric("Win rate", f"{win_rate:.1f}%")
    p4.metric("Net paper P/L", f"${total_net_pnl:+.2f}")
    p5.metric("Avg return", f"{average_return:+.2f}%")
    p6.metric("Expectancy/trade", f"${expectancy:+.2f}")
    st.caption(f"Realized paper P/L drawdown: ${realized_drawdown:.2f}")

    if open_count:
        st.markdown("**Open simulated positions**")
        st.dataframe(
            open_trades[
                [
                    "opened_at", "product", "entry_score", "entry_market_price",
                    "current_price", "current_pnl_usd", "current_return_pct",
                    "highest_price",
                ]
            ].sort_values("opened_at", ascending=False),
            use_container_width=True,
            hide_index=True,
        )

    if closed_count:
        st.markdown("**Completed simulated trades**")
        st.dataframe(
            closed_trades[
                [
                    "opened_at", "closed_at", "product", "entry_score",
                    "entry_market_price", "exit_market_price", "exit_reason",
                    "net_pnl_usd", "net_return_pct",
                ]
            ].sort_values("closed_at", ascending=False),
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
    skip_summary = (
        paper_entry_skips.groupby("reason", dropna=False)
        .size()
        .reset_index(name="events")
    )
    st.dataframe(skip_summary, use_container_width=True, hide_index=True)
    st.dataframe(
        paper_entry_skips.sort_values("id", ascending=False).head(100),
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

st.subheader("Score History")
selected_product = st.selectbox(
    "Asset", sorted(scans["product"].dropna().unique().tolist())
)
history = scans[scans["product"] == selected_product].set_index("seen_at")
st.line_chart(history["score"])

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
