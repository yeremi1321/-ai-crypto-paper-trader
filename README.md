# AI Crypto Paper Trader V1

A phone-friendly Streamlit prototype for testing the strategy discussed in ChatGPT.

## Safety
- Paper trading only.
- No API keys.
- No real orders.
- Starting balance: $500.
- Planned risk: $5 per trade.
- Daily realized-loss cutoff: $15.
- No leverage or averaging down.

## Run
1. Install Python 3.11+.
2. In this folder:
   `pip install -r requirements.txt`
3. Start:
   `streamlit run app.py`
4. Open the local URL shown by Streamlit.

For phone access, deploy this folder to a Streamlit-compatible host or another Python web host.

## V1 scoring
Uses 15-minute and 1-hour public candles. It scores momentum, relative volume,
market structure and a basic liquidity/volatility proxy. AI/news sentiment is intentionally
not included in the score until we can test whether it adds predictive value.

## Important limitation
The current version checks exits when the scanner is run. A later hosted version should run
a scheduled background scanner and use a proper real-time market-data feed. Fees/slippage,
more robust liquidity/order-book checks, backtesting, alerts, and the Perplexity research
layer should be added before any live-trading consideration.
