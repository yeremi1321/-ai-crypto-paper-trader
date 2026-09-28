# V5 paper strategy research status — September 27, 2026 UTC

New paper portfolio entries are paused. Scans, momentum states, blocked setup
outcomes, and early shadow outcomes continue. Existing open paper positions, if
any, still follow their exit rules. No real-money execution is enabled.

## Recorded evidence

| Source | Sample | Result |
| --- | ---: | ---: |
| V5 closed paper trades | 1 | 0 wins; -$1.25 net |
| V6 early closed paper trades | 7 | 0 wins; -$12.84 net |
| V5 + V6 early | 8 | 0 wins; -$14.09 net |
| Offline 60-day backtest, held-out 30% segment | 48 parameter sets | 0 positive-expectancy sets; best -$0.33/trade |

The paper ledger uses $100 per trade, 0.6% fee and 0.1% slippage on each
side. Across the eight recent trades, simulated fees total about $9.54 and
gross P/L after slippage is about -$4.54. All seven early entries lost. Most
closed when momentum weakened or failed before reaching the profit target.
The offline backtest tests V5-style confirmation, trend and breakout/retest
variants; it does not validate the V6 early branch. Its held-out results are
negative even for the best parameter set, so selecting the best in hindsight
is not evidence of an edge.

## Research gate for resuming paper entries

1. Keep recording early and confirmed candidate outcomes with the same fees,
   slippage, and exit assumptions as portfolio paper trades.
2. Run fresh, chronologically separated tests with enough independent trades
   to estimate net expectancy and drawdown. Do not tune on the held-out window.
3. Review whether the exact candidate rule has positive net expectancy in
   more than one unseen market period, including weak or choppy conditions.
4. Resume a small paper-only cohort by changing `PAPER_ENTRY_ENABLED` only
   after documenting the rule and its unseen results. Treat subsequent paper
   trades as prospective validation, not proof of future profit.

This pause does not erase the ledger or rewrite simulated fees to make the
strategy appear profitable. The scanner fails its scheduled run when every
product fails, so a green workflow now means at least one product was scanned.

## Separate memecoin paper cohort

The memecoin ledger currently has 70 closed simulated trades, 23 wins, and
-$1,289.42 net P/L. The scheduled memecoin discovery workflow now marks
otherwise eligible candidates `RESEARCH_PAUSE` and continues recording their
forward outcomes; it opens no new simulated positions. Existing position
monitoring and exits remain active. This cohort has different prices, liquidity,
slippage, and exit rules from V5 and must be validated separately.
