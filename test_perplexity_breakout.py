import unittest
from perplexity_breakout import entry_signal, exit_levels, exit_decision

class TestPerplexityBreakout(unittest.TestCase):
    def test_report_entry_template(self):
        ok, checks = entry_signal(market_regime="risk_on", price=101, vwap=100,
            ema20=102, ema50=99, close=105, previous_highest_high_20=104,
            relative_volume=1.81, spread_bps=9, no_event_risk=True)
        self.assertTrue(ok)
        self.assertTrue(all(checks.values()))

    def test_entry_veto(self):
        ok, _ = entry_signal(market_regime="risk_on", price=101, vwap=100,
            ema20=102, ema50=99, close=105, previous_highest_high_20=104,
            relative_volume=1.79, spread_bps=9, no_event_risk=True)
        self.assertFalse(ok)

    def test_report_exit_levels(self):
        levels = exit_levels(100, 2, 110)
        self.assertAlmostEqual(levels["initial_stop"], 97.6)
        self.assertAlmostEqual(levels["target_1"], 103.6)
        self.assertAlmostEqual(levels["trailing_stop"], 106.0)

    def test_breakout_failure_exit(self):
        action = exit_decision(price=101, close=99, initial_stop=95, target_1=105,
            scaled_out=False, vwap=100, reached_target_1=False, breakout_level=100,
            bars_since_entry=2, max_holding_bars=10, return_pct=1,
            minimum_expected_return=2)
        self.assertEqual(action, "EXIT_REMAINDER_BREAKOUT_FAILURE")

if __name__ == "__main__":
    unittest.main()
