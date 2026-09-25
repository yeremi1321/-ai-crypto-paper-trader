"""Two-second paper confirmation for Perplexity breakout candidates."""
import time
import requests
from perplexity_breakout import entry_signal

COINBASE = "https://api.exchange.coinbase.com"

def top_of_book(product, session=requests):
    r=session.get(f"{COINBASE}/products/{product}/book",params={"level":1},timeout=5,
                  headers={"User-Agent":"paper-two-second-confirm"})
    r.raise_for_status()
    d=r.json()
    bid=float(d["bids"][0][0]); ask=float(d["asks"][0][0]); mid=(bid+ask)/2
    return {"bid":bid,"ask":ask,"mid":mid,"spread_bps":((ask-bid)/mid)*10000}

def confirm_two_seconds(product, setup, sleep=time.sleep, session=requests):
    """Require the setup to survive a second live quote two seconds later."""
    first=top_of_book(product,session)
    sleep(2.0)
    second=top_of_book(product,session)
    common=dict(
        market_regime=setup["market_regime"], vwap=setup["vwap"],
        ema20=setup["ema20"], ema50=setup["ema50"], close=setup["close"],
        previous_highest_high_20=setup["previous_highest_high_20"],
        relative_volume=setup["relative_volume"], no_event_risk=setup["no_event_risk"],
        liquidity_ok=setup.get("liquidity_ok",True),
        volatility_ok=setup.get("volatility_ok",True), data_ok=setup.get("data_ok",True),
    )
    first_ok,_=entry_signal(price=first["mid"],spread_bps=first["spread_bps"],**common)
    second_ok,checks=entry_signal(price=second["mid"],spread_bps=second["spread_bps"],**common)
    held_breakout=second["mid"] > setup["previous_highest_high_20"]
    did_not_reverse=second["mid"] >= first["mid"] * 0.999
    passed=first_ok and second_ok and held_breakout and did_not_reverse
    return passed, {"first":first,"second":second,"checks":checks,
                    "held_breakout":held_breakout,"did_not_reverse":did_not_reverse}
