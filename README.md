# AI Crypto Paper Trader V4

V4 separates scanning from the Streamlit dashboard.

## What changes
- GitHub Actions runs `scanner.py` roughly every 15 minutes.
- Each run uses completed Coinbase 15m/1h candles.
- Results are stored in `paper_trader_v4.db` and committed back to the repository.
- Streamlit displays the accumulated history.
- Forward research tracks 1h, 4h, and 24h returns after recorded scores.
- New paper entries require BTC and at least 60% of fresh tracked markets to be
  above both their 15-minute EMA20 and 1-hour EMA20 trend filters.
- Real-money trading is not included.

## Install
Upload/replace these items in the SAME GitHub repository:
- `app.py`
- `scanner.py`
- `requirements.txt`
- `.github/workflows/scanner.yml`

Then open GitHub → Actions → Automatic crypto research scan → Run workflow once.
After that first successful run, Streamlit will redeploy when the database commit lands.

## Important
GitHub scheduled workflows can be delayed and can be disabled after long inactivity on public repositories.
This is a research collector, not an execution engine or guaranteed real-time alerting service.
