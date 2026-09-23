# AI Crypto Paper Trader V5

V5 keeps the V4 scanner/dashboard architecture and starts a clean, versioned
paper test without deleting the original 22-trade baseline.

## What changes
- GitHub Actions runs `scanner.py` roughly every 15 minutes.
- Each run uses completed Coinbase 15m/1h candles.
- Results are stored in `paper_trader_v4.db` and committed back to the repository.
- Streamlit displays the accumulated history.
- The live control center shows scanner freshness, market-regime status, open
  positions, paper P/L, score changes, recent decisions, and direct TradingView
  links for every tracked coin.
- Forward research tracks 1h, 4h, and 24h returns after recorded scores.
- A separate shadow evaluator records 4-hour trend alignment, market regime,
  and pullback/retest readiness without changing V5 trade decisions.
- A separate historical backtester tests 48 parameter combinations over 60
  days by default, ranks them on an unseen 30% test period, and never promotes
  settings into the live scanner automatically.
- New paper entries require BTC and at least 60% of fresh tracked markets to be
  above both their 15-minute EMA20 and 1-hour EMA20 trend filters.
- V5 raises that market breadth requirement to 70% and only enters after two
  consecutive high-quality SIGNAL scans: score 80+, relative volume 1.50x+,
  RSI 55–68, 15-minute and 1-hour trend alignment, a 20-bar breakout, and
  continued price/score strength.
- V5 uses a 3% hard stop, 4% target, a 1% trailing stop after a 2% gain,
  loss/profit-aware weakening exits, a 2-hour re-entry cooldown, and a $15
  daily realized-loss cutoff.
- V4 trades remain visible as the baseline; V5 win rate, P/L, expectancy, and
  drawdown are reported separately.
- Real-money trading is not included.

## Install
Upload/replace these items in the SAME GitHub repository:
- `app.py`
- `scanner.py`
- `requirements.txt`
- `.github/workflows/scanner.yml`
- `.github/workflows/research.yml`
- `shadow_research.py`
- `research_backtest.py`

Then open GitHub → Actions → Automatic crypto research scan → Run workflow once.
After that first successful run, Streamlit will redeploy when the database commit lands.

The shadow evaluator runs after each normal scan. The offline backtest can be
started from GitHub Actions → V5 Offline Research Lab → Run workflow and also
runs weekly. Research output is stored separately in `research_shadow.db` and
`research_backtest.db`.

## Important
GitHub scheduled workflows can be delayed and can be disabled after long inactivity on public repositories.
This is a research collector, not an execution engine or guaranteed real-time alerting service.
