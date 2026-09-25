import unittest
from unittest.mock import patch
import pandas as pd
import scanner

class DummyResponse:
    def raise_for_status(self): pass
    def json(self): return {"bids":[["100","1"]],"asks":[["100.05","1"]]}

class TestScannerPerplexity(unittest.TestCase):
    @patch("scanner.db")
    @patch("scanner.market_regime", return_value=(True,"ok",True,1.0))
    @patch("scanner.requests.get", return_value=DummyResponse())
    @patch("scanner.candles")
    def test_candidate_uses_copied_gate(self, candles, *_):
        n=60
        close=[100.0]*59+[102.0]
        high=[100.5]*59+[102.2]
        low=[99.5]*59+[101.0]
        volume=[100.0]*59+[300.0]
        candles.return_value=pd.DataFrame({"time":range(n),"low":low,"high":high,"open":close,"close":close,"volume":volume})
        ok, checks, levels, spread, detail=scanner.perplexity_candidate("BTC-USD")
        self.assertTrue(checks["breakout_20"])
        self.assertTrue(checks["relative_volume"])
        self.assertTrue(checks["spread"])
        self.assertLess(spread,10)
        self.assertIn("initial_stop",levels)

if __name__=="__main__":
    unittest.main()
