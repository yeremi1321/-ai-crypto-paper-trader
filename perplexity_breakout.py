"""Perplexity breakout template copied as a PAPER/RESEARCH challenger.

Numeric values match the report's illustrative defaults. No real orders.
"""
from dataclasses import dataclass

@dataclass(frozen=True)
class PerplexityBreakoutConfig:
    fast_ema: int = 20
    slow_ema: int = 50
    breakout_lookback: int = 20
    relative_volume_min: float = 1.8
    spread_bps_max: float = 10.0
    atr_period: int = 14
    initial_stop_atr: float = 1.2
    target_r_multiple: float = 1.5
    scale_out_fraction: float = 0.50
    trailing_atr: float = 2.0

def entry_signal(*, market_regime, price, vwap, ema20, ema50, close,
                 previous_highest_high_20, relative_volume, spread_bps,
                 no_event_risk, liquidity_ok=True, volatility_ok=True, data_ok=True):
    checks = {
        "risk_on": market_regime == "risk_on",
        "above_vwap": price > vwap,
        "ema_alignment": ema20 > ema50,
        "breakout_20": close > previous_highest_high_20,
        "relative_volume": relative_volume > 1.8,
        "spread": spread_bps < 10,
        "no_event_risk": bool(no_event_risk),
        "liquidity": bool(liquidity_ok),
        "volatility": bool(volatility_ok),
        "data": bool(data_ok),
    }
    return all(checks.values()), checks

def exit_levels(entry, atr, highest_close):
    initial_stop = entry - 1.2 * atr
    risk = entry - initial_stop
    return {"initial_stop": initial_stop, "target_1": entry + 1.5 * risk,
            "scale_out_fraction": 0.50, "trailing_stop": highest_close - 2.0 * atr}

def exit_decision(*, price, close, initial_stop, target_1, scaled_out, vwap,
                  reached_target_1, breakout_level, bars_since_entry,
                  max_holding_bars, return_pct, minimum_expected_return,
                  momentum_failed=False):
    if price <= initial_stop: return "EXIT_ALL_INITIAL_STOP"
    if price >= target_1 and not scaled_out: return "SCALE_OUT_50"
    if momentum_failed: return "EXIT_REMAINDER_MOMENTUM_FAILURE"
    if reached_target_1 and close < vwap: return "EXIT_REMAINDER_VWAP_LOSS"
    if close < breakout_level: return "EXIT_REMAINDER_BREAKOUT_FAILURE"
    if bars_since_entry >= max_holding_bars and return_pct < minimum_expected_return:
        return "EXIT_REMAINDER_TIME_STOP"
    return "HOLD"
