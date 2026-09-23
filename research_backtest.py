import argparse
import itertools
import sqlite3
import time
from datetime import datetime, timedelta, timezone

import numpy as np
import pandas as pd
import requests


PRODUCTS = [
    "BTC-USD", "ETH-USD", "SOL-USD", "DOGE-USD", "SHIB-USD", "AVAX-USD",
    "LINK-USD", "ADA-USD", "XRP-USD", "LTC-USD", "BCH-USD",
]
DB = "research_backtest.db"
GRANULARITY = 900
NOTIONAL = 100.0
FEE_RATE = 0.006
SLIPPAGE_RATE = 0.001
STOP_PCT = 3.0
TARGET_PCT = 4.0
TRAIL_ACTIVATION_PCT = 2.0
TRAIL_DISTANCE_PCT = 1.0
MAX_HOLD_BARS = 96
WALK_FORWARD_FOLDS = 4


def get_coinbase_json(session, url, params, attempts=4):
    last_error = None
    for attempt in range(attempts):
        try:
            response = session.get(url, params=params, timeout=30)
            response.raise_for_status()
            payload = response.json()
            if not isinstance(payload, list):
                raise RuntimeError(f"Unexpected Coinbase response: {payload!r}")
            return payload
        except (requests.RequestException, ValueError, RuntimeError) as exc:
            last_error = exc
            if attempt + 1 < attempts:
                time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"Coinbase candle request failed after {attempts} attempts") from last_error


def fetch_candles(product, days):
    end = datetime.now(timezone.utc).replace(second=0, microsecond=0)
    start = end - timedelta(days=days)
    chunks = []
    cursor = start
    session = requests.Session()
    session.headers.update({"User-Agent": "v5-shadow-backtest"})
    while cursor < end:
        chunk_end = min(cursor + timedelta(seconds=GRANULARITY * 299), end)
        rows = get_coinbase_json(
            session,
            f"https://api.exchange.coinbase.com/products/{product}/candles",
            {
                "granularity": GRANULARITY,
                "start": cursor.isoformat(),
                "end": chunk_end.isoformat(),
            },
        )
        if rows:
            chunks.extend(rows)
        cursor = chunk_end + timedelta(seconds=GRANULARITY)
        time.sleep(0.12)
    frame = pd.DataFrame(
        chunks, columns=["time", "low", "high", "open", "close", "volume"]
    )
    if frame.empty:
        raise RuntimeError(f"No candles returned for {product}")
    frame = frame.drop_duplicates("time").sort_values("time").reset_index(drop=True)
    frame["time"] = pd.to_datetime(frame["time"], unit="s", utc=True)
    for column in ["low", "high", "open", "close", "volume"]:
        frame[column] = pd.to_numeric(frame[column])
    return frame


def indicators(frame):
    frame = frame.copy()
    frame["ema20"] = frame.close.ewm(span=20, adjust=False).mean()
    frame["ema50"] = frame.close.ewm(span=50, adjust=False).mean()
    change = frame.close.diff()
    gain = change.clip(lower=0).ewm(alpha=1 / 14, adjust=False).mean()
    loss = (-change.clip(upper=0)).ewm(alpha=1 / 14, adjust=False).mean()
    frame["rsi"] = 100 - (100 / (1 + gain / loss.replace(0, np.nan)))
    frame["rel_volume"] = frame.volume / frame.volume.rolling(20).mean()
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


def higher_timeframe(frame, rule):
    indexed = frame.set_index("time")
    output = indexed.resample(rule, label="left", closed="left").agg(
        {"open": "first", "high": "max", "low": "min", "close": "last", "volume": "sum"}
    ).dropna()
    output["ema20"] = output.close.ewm(span=20, adjust=False).mean()
    output["ema50"] = output.close.ewm(span=50, adjust=False).mean()
    duration = pd.Timedelta(rule)
    output["available_at"] = output.index + duration
    return output.reset_index()


def build_features(raw):
    frame = indicators(raw)
    frame["decision_at"] = frame.time + pd.Timedelta(minutes=15)
    hourly = higher_timeframe(raw, "1h")[["available_at", "close", "ema20"]].rename(
        columns={"close": "close_1h", "ema20": "ema20_1h"}
    )
    four_hour = higher_timeframe(raw, "4h")[
        ["available_at", "close", "ema20", "ema50"]
    ].rename(
        columns={"close": "close_4h", "ema20": "ema20_4h", "ema50": "ema50_4h"}
    )
    frame = pd.merge_asof(
        frame.sort_values("decision_at"),
        hourly.sort_values("available_at"),
        left_on="decision_at",
        right_on="available_at",
        direction="backward",
    ).drop(columns=["available_at"])
    frame = pd.merge_asof(
        frame.sort_values("decision_at"),
        four_hour.sort_values("available_at"),
        left_on="decision_at",
        right_on="available_at",
        direction="backward",
    ).drop(columns=["available_at"])
    frame["breakout_level"] = frame.high.shift(1).rolling(20).max()
    frame["breakout"] = frame.close > frame.breakout_level
    recent_level = frame.breakout_level.where(frame.breakout).ffill(limit=4)
    frame["retest"] = (
        recent_level.notna()
        & (frame.low <= recent_level * 1.004)
        & (frame.close >= recent_level * 0.998)
        & (frame.close > frame.ema20)
    )
    frame["trend_15m"] = frame.ema20 > frame.ema50
    frame["trend_1h"] = frame.close_1h > frame.ema20_1h
    frame["trend_4h"] = (frame.close_4h > frame.ema20_4h) & (
        frame.ema20_4h > frame.ema50_4h
    )
    score = (
        (frame.close > frame.ema20).astype(float) * 10
        + frame.trend_15m.astype(float) * 8
        + frame.rsi.between(52, 72).astype(float) * 7
        + ((frame.rel_volume - 0.8) * 18).clip(lower=0, upper=25)
        + frame.breakout.astype(float) * 12
        + frame.trend_1h.astype(float) * 8
        + ((frame.atr / frame.close * 100).between(0.15, 4)).astype(float) * 10
        + (frame.volume > 0).astype(float) * 5
    )
    frame["score"] = score.clip(upper=85).round(1)
    return frame.dropna(
        subset=["rsi", "rel_volume", "ema50", "close_1h", "ema20_1h", "close_4h"]
    ).reset_index(drop=True)


def entry_mask(frame, params):
    structure = frame["breakout"] if params["entry_mode"] == "BREAKOUT" else frame["retest"]
    mask = (
        (frame.score >= params["min_score"])
        & (frame.rel_volume >= params["min_volume"])
        & frame.rsi.between(55, 68)
        & frame.trend_15m
        & frame.trend_1h
        & structure
        & (frame.close >= frame.close.shift(1))
        & (frame.score >= frame.score.shift(1) - 2)
    )
    if params["require_4h"]:
        mask &= frame.trend_4h
    return mask.fillna(False)


def close_trade(frame, entry_index):
    entry_market = float(frame.at[entry_index, "close"])
    entry_fill = entry_market * (1 + SLIPPAGE_RATE)
    entry_fee = NOTIONAL * FEE_RATE
    quantity = (NOTIONAL - entry_fee) / entry_fill
    stop = entry_market * (1 - STOP_PCT / 100)
    target = entry_market * (1 + TARGET_PCT / 100)
    highest = entry_market
    exit_market = float(frame.iloc[min(entry_index + MAX_HOLD_BARS, len(frame) - 1)].close)
    exit_reason = "MAX_HOLD"
    exit_index = min(entry_index + MAX_HOLD_BARS, len(frame) - 1)
    for index in range(entry_index + 1, min(entry_index + MAX_HOLD_BARS + 1, len(frame))):
        row = frame.iloc[index]
        highest = max(highest, float(row.high))
        if row.low <= stop:
            exit_market, exit_reason, exit_index = stop, "STOP_LOSS", index
            break
        if row.high >= target:
            exit_market, exit_reason, exit_index = target, "PROFIT_TARGET", index
            break
        high_gain = (highest / entry_market - 1) * 100
        trail = highest * (1 - TRAIL_DISTANCE_PCT / 100)
        if high_gain >= TRAIL_ACTIVATION_PCT and row.low <= trail:
            exit_market, exit_reason, exit_index = trail, "TRAILING_STOP", index
            break
    exit_fill = exit_market * (1 - SLIPPAGE_RATE)
    exit_value = quantity * exit_fill
    exit_fee = exit_value * FEE_RATE
    net_pnl = exit_value - exit_fee - NOTIONAL
    return {
        "exit_index": exit_index,
        "exit_at": frame.iloc[exit_index].decision_at.isoformat(),
        "entry_market": entry_market,
        "exit_market": exit_market,
        "net_pnl": net_pnl,
        "return_pct": net_pnl / NOTIONAL * 100,
        "exit_reason": exit_reason,
    }


def benchmark_return(frame, start_at, end_at):
    window = frame[(frame.decision_at >= start_at) & (frame.decision_at <= end_at)]
    if len(window) < 2:
        return None
    return float((window.close.iloc[-1] / window.close.iloc[0] - 1) * 100)


def walk_forward_windows(frames, folds=WALK_FORWARD_FOLDS):
    start = max(frame.decision_at.min() for frame in frames.values())
    end = min(frame.decision_at.max() for frame in frames.values())
    span = end - start
    # Expanding training window followed by strictly unseen test windows.
    train_fraction = 0.40
    train_end = start + span * train_fraction
    remaining = end - train_end
    test_span = remaining / folds
    windows = []
    for fold in range(1, folds + 1):
        test_start = train_end + test_span * (fold - 1)
        test_end = train_end + test_span * fold
        windows.append((fold, start, test_start, test_start, test_end))
    return windows


def simulate(product, frame, params, start_at=None, end_at=None):
    qualifying = entry_mask(frame, params)
    allowed = pd.Series(True, index=frame.index)
    if start_at is not None:
        allowed &= frame.decision_at >= start_at
    if end_at is not None:
        allowed &= frame.decision_at < end_at
    qualifying &= allowed
    trades = []
    confirmations = 0
    index = 1
    while index < len(frame) - 1:
        confirmations = confirmations + 1 if qualifying.iloc[index] else 0
        if confirmations < params["confirmation_scans"]:
            index += 1
            continue
        result = close_trade(frame, index)
        trades.append(
            {
                "product": product,
                "entry_at": frame.iloc[index].decision_at.isoformat(),
                "entry_score": float(frame.iloc[index].score),
                "entry_volume": float(frame.iloc[index].rel_volume),
                "trend_4h": int(bool(frame.iloc[index].trend_4h)),
                **result,
            }
        )
        confirmations = 0
        index = result["exit_index"] + 1
    return trades


def metrics(trades):
    if not trades:
        return {
            "trades": 0, "wins": 0, "win_rate": 0.0, "net_pnl": 0.0,
            "expectancy": 0.0, "profit_factor": 0.0, "max_drawdown": 0.0,
        }
    pnl = pd.Series([trade["net_pnl"] for trade in trades], dtype=float)
    equity = pnl.cumsum()
    drawdown = equity - equity.cummax().clip(lower=0)
    gains = pnl[pnl > 0].sum()
    losses = abs(pnl[pnl <= 0].sum())
    return {
        "trades": len(trades),
        "wins": int((pnl > 0).sum()),
        "win_rate": float((pnl > 0).mean() * 100),
        "net_pnl": float(pnl.sum()),
        "expectancy": float(pnl.mean()),
        "profit_factor": float(gains / losses) if losses else 0.0,
        "max_drawdown": float(drawdown.min()),
    }


def parameter_grid():
    for score, volume, confirmations, require_4h, mode in itertools.product(
        [75.0, 80.0, 82.0],
        [1.25, 1.50],
        [1, 2, 3],
        [False, True],
        ["BREAKOUT", "RETEST"],
    ):
        yield {
            "min_score": score,
            "min_volume": volume,
            "confirmation_scans": confirmations,
            "require_4h": require_4h,
            "entry_mode": mode,
        }


def init_db(path):
    conn = sqlite3.connect(path)
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS runs(
            run_id TEXT PRIMARY KEY, created_at TEXT, days INTEGER,
            products INTEGER, parameter_sets INTEGER, note TEXT
        );
        CREATE TABLE IF NOT EXISTS results(
            run_id TEXT, parameter_id INTEGER, segment TEXT,
            min_score REAL, min_volume REAL, confirmation_scans INTEGER,
            require_4h INTEGER, entry_mode TEXT, trades INTEGER, wins INTEGER,
            win_rate REAL, net_pnl REAL, expectancy REAL, profit_factor REAL,
            max_drawdown REAL
        );
        CREATE TABLE IF NOT EXISTS walk_forward_results(
            run_id TEXT, fold INTEGER, parameter_id INTEGER, segment TEXT,
            start_at TEXT, end_at TEXT, trades INTEGER, win_rate REAL,
            net_pnl REAL, expectancy REAL, profit_factor REAL, max_drawdown REAL,
            btc_buy_hold_pct REAL, eth_buy_hold_pct REAL, basket_buy_hold_pct REAL
        );
        CREATE TABLE IF NOT EXISTS trades(
            run_id TEXT, parameter_id INTEGER, segment TEXT, product TEXT,
            entry_at TEXT, exit_at TEXT, entry_score REAL, entry_volume REAL,
            trend_4h INTEGER, entry_market REAL, exit_market REAL,
            net_pnl REAL, return_pct REAL, exit_reason TEXT
        );
        """
    )
    return conn


def run_walk_forward(conn, run_id, frames, parameter_sets):
    conn.execute("DELETE FROM walk_forward_results")
    windows = walk_forward_windows(frames)
    for fold, train_start, train_end, test_start, test_end in windows:
        train_scores = []
        for parameter_id, params in enumerate(parameter_sets, start=1):
            train_trades = []
            for product, frame in frames.items():
                train_trades.extend(simulate(product, frame, params, train_start, train_end))
            train_scores.append((metrics(train_trades)["expectancy"], parameter_id, params))
        _, parameter_id, chosen = max(train_scores, key=lambda row: row[0])
        test_trades = []
        for product, frame in frames.items():
            test_trades.extend(simulate(product, frame, chosen, test_start, test_end))
        result = metrics(test_trades)
        btc = benchmark_return(frames["BTC-USD"], test_start, test_end) if "BTC-USD" in frames else None
        eth = benchmark_return(frames["ETH-USD"], test_start, test_end) if "ETH-USD" in frames else None
        basket_values = [benchmark_return(frame, test_start, test_end) for frame in frames.values()]
        basket_values = [value for value in basket_values if value is not None]
        basket = float(np.mean(basket_values)) if basket_values else None
        conn.execute(
            """INSERT INTO walk_forward_results VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (run_id, fold, parameter_id, "TEST", test_start.isoformat(), test_end.isoformat(),
             result["trades"], result["win_rate"], result["net_pnl"], result["expectancy"],
             result["profit_factor"], result["max_drawdown"], btc, eth, basket),
        )
        print(f"Walk-forward fold {fold}: parameter {parameter_id}, trades={result['trades']}, expectancy={result['expectancy']:.3f}")


def run_backtest(days, products, db_path):
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    frames = {}
    for product in products:
        print(f"Downloading {days} days of {product}")
        frames[product] = build_features(fetch_candles(product, days))
    split_time = min(frame.decision_at.min() for frame in frames.values()) + (
        max(frame.decision_at.max() for frame in frames.values())
        - min(frame.decision_at.min() for frame in frames.values())
    ) * 0.70
    parameter_sets = list(parameter_grid())
    conn = init_db(db_path)
    conn.execute("DELETE FROM results")
    conn.execute("DELETE FROM trades")
    run_walk_forward(conn, run_id, frames, parameter_sets)
    for parameter_id, params in enumerate(parameter_sets, start=1):
        all_trades = []
        for product, frame in frames.items():
            all_trades.extend(simulate(product, frame, params))
        for trade in all_trades:
            trade["segment"] = (
                "TRAIN" if pd.Timestamp(trade["entry_at"]) < split_time else "TEST"
            )
        for segment in ["TRAIN", "TEST", "ALL"]:
            selected = (
                all_trades if segment == "ALL"
                else [trade for trade in all_trades if trade["segment"] == segment]
            )
            result = metrics(selected)
            conn.execute(
                """INSERT INTO results VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (
                    run_id, parameter_id, segment, params["min_score"],
                    params["min_volume"], params["confirmation_scans"],
                    int(params["require_4h"]), params["entry_mode"],
                    result["trades"], result["wins"], result["win_rate"],
                    result["net_pnl"], result["expectancy"], result["profit_factor"],
                    result["max_drawdown"],
                ),
            )
            for trade in selected if segment != "ALL" else []:
                conn.execute(
                    """INSERT INTO trades VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                    (
                        run_id, parameter_id, segment, trade["product"],
                        trade["entry_at"], trade["exit_at"], trade["entry_score"],
                        trade["entry_volume"], trade["trend_4h"],
                        trade["entry_market"], trade["exit_market"], trade["net_pnl"],
                        trade["return_pct"], trade["exit_reason"],
                    ),
                )
        if parameter_id % 8 == 0:
            print(f"Evaluated {parameter_id}/{len(parameter_sets)} parameter sets")
            conn.commit()
    conn.execute(
        "INSERT OR REPLACE INTO runs VALUES(?,?,?,?,?,?)",
        (
            run_id, datetime.now(timezone.utc).isoformat(), days, len(products),
            len(parameter_sets),
            "Research only. Parameters are never promoted automatically.",
        ),
    )
    conn.commit()
    conn.close()
    print(f"Backtest complete: {run_id}")


def self_test():
    periods = 900
    time_index = pd.date_range("2026-01-01", periods=periods, freq="15min", tz="UTC")
    base = 100 + np.linspace(0, 35, periods) + np.sin(np.arange(periods) / 9)
    volume = np.full(periods, 100.0)
    volume[::12] = 350
    raw = pd.DataFrame(
        {
            "time": time_index, "open": base - .1, "high": base + .35,
            "low": base - .35, "close": base, "volume": volume,
        }
    )
    frame = build_features(raw)
    assert {"score", "trend_4h", "breakout", "retest"}.issubset(frame.columns)
    params = next(parameter_grid())
    result = simulate("TEST-USD", frame, params)
    assert isinstance(result, list)
    assert len(list(parameter_grid())) == 72
    windows = walk_forward_windows({"TEST": frame}, folds=3)
    assert len(windows) == 3
    assert all(test_start >= train_end for _, _, train_end, test_start, _ in windows)
    print("research_backtest self-test passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=60)
    parser.add_argument("--db", default=DB)
    parser.add_argument("--products", nargs="*", default=PRODUCTS)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    else:
        run_backtest(args.days, args.products, args.db)
