import os
import sqlite3
import time
from datetime import datetime, timezone
from zoneinfo import ZoneInfo


import numpy as np
import pandas as pd
import requests




DB = "paper_trader_v4.db"
STRATEGY_VERSION = "V5"
PRODUCTS = [
    "BTC-USD", "ETH-USD", "SOL-USD", "DOGE-USD", "SHIB-USD", "AVAX-USD",
    "LINK-USD", "ADA-USD", "XRP-USD", "LTC-USD", "BCH-USD",
]
EARLY_MIN_SCORE = 45
EARLY_MAX_SCORE = 69.9
SCORE_ACCEL_MIN = 8
VOLUME_ACCEL_MIN = 1.25
STRENGTHEN_SCORE_GAIN = 5
WEAKEN_SCORE_DROP = 8
FAIL_SCORE = 35
PAPER_NOTIONAL_USD = 100.0
PAPER_FEE_RATE = 0.006
PAPER_SLIPPAGE_RATE = 0.001
PAPER_STOP_LOSS_PCT = 3.0
PAPER_PROFIT_TARGET_PCT = 4.0
PAPER_TRAILING_ACTIVATION_PCT = 2.0
PAPER_TRAILING_STOP_PCT = 1.0
# Research-safe umbrella profit lock. V5 production exits remain unchanged until validated.
UMBRELLA_ACTIVATION_PCT = 2.0
UMBRELLA_LOCK_DISTANCE_PCT = 0.50
PAPER_MAX_HOLD_HOURS = 24
PAPER_CONFIRMATION_SCANS = 2
PAPER_WEAKENING_EXIT_SCANS = 2
PAPER_REENTRY_COOLDOWN_HOURS = 2
PAPER_ENTRY_MIN_SCORE = 80.0
PAPER_ENTRY_MIN_REL_VOLUME = 1.50
PAPER_ENTRY_MIN_RSI = 55.0
PAPER_ENTRY_MAX_RSI = 68.0
PAPER_WEAKENING_FAST_LOSS_PCT = -0.75
PAPER_WEAKENING_PROFIT_LOCK_PCT = 1.75
PAPER_DAILY_LOSS_LIMIT_USD = 15.0
MARKET_REGIME_MIN_COVERAGE = 7
MARKET_REGIME_MIN_BREADTH = 0.70
MARKET_REGIME_MAX_AGE_MINUTES = 45
OUTCOME_TRACKER_MAX_HOLD_HOURS = 24
MAX_OPEN_PAPER_TRADES = 5
MAX_PAPER_EXPOSURE_USD = 500.0
REPORT_TIMEZONE = ZoneInfo("America/New_York")
DAILY_REPORT_HOUR = 20


def ensure_column(conn, table, column, definition):
    columns = {
        row[1] for row in conn.execute(f"PRAGMA table_info({table})").fetchall()
    }
    if column not in columns:
        conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")




def db():
    conn = sqlite3.connect(DB)
    conn.execute("""CREATE TABLE IF NOT EXISTS scans(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scan_id TEXT,
        seen_at TEXT,
        product TEXT,
        price REAL,
        score REAL,
        status TEXT,
        rsi REAL,
        rel_volume REAL,
        reason TEXT
    )""")
    conn.execute("""CREATE TABLE IF NOT EXISTS early_events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scan_id TEXT,
        seen_at TEXT,
        product TEXT,
        price REAL,
        score REAL,
        score_accel REAL,
        rel_volume REAL,
        volume_accel REAL
    )""")
    conn.execute("""CREATE TABLE IF NOT EXISTS momentum_tracking(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        seen_at TEXT,
        product TEXT,
        state TEXT,
        score REAL,
        previous_score REAL,
        price REAL
    )""")
    conn.execute("""CREATE TABLE IF NOT EXISTS momentum_sequences(
        product TEXT PRIMARY KEY,
        started_at TEXT,
        state TEXT,
        hold_count INTEGER,
        early_score REAL,
        last_score REAL
    )""")
    conn.execute("""CREATE TABLE IF NOT EXISTS paper_trades(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product TEXT,
        opened_at TEXT,
        entry_state TEXT,
        entry_score REAL,
        entry_market_price REAL,
        entry_price REAL,
        notional_usd REAL,
        quantity REAL,
        entry_fee REAL,
        status TEXT,
        highest_price REAL,
        current_price REAL,
        current_pnl_usd REAL,
        current_return_pct REAL,
        closed_at TEXT,
        exit_state TEXT,
        exit_market_price REAL,
        exit_price REAL,
        exit_fee REAL,
        gross_pnl_usd REAL,
        net_pnl_usd REAL,
        net_return_pct REAL,
        exit_reason TEXT
    )""")
    conn.execute("""CREATE UNIQUE INDEX IF NOT EXISTS one_open_paper_trade_per_product
                    ON paper_trades(product) WHERE status='OPEN'""")
    conn.execute("""CREATE TABLE IF NOT EXISTS paper_daily_reports(
        report_date TEXT PRIMARY KEY,
        sent_at TEXT
    )""")
    conn.execute("""CREATE TABLE IF NOT EXISTS paper_trade_controls(
        product TEXT PRIMARY KEY,
        confirmation_count INTEGER NOT NULL DEFAULT 0,
        weakening_count INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT
    )""")
    conn.execute("""CREATE TABLE IF NOT EXISTS paper_entry_skips(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        seen_at TEXT,
        product TEXT,
        score REAL,
        price REAL,
        reason TEXT,
        detail TEXT
    )""")
    conn.execute("""CREATE TABLE IF NOT EXISTS market_regime_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scan_id TEXT,
        seen_at TEXT,
        allows_entries INTEGER,
        btc_aligned INTEGER,
        market_breadth REAL,
        detail TEXT
    )""")
    conn.execute("""CREATE TABLE IF NOT EXISTS decision_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        seen_at TEXT, scan_id TEXT, product TEXT, stage TEXT, decision TEXT,
        score REAL, price REAL, regime TEXT, detail TEXT, strategy_version TEXT
    )""")
    conn.execute("""CREATE TABLE IF NOT EXISTS signal_outcomes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at TEXT,
        product TEXT,
        decision TEXT,
        signal_score REAL,
        entry_price REAL,
        btc_aligned INTEGER,
        market_breadth REAL,
        regime_detail TEXT,
        status TEXT,
        highest_price REAL,
        lowest_price REAL,
        last_price REAL,
        weakening_count INTEGER NOT NULL DEFAULT 0,
        final_at TEXT,
        final_result TEXT,
        final_return_pct REAL,
        exit_reason TEXT,
        paper_trade_id INTEGER
    )""")
    conn.execute("""CREATE UNIQUE INDEX IF NOT EXISTS
                    one_open_signal_outcome_per_product_decision
                    ON signal_outcomes(product, decision) WHERE status='OPEN'""")
    ensure_column(conn, "paper_trades", "strategy_version", "TEXT")
    ensure_column(conn, "paper_trades", "lowest_price", "REAL")
    ensure_column(conn, "paper_trades", "mfe_pct", "REAL DEFAULT 0")
    ensure_column(conn, "paper_trades", "mae_pct", "REAL DEFAULT 0")
    ensure_column(conn, "paper_trades", "umbrella_activated", "INTEGER DEFAULT 0")
    ensure_column(conn, "paper_trades", "umbrella_stop_price", "REAL")
    ensure_column(conn, "signal_outcomes", "mfe_pct", "REAL DEFAULT 0")
    ensure_column(conn, "signal_outcomes", "mae_pct", "REAL DEFAULT 0")
    ensure_column(conn, "paper_entry_skips", "strategy_version", "TEXT")
    ensure_column(conn, "signal_outcomes", "strategy_version", "TEXT")
    conn.execute("UPDATE paper_trades SET lowest_price=COALESCE(lowest_price, entry_market_price) WHERE lowest_price IS NULL")
    conn.execute(
        "UPDATE paper_trades SET strategy_version='V4' "
        "WHERE strategy_version IS NULL OR strategy_version=''"
    )
    conn.execute(
        "UPDATE paper_entry_skips SET strategy_version='V4' "
        "WHERE strategy_version IS NULL OR strategy_version=''"
    )
    conn.execute(
        "UPDATE signal_outcomes SET strategy_version='V4' "
        "WHERE strategy_version IS NULL OR strategy_version=''"
    )
    conn.commit()
    return conn




def candles(product, granularity, limit=220):
    url = f"https://api.exchange.coinbase.com/products/{product}/candles"
    response = requests.get(
        url,
        params={"granularity": granularity},
        headers={"User-Agent": "paper-v4"},
        timeout=15,
    )
    response.raise_for_status()
    frame = pd.DataFrame(
        response.json()[:limit],
        columns=["time", "low", "high", "open", "close", "volume"],
    )
    frame = frame.sort_values("time").reset_index(drop=True)
    for column in ["low", "high", "open", "close", "volume"]:
        frame[column] = pd.to_numeric(frame[column])
    return frame[frame.time + granularity <= time.time()].copy()




def indicators(frame):
    frame = frame.copy()
    frame["ema20"] = frame.close.ewm(span=20, adjust=False).mean()
    frame["ema50"] = frame.close.ewm(span=50, adjust=False).mean()
    change = frame.close.diff()
    gain = change.clip(lower=0).ewm(alpha=1 / 14, adjust=False).mean()
    loss = (-change.clip(upper=0)).ewm(alpha=1 / 14, adjust=False).mean()
    frame["rsi"] = 100 - (100 / (1 + (gain / loss.replace(0, np.nan))))
    frame["rv"] = frame.volume / frame.volume.rolling(20).mean()
    true_range = pd.concat(
        [
            frame.high - frame.low,
            (frame.high - frame.close.shift()).abs(),
            (frame.low - frame.close.shift()).abs(),
        ],
        axis=1,
    ).max(axis=1)
    frame["atr"] = true_range.rolling(14).mean()
    return frame




def scan_one(product):
    quarter_hour = indicators(candles(product, 900))
    hourly = indicators(candles(product, 3600))
    current, hour = quarter_hour.iloc[-1], hourly.iloc[-1]
    score = 0.0
    reasons = []


    if current.close > current.ema20:
        score += 10
        reasons.append("15m>EMA20")
    if current.ema20 > current.ema50:
        score += 8
        reasons.append("15m trend")
    if 52 <= current.rsi <= 72:
        score += 7
        reasons.append("RSI momentum")


    relative_volume = float(current.rv) if pd.notna(current.rv) else 0
    score += min(25, max(0, (relative_volume - 0.8) * 18))
    if relative_volume >= 1.5:
        reasons.append("volume surge")
    if current.close > quarter_hour.high.iloc[-21:-1].max():
        score += 12
        reasons.append("20-bar breakout")
    if hour.close > hour.ema20:
        score += 8
        reasons.append("1h trend")


    atr_percent = (current.atr / current.close) * 100
    if 0.15 <= atr_percent <= 4:
        score += 10
        reasons.append("tradable ATR")
    if current.volume > 0:
        score += 5


    score = round(min(score, 85), 1)
    status = "SIGNAL" if score >= 80 else ("WATCH" if score >= 70 else "IGNORE")
    return (
        product,
        float(current.close),
        score,
        status,
        round(float(current.rsi), 1),
        round(relative_volume, 2),
        ", ".join(reasons),
    )




def record_state(conn, seen_at, product, state, score, previous_score, price):
    """Record a state transition once and return True when a row was added."""
    latest = conn.execute(
        "SELECT state FROM momentum_tracking WHERE product=? ORDER BY id DESC LIMIT 1",
        (product,),
    ).fetchone()
    if latest and latest[0] == state:
        return False
    conn.execute(
        """INSERT INTO momentum_tracking(
               seen_at, product, state, score, previous_score, price
           ) VALUES(?,?,?,?,?,?)""",
        (seen_at, product, state, score, previous_score, price),
    )
    return True




def paper_control(conn, product):
    conn.execute(
        """INSERT OR IGNORE INTO paper_trade_controls(
               product, confirmation_count, weakening_count, updated_at
           ) VALUES(?,0,0,NULL)""",
        (product,),
    )
    return conn.execute(
        """SELECT confirmation_count, weakening_count
           FROM paper_trade_controls WHERE product=?""",
        (product,),
    ).fetchone()




def update_paper_control(
    conn, product, seen_at, confirmation_count=None, weakening_count=None
):
    current_confirmation, current_weakening = paper_control(conn, product)
    conn.execute(
        """UPDATE paper_trade_controls
           SET confirmation_count=?, weakening_count=?, updated_at=?
           WHERE product=?""",
        (
            current_confirmation if confirmation_count is None else confirmation_count,
            current_weakening if weakening_count is None else weakening_count,
            seen_at,
            product,
        ),
    )




def record_decision(conn, seen_at, scan_id, product, stage, decision, score, price, regime, detail):
    """Append-only audit trail for deterministic decisions and future model comparisons."""
    conn.execute(
        """INSERT INTO decision_log(seen_at, scan_id, product, stage, decision,
               score, price, regime, detail, strategy_version)
           VALUES(?,?,?,?,?,?,?,?,?,?)""",
        (seen_at, scan_id, product, stage, decision, score, price, regime, detail, STRATEGY_VERSION),
    )


def record_entry_skip(conn, seen_at, product, score, price, reason, detail):
    conn.execute(
        """INSERT INTO paper_entry_skips(
               seen_at, product, score, price, reason, detail, strategy_version
           ) VALUES(?,?,?,?,?,?,?)""",
        (seen_at, product, score, price, reason, detail, STRATEGY_VERSION),
    )


def v5_entry_quality(result, previous):
    """Require a fresh, liquid breakout that is still advancing."""
    if not previous:
        return False, "No prior completed scan for continuation check"
    previous_score, _, _, previous_price = previous
    _, price, score, status, rsi, rel_volume, reason = result
    required_reasons = ("15m>EMA20", "15m trend", "20-bar breakout", "1h trend")
    missing = [item for item in required_reasons if item not in (reason or "")]
    failures = []
    if status != "SIGNAL" or score < PAPER_ENTRY_MIN_SCORE:
        failures.append(f"score {score:.1f} below SIGNAL quality")
    if rel_volume < PAPER_ENTRY_MIN_REL_VOLUME:
        failures.append(
            f"volume {rel_volume:.2f}x below {PAPER_ENTRY_MIN_REL_VOLUME:.2f}x"
        )
    if not PAPER_ENTRY_MIN_RSI <= rsi <= PAPER_ENTRY_MAX_RSI:
        failures.append(
            f"RSI {rsi:.1f} outside {PAPER_ENTRY_MIN_RSI:.0f}-{PAPER_ENTRY_MAX_RSI:.0f}"
        )
    if missing:
        failures.append("missing " + ", ".join(missing))
    if price < previous_price:
        failures.append("price did not continue above prior scan")
    if score < previous_score - 2:
        failures.append("score faded more than 2 points")
    return not failures, "; ".join(failures) if failures else "V5 quality passed"


def daily_realized_pnl(conn, now):
    local_date = now.astimezone(REPORT_TIMEZONE).date()
    total = 0.0
    rows = conn.execute(
        """SELECT closed_at, net_pnl_usd FROM paper_trades
           WHERE status='CLOSED' AND closed_at IS NOT NULL"""
    ).fetchall()
    for closed_at, net_pnl in rows:
        closed_date = (
            datetime.fromisoformat(closed_at).astimezone(REPORT_TIMEZONE).date()
        )
        if closed_date == local_date:
            total += net_pnl or 0.0
    return total


def weakening_exit_reason(
    momentum_state,
    weakening_scan,
    market_return_pct,
    high_gain_pct,
    pullback_from_high_pct,
    age_hours,
    weakening_count,
):
    if momentum_state == "FAILED":
        return "STATE_FAILED"
    if market_return_pct <= -PAPER_STOP_LOSS_PCT:
        return "STOP_LOSS"
    if market_return_pct >= PAPER_PROFIT_TARGET_PCT:
        return "PROFIT_TARGET"
    if (
        high_gain_pct >= PAPER_TRAILING_ACTIVATION_PCT
        and pullback_from_high_pct <= -PAPER_TRAILING_STOP_PCT
    ):
        return "TRAILING_STOP"
    if age_hours >= PAPER_MAX_HOLD_HOURS:
        return "TIME_EXIT_24H"
    if weakening_scan and (
        market_return_pct <= PAPER_WEAKENING_FAST_LOSS_PCT
        or market_return_pct >= PAPER_WEAKENING_PROFIT_LOCK_PCT
    ):
        return "STATE_WEAKENING_RISK"
    if weakening_count >= PAPER_WEAKENING_EXIT_SCANS:
        return "STATE_WEAKENING_2X"
    return None





def start_signal_outcome(
    conn,
    now,
    product,
    decision,
    score,
    price,
    btc_aligned,
    market_breadth,
    regime_detail,
    paper_trade_id=None,
):
    """Start one independent outcome sample per product and decision."""
    existing = conn.execute(
        """SELECT id FROM signal_outcomes
           WHERE product=? AND decision=? AND status='OPEN' LIMIT 1""",
        (product, decision),
    ).fetchone()
    if existing:
        return False
    conn.execute(
        """INSERT INTO signal_outcomes(
               created_at, product, decision, signal_score, entry_price,
               btc_aligned, market_breadth, regime_detail, status,
               highest_price, lowest_price, last_price, weakening_count,
               paper_trade_id, strategy_version
           ) VALUES(?,?,?,?,?,?,?,?, 'OPEN', ?,?,?,0,?,?)""",
        (
            now.isoformat(),
            product,
            decision,
            score,
            price,
            int(bool(btc_aligned)),
            market_breadth,
            regime_detail,
            price,
            price,
            price,
            paper_trade_id,
            STRATEGY_VERSION,
        ),
    )
    return True


def update_signal_outcomes(
    conn, now, product, market_price, momentum_state, weakening_scan
):
    """Mark shadow and allowed samples using the same costs and exit rules."""
    rows = conn.execute(
        """SELECT id, decision, created_at, entry_price, highest_price,
                  lowest_price, weakening_count
           FROM signal_outcomes
           WHERE product=? AND status='OPEN'""",
        (product,),
    ).fetchall()
    alerts = []
    for (
        outcome_id,
        decision,
        created_at,
        entry_market_price,
        previous_high,
        previous_low,
        weakening_count,
    ) in rows:
        highest_price = max(previous_high or market_price, market_price)
        lowest_price = min(previous_low or market_price, market_price)
        weakening_count = weakening_count + 1 if weakening_scan else 0
        market_return_pct = ((market_price / entry_market_price) - 1) * 100
        high_gain_pct = ((highest_price / entry_market_price) - 1) * 100
        pullback_from_high_pct = ((market_price / highest_price) - 1) * 100
        age_hours = (
            now - datetime.fromisoformat(created_at)
        ).total_seconds() / 3600

        entry_fill = entry_market_price * (1 + PAPER_SLIPPAGE_RATE)
        entry_fee = PAPER_NOTIONAL_USD * PAPER_FEE_RATE
        quantity = (PAPER_NOTIONAL_USD - entry_fee) / entry_fill
        exit_fill = market_price * (1 - PAPER_SLIPPAGE_RATE)
        exit_value = quantity * exit_fill
        exit_fee = exit_value * PAPER_FEE_RATE
        net_pnl = exit_value - exit_fee - PAPER_NOTIONAL_USD
        net_return_pct = (net_pnl / PAPER_NOTIONAL_USD) * 100

        exit_reason = weakening_exit_reason(
            momentum_state,
            weakening_scan,
            market_return_pct,
            high_gain_pct,
            pullback_from_high_pct,
            age_hours,
            weakening_count,
        )

        if exit_reason:
            final_result = "WIN" if net_pnl > 0 else "LOSS"
            conn.execute(
                """UPDATE signal_outcomes
                   SET status='FINAL', highest_price=?, lowest_price=?,
                       last_price=?, weakening_count=?, final_at=?,
                       final_result=?, final_return_pct=?, exit_reason=?
                   WHERE id=?""",
                (
                    highest_price,
                    lowest_price,
                    market_price,
                    weakening_count,
                    now.isoformat(),
                    final_result,
                    net_return_pct,
                    exit_reason,
                    outcome_id,
                ),
            )
            icon = "📈" if final_result == "WIN" else "📉"
            alerts.append(
                f"{icon} OUTCOME {decision} → {final_result} {product} — "
                f"{net_return_pct:+.2f}% — {exit_reason}"
            )
        else:
            conn.execute(
                """UPDATE signal_outcomes
                   SET highest_price=?, lowest_price=?, last_price=?,
                       weakening_count=?
                   WHERE id=?""",
                (
                    highest_price,
                    lowest_price,
                    market_price,
                    weakening_count,
                    outcome_id,
                ),
            )
    return alerts


def outcome_bucket_summary(conn):
    counts = {
        ("BLOCKED", "WIN"): 0,
        ("BLOCKED", "LOSS"): 0,
        ("ALLOWED", "WIN"): 0,
        ("ALLOWED", "LOSS"): 0,
    }
    rows = conn.execute(
        """SELECT decision, final_result, COUNT(*)
           FROM signal_outcomes
           WHERE status='FINAL'
           GROUP BY decision, final_result"""
    ).fetchall()
    for decision, final_result, count in rows:
        if (decision, final_result) in counts:
            counts[(decision, final_result)] = count
    active = conn.execute(
        "SELECT COUNT(*) FROM signal_outcomes WHERE status='OPEN'"
    ).fetchone()[0]
    return (
        f"Tracker B {counts[('BLOCKED', 'WIN')]}W/"
        f"{counts[('BLOCKED', 'LOSS')]}L • "
        f"A {counts[('ALLOWED', 'WIN')]}W/"
        f"{counts[('ALLOWED', 'LOSS')]}L • Active {active}"
    )


def market_regime(conn):
    """Allow entries only when BTC and most tracked coins have aligned trends."""
    rows = conn.execute(
        """SELECT s.product, s.reason
           FROM scans s
           JOIN (
               SELECT product, MAX(id) AS latest_id
               FROM scans
               WHERE julianday(seen_at) >= julianday('now', ?)
               GROUP BY product
           ) latest ON latest.latest_id = s.id""",
        (f"-{MARKET_REGIME_MAX_AGE_MINUTES} minutes",),
    ).fetchall()
    trend_by_product = {
        product: "15m>EMA20" in (reason or "") and "1h trend" in (reason or "")
        for product, reason in rows
    }
    aligned_count = sum(trend_by_product.values())
    breadth = aligned_count / len(rows) if rows else 0.0
    btc_aligned = trend_by_product.get("BTC-USD", False)
    if len(rows) < MARKET_REGIME_MIN_COVERAGE:
        detail = f"insufficient fresh coverage ({len(rows)}/{len(PRODUCTS)})"
        return False, detail, btc_aligned, breadth
    detail = (
        f"BTC {'aligned' if btc_aligned else 'not aligned'}; "
        f"breadth {aligned_count}/{len(rows)} ({breadth:.0%})"
    )
    return (
        btc_aligned and breadth >= MARKET_REGIME_MIN_BREADTH,
        detail,
        btc_aligned,
        breadth,
    )




def open_paper_trade(conn, seen_at, product, score, market_price):
    """Open one simulated $100 position after the entry filters pass."""
    existing = conn.execute(
        "SELECT id FROM paper_trades WHERE product=? AND status='OPEN' LIMIT 1",
        (product,),
    ).fetchone()
    if existing:
        return None


    open_count, open_exposure = conn.execute(
        """SELECT COUNT(*), COALESCE(SUM(notional_usd), 0)
           FROM paper_trades WHERE status='OPEN'"""
    ).fetchone()
    if (
        open_count >= MAX_OPEN_PAPER_TRADES
        or open_exposure + PAPER_NOTIONAL_USD > MAX_PAPER_EXPOSURE_USD
    ):
        return (
            f"🛑 PAPER SKIP {product} — exposure limit reached "
            f"({open_count} open / ${open_exposure:.0f})"
        )


    entry_price = market_price * (1 + PAPER_SLIPPAGE_RATE)
    entry_fee = PAPER_NOTIONAL_USD * PAPER_FEE_RATE
    quantity = (PAPER_NOTIONAL_USD - entry_fee) / entry_price
    conn.execute(
        """INSERT INTO paper_trades(
               product, opened_at, entry_state, entry_score,
               entry_market_price, entry_price, notional_usd, quantity,
               entry_fee, status, highest_price, lowest_price, current_price,
               current_pnl_usd, current_return_pct, strategy_version
           ) VALUES(?,?,?,?,?,?,?,?,?,'OPEN',?,?,?,?,?,?)""",
        (
            product,
            seen_at,
            "CONFIRMED",
            score,
            market_price,
            entry_price,
            PAPER_NOTIONAL_USD,
            quantity,
            entry_fee,
            market_price,
            market_price,
            market_price,
            -entry_fee,
            (-entry_fee / PAPER_NOTIONAL_USD) * 100,
            STRATEGY_VERSION,
        ),
    )
    return (
        f"🧪 PAPER OPEN {product} — CONFIRMED {score} — "
        f"Simulated ${PAPER_NOTIONAL_USD:.0f} at ${market_price}"
    )




def consider_paper_entry(
    conn, now, product, score, market_price, qualifies, regime_allows,
    regime_detail, btc_aligned, market_breadth
):
    """Require persistent confirmation and enforce a per-product cooldown."""
    existing = conn.execute(
        "SELECT 1 FROM paper_trades WHERE product=? AND status='OPEN' LIMIT 1",
        (product,),
    ).fetchone()
    confirmation_count, _ = paper_control(conn, product)
    if existing:
        if confirmation_count:
            update_paper_control(
                conn, product, now.isoformat(), confirmation_count=0
            )
        return None


    if not qualifies:
        if confirmation_count:
            update_paper_control(
                conn, product, now.isoformat(), confirmation_count=0
            )
        return None


    if not regime_allows:
        if confirmation_count:
            update_paper_control(
                conn, product, now.isoformat(), confirmation_count=0
            )
        start_signal_outcome(
            conn,
            now,
            product,
            "BLOCKED",
            score,
            market_price,
            btc_aligned,
            market_breadth,
            regime_detail,
        )
        record_entry_skip(
            conn,
            now.isoformat(),
            product,
            score,
            market_price,
            "MARKET_REGIME",
            regime_detail,
        )
        return f"🌧️ PAPER BLOCK {product} — market regime — {regime_detail}"

    realized_today = daily_realized_pnl(conn, now)
    if realized_today <= -PAPER_DAILY_LOSS_LIMIT_USD:
        if confirmation_count:
            update_paper_control(
                conn, product, now.isoformat(), confirmation_count=0
            )
        detail = (
            f"daily realized P/L ${realized_today:+.2f}; "
            f"limit -${PAPER_DAILY_LOSS_LIMIT_USD:.0f}"
        )
        record_entry_skip(
            conn,
            now.isoformat(),
            product,
            score,
            market_price,
            "DAILY_LOSS_LIMIT",
            detail,
        )
        return f"🛑 PAPER BLOCK {product} — {detail}"


    confirmation_count += 1
    update_paper_control(
        conn, product, now.isoformat(), confirmation_count=confirmation_count
    )
    if confirmation_count < PAPER_CONFIRMATION_SCANS:
        record_entry_skip(
            conn,
            now.isoformat(),
            product,
            score,
            market_price,
            "AWAITING_CONFIRMATION",
            f"{confirmation_count}/{PAPER_CONFIRMATION_SCANS} qualifying scans",
        )
        return (
            f"⏸️ PAPER WAIT {product} — confirmation "
            f"{confirmation_count}/{PAPER_CONFIRMATION_SCANS}"
        )


    update_paper_control(conn, product, now.isoformat(), confirmation_count=0)
    last_close = conn.execute(
        """SELECT closed_at FROM paper_trades
           WHERE product=? AND status='CLOSED' AND closed_at IS NOT NULL
           ORDER BY id DESC LIMIT 1""",
        (product,),
    ).fetchone()
    if last_close:
        closed_at = datetime.fromisoformat(last_close[0])
        cooldown_age = (now - closed_at).total_seconds() / 3600
        if cooldown_age < PAPER_REENTRY_COOLDOWN_HOURS:
            remaining = PAPER_REENTRY_COOLDOWN_HOURS - cooldown_age
            record_entry_skip(
                conn,
                now.isoformat(),
                product,
                score,
                market_price,
                "COOLDOWN",
                f"{remaining:.2f} hours remaining",
            )
            return f"🧊 PAPER COOLDOWN {product} — {remaining:.1f}h remaining"


    alert = open_paper_trade(conn, now.isoformat(), product, score, market_price)
    if alert and "PAPER SKIP" in alert:
        record_entry_skip(
            conn,
            now.isoformat(),
            product,
            score,
            market_price,
            "EXPOSURE_LIMIT",
            alert,
        )
    elif alert and "PAPER OPEN" in alert:
        paper_trade = conn.execute(
            """SELECT id FROM paper_trades
               WHERE product=? AND status='OPEN'
               ORDER BY id DESC LIMIT 1""",
            (product,),
        ).fetchone()
        start_signal_outcome(
            conn,
            now,
            product,
            "ALLOWED",
            score,
            market_price,
            btc_aligned,
            market_breadth,
            regime_detail,
            paper_trade[0] if paper_trade else None,
        )
    return alert




def manage_paper_trade(
    conn, now, product, score, market_price, momentum_state, weakening_scan
):
    """Mark an open paper position to market and close it when a rule fires."""
    trade = conn.execute(
        """SELECT id, opened_at, entry_market_price, entry_price,
                  notional_usd, quantity, entry_fee, highest_price, lowest_price
           FROM paper_trades
           WHERE product=? AND status='OPEN'
           ORDER BY id DESC LIMIT 1""",
        (product,),
    ).fetchone()
    if not trade:
        return None


    (
        trade_id,
        opened_at,
        entry_market_price,
        entry_price,
        notional_usd,
        quantity,
        entry_fee,
        previous_high,
        previous_low,
    ) = trade
    highest_price = max(previous_high or market_price, market_price)
    lowest_price = min(previous_low or market_price, market_price)
    mfe_pct = ((highest_price / entry_market_price) - 1) * 100
    mae_pct = ((lowest_price / entry_market_price) - 1) * 100
    umbrella_activated = int(mfe_pct >= UMBRELLA_ACTIVATION_PCT)
    umbrella_stop_price = highest_price * (1 - UMBRELLA_LOCK_DISTANCE_PCT / 100) if umbrella_activated else None
    simulated_exit_price = market_price * (1 - PAPER_SLIPPAGE_RATE)
    exit_value = quantity * simulated_exit_price
    estimated_exit_fee = exit_value * PAPER_FEE_RATE
    gross_pnl = quantity * (simulated_exit_price - entry_price)
    net_pnl = exit_value - estimated_exit_fee - notional_usd
    net_return_pct = (net_pnl / notional_usd) * 100
    market_return_pct = ((market_price / entry_market_price) - 1) * 100
    pullback_from_high_pct = ((market_price / highest_price) - 1) * 100
    high_gain_pct = ((highest_price / entry_market_price) - 1) * 100
    opened = datetime.fromisoformat(opened_at)
    age_hours = (now - opened).total_seconds() / 3600


    _, weakening_count = paper_control(conn, product)
    weakening_count = weakening_count + 1 if weakening_scan else 0
    update_paper_control(
        conn,
        product,
        now.isoformat(),
        weakening_count=weakening_count,
    )


    exit_reason = weakening_exit_reason(
        momentum_state,
        weakening_scan,
        market_return_pct,
        high_gain_pct,
        pullback_from_high_pct,
        age_hours,
        weakening_count,
    )


    if exit_reason:
        conn.execute(
            """UPDATE paper_trades
               SET status='CLOSED', highest_price=?, lowest_price=?, mfe_pct=?, mae_pct=?, umbrella_activated=?, umbrella_stop_price=?, current_price=?,
                   current_pnl_usd=?, current_return_pct=?, closed_at=?,
                   exit_state=?, exit_market_price=?, exit_price=?, exit_fee=?,
                   gross_pnl_usd=?, net_pnl_usd=?, net_return_pct=?, exit_reason=?
               WHERE id=?""",
            (
                highest_price,
                lowest_price,
                mfe_pct,
                mae_pct,
                umbrella_activated,
                umbrella_stop_price,
                market_price,
                net_pnl,
                net_return_pct,
                now.isoformat(),
                "WEAKENING" if exit_reason == "STATE_WEAKENING_2X" else momentum_state,
                market_price,
                simulated_exit_price,
                estimated_exit_fee,
                gross_pnl,
                net_pnl,
                net_return_pct,
                exit_reason,
                trade_id,
            ),
        )
        update_paper_control(
            conn,
            product,
            now.isoformat(),
            confirmation_count=0,
            weakening_count=0,
        )
        result_word = "WIN" if net_pnl > 0 else "LOSS"
        return (
            f"🧾 PAPER CLOSE {product} — {exit_reason} — {result_word} "
            f"${net_pnl:+.2f} ({net_return_pct:+.2f}%)"
        )


    conn.execute(
        """UPDATE paper_trades
           SET highest_price=?, lowest_price=?, mfe_pct=?, mae_pct=?,
               umbrella_activated=?, umbrella_stop_price=?, current_price=?, current_pnl_usd=?,
               current_return_pct=?
           WHERE id=?""",
        (highest_price, lowest_price, mfe_pct, mae_pct, umbrella_activated,
         umbrella_stop_price, market_price, net_pnl, net_return_pct, trade_id),
    )
    return None




def open_positions_summary(conn):
    """Return a compact mark-to-market summary for meaningful alert batches."""
    rows = conn.execute(
        """SELECT product, current_pnl_usd, current_return_pct
           FROM paper_trades WHERE status='OPEN'
           ORDER BY opened_at"""
    ).fetchall()
    if not rows:
        return None
    total_pnl = sum(row[1] or 0 for row in rows)
    positions = ", ".join(
        f"{product} ${pnl:+.2f} ({return_pct:+.2f}%)"
        for product, pnl, return_pct in rows
    )
    return f"📂 OPEN {len(rows)}/5 — {positions} — Total ${total_pnl:+.2f}"




def maybe_daily_report(conn, now):
    """Create one 8 PM Eastern paper-performance report per local date."""
    local_now = now.astimezone(REPORT_TIMEZONE)
    report_date = local_now.date().isoformat()
    if local_now.hour < DAILY_REPORT_HOUR:
        return None
    already_sent = conn.execute(
        "SELECT 1 FROM paper_daily_reports WHERE report_date=?", (report_date,)
    ).fetchone()
    if already_sent:
        return None


    closed_rows = conn.execute(
        """SELECT closed_at, net_pnl_usd
           FROM paper_trades WHERE status='CLOSED' AND closed_at IS NOT NULL"""
    ).fetchall()
    todays_results = []
    for closed_at, net_pnl in closed_rows:
        closed_local = datetime.fromisoformat(closed_at).astimezone(REPORT_TIMEZONE)
        if closed_local.date().isoformat() == report_date:
            todays_results.append(net_pnl or 0)


    open_count, open_pnl, open_exposure = conn.execute(
        """SELECT COUNT(*), COALESCE(SUM(current_pnl_usd), 0),
                  COALESCE(SUM(notional_usd), 0)
           FROM paper_trades WHERE status='OPEN'"""
    ).fetchone()
    wins = sum(value > 0 for value in todays_results)
    losses = sum(value <= 0 for value in todays_results)
    realized = sum(todays_results)
    conn.execute(
        "INSERT INTO paper_daily_reports(report_date, sent_at) VALUES(?,?)",
        (report_date, now.isoformat()),
    )
    return (
        f"📅 DAILY PAPER REPORT {report_date} — Closed {len(todays_results)} "
        f"({wins}W/{losses}L) — Realized ${realized:+.2f} — "
        f"Open {open_count}/5 (${open_exposure:.0f} exposure) — "
        f"Open P/L ${open_pnl:+.2f} — {outcome_bucket_summary(conn)}"
    )




conn = db()
now = datetime.now(timezone.utc)
seen_at = now.isoformat()
scan_id = now.strftime("%Y%m%dT%H%M%SZ")
alerts = []
regime_allows_entries, regime_detail, btc_aligned, market_breadth = market_regime(conn)
conn.execute(
    """INSERT INTO market_regime_log(
           scan_id, seen_at, allows_entries, btc_aligned, market_breadth, detail
       ) VALUES(?,?,?,?,?,?)""",
    (
        scan_id,
        seen_at,
        int(bool(regime_allows_entries)),
        int(bool(btc_aligned)),
        market_breadth,
        regime_detail,
    ),
)


for product in PRODUCTS:
    try:
        result = scan_one(product)
        previous = conn.execute(
            """SELECT score, rel_volume, status, price
               FROM scans
               WHERE product=?
               ORDER BY id DESC
               LIMIT 1""",
            (product,),
        ).fetchone()


        previous_score = previous[0] if previous else result[2]
        score_acceleration = result[2] - previous_score if previous else 0
        volume_acceleration = 0
        if previous and previous[1] and previous[1] > 0:
            volume_acceleration = result[5] / previous[1]


        is_early = bool(
            previous
            and EARLY_MIN_SCORE <= result[2] <= EARLY_MAX_SCORE
            and score_acceleration >= SCORE_ACCEL_MIN
            and volume_acceleration >= VOLUME_ACCEL_MIN
        )
        recent_early = conn.execute(
            """SELECT seen_at, price, score
               FROM early_events
               WHERE product=?
                 AND julianday(seen_at) >= julianday('now','-2 hours')
               ORDER BY id DESC
               LIMIT 1""",
            (product,),
        ).fetchone()
        sequence = conn.execute(
            """SELECT state, hold_count, early_score, last_score
               FROM momentum_sequences WHERE product=?""",
            (product,),
        ).fetchone()
        latest_momentum_state = conn.execute(
            """SELECT state
               FROM momentum_tracking
               WHERE product=?
               ORDER BY id DESC
               LIMIT 1""",
            (product,),
        ).fetchone()


        started_early_now = False
        if is_early and not recent_early and not sequence:
            conn.execute(
                """INSERT INTO early_events(
                       scan_id, seen_at, product, price, score,
                       score_accel, rel_volume, volume_accel
                   ) VALUES(?,?,?,?,?,?,?,?)""",
                (
                    scan_id, seen_at, result[0], result[1], result[2],
                    score_acceleration, result[5], volume_acceleration,
                ),
            )
            conn.execute(
                """INSERT OR REPLACE INTO momentum_sequences(
                       product, started_at, state, hold_count, early_score, last_score
                   ) VALUES(?,?,?,?,?,?)""",
                (result[0], seen_at, "EARLY", 0, result[2], result[2]),
            )
            record_state(
                conn, seen_at, result[0], "EARLY", result[2], previous_score, result[1]
            )
            alerts.append(
                f"🚨 EARLY {result[0]} — Score {result[2]} — "
                f"Jump +{score_acceleration:.1f} — Volume {volume_acceleration:.2f}x"
            )
            sequence = ("EARLY", 0, result[2], result[2])
            started_early_now = True


        # Recover a recent sequence if an older run stored EARLY but stopped early.
        if (
            not sequence
            and recent_early
            and (
                not latest_momentum_state
                or latest_momentum_state[0] != "FAILED"
            )
        ):
            conn.execute(
                """INSERT OR REPLACE INTO momentum_sequences(
                       product, started_at, state, hold_count, early_score, last_score
                   ) VALUES(?,?,?,?,?,?)""",
                (product, recent_early[0], "EARLY", 0, recent_early[2], result[2]),
            )
            record_state(
                conn,
                recent_early[0],
                product,
                "EARLY",
                recent_early[2],
                recent_early[2],
                recent_early[1],
            )
            sequence = ("EARLY", 0, recent_early[2], result[2])


        sequence_state_before = sequence[0] if sequence else None
        next_state = None
        hold_alert = False

        if sequence and not started_early_now:
            sequence_state, hold_count, early_score, last_score = sequence

            if result[2] <= FAIL_SCORE:
                next_state = "FAILED"

            elif sequence_state == "EARLY":
                score_holding = result[2] >= (last_score - 2)
                volume_holding = result[5] >= 1.25

                if score_holding and volume_holding:
                    hold_count += 1
                else:
                    hold_count = 0

                if hold_count >= 2:
                    next_state = "STRENGTHENING"
                elif hold_count == 1:
                    hold_alert = True

            elif previous_score - result[2] >= WEAKEN_SCORE_DROP:
                next_state = "WEAKENING"

            elif (
                result[3] in ("WATCH", "SIGNAL")
                and sequence_state not in ("CONFIRMED", "WATCH")
            ):
                next_state = "CONFIRMED"

            elif result[3] == "WATCH" and sequence_state == "CONFIRMED":
                next_state = "WATCH"

            elif (
                sequence_state == "WEAKENING"
                and result[2] - previous_score >= STRENGTHEN_SCORE_GAIN
            ):
                next_state = "STRENGTHENING"

            if hold_alert:
                alerts.append(
                    f"⌛ HOLD 1 {result[0]} — Score {result[2]} — Price ${result[1]}"
                )


            if next_state:
                added = record_state(
                    conn,
                    seen_at,
                    result[0],
                    next_state,
                    result[2],
                    previous_score,
                    result[1],
                )
                if added:
                    alerts.append(
                        f"📊 {result[0]} — {next_state} — "
                        f"Score {result[2]} — Price ${result[1]}"
                    )


                if next_state == "FAILED":
                    conn.execute(
                        "DELETE FROM momentum_sequences WHERE product=?", (result[0],)
                    )
                else:
                    conn.execute(
                        """UPDATE momentum_sequences
                           SET state=?, hold_count=?, last_score=?
                           WHERE product=?""",
                        (next_state, hold_count, result[2], result[0]),
                    )
            else:
                conn.execute(
                    """UPDATE momentum_sequences
                       SET hold_count=?, last_score=?
                       WHERE product=?""",
                    (hold_count, result[2], result[0]),
                )


        sequence_entry_ready = bool(
            next_state == "CONFIRMED"
            or (
                sequence_state_before in ("CONFIRMED", "WATCH")
                and result[3] in ("WATCH", "SIGNAL")
                and next_state not in ("FAILED", "WEAKENING")
            )
        )
        quality_passed, quality_detail = v5_entry_quality(result, previous)
        entry_qualifies = sequence_entry_ready and quality_passed
        record_decision(
            conn, seen_at, scan_id, result[0], "ENTRY_FILTER",
            "QUALIFIES" if entry_qualifies else "REJECT", result[2], result[1],
            regime_detail, quality_detail if sequence_entry_ready else "momentum sequence not entry-ready"
        )
        if sequence_entry_ready and not quality_passed:
            record_entry_skip(
                conn,
                now.isoformat(),
                result[0],
                result[2],
                result[1],
                "ENTRY_QUALITY",
                quality_detail,
            )
        paper_entry_alert = consider_paper_entry(
            conn,
            now,
            result[0],
            result[2],
            result[1],
            entry_qualifies,
            regime_allows_entries,
            regime_detail,
            btc_aligned,
            market_breadth,
        )
        if paper_entry_alert:
            alerts.append(paper_entry_alert)


        weakening_scan = bool(
            next_state == "WEAKENING"
            or (
                sequence_state_before == "WEAKENING"
                and next_state not in ("STRENGTHENING", "CONFIRMED", "WATCH")
                and result[3] == "IGNORE"
            )
        )


        paper_close_alert = manage_paper_trade(
            conn,
            now,
            result[0],
            result[2],
            result[1],
            next_state,
            weakening_scan,
        )
        if paper_close_alert:
            alerts.append(paper_close_alert)


        outcome_alerts = update_signal_outcomes(
            conn,
            now,
            result[0],
            result[1],
            next_state,
            weakening_scan,
        )
        alerts.extend(outcome_alerts)


        conn.execute(
            """INSERT INTO scans(
                   scan_id, seen_at, product, price, score,
                   status, rsi, rel_volume, reason
               ) VALUES(?,?,?,?,?,?,?,?,?)""",
            (scan_id, seen_at, *result),
        )
        print(result[0], result[2], result[3])


        status_changed = not previous or previous[2] != result[3]
        if result[3] in ("WATCH", "SIGNAL") and status_changed and not next_state:
            alerts.append(
                f"{result[0]} → {result[3]} — Score {result[2]} — Price ${result[1]}"
            )


    except Exception as exc:
        print("ERROR", product, exc)


if alerts and os.environ.get("NTFY_DISABLED") != "1":
    positions_alert = open_positions_summary(conn)
    if positions_alert:
        alerts.append(positions_alert)


daily_report = maybe_daily_report(conn, now)
if daily_report:
    alerts.append(daily_report)


conn.commit()
conn.close()


if alerts:
    requests.post(
        "https://ntfy.sh/gonzaleztradealerts",
        data=("\n".join(alerts)).encode("utf-8"),
        headers={"Title": "Crypto Scanner Alert"},
        timeout=10,
    )
