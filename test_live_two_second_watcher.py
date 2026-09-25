import unittest
from live_two_second_watcher import LiveDetector

class TestLiveDetector(unittest.TestCase):
    def test_detects_fast_breakout(self):
        d=LiveDetector()
        q=lambda mid: {"mid":mid,"spread_bps":2.0}
        self.assertFalse(d.observe("BTC-USD",q(100),0)[0])
        ok,x=d.observe("BTC-USD",q(100.13),2)
        self.assertTrue(ok); self.assertGreaterEqual(x["accel_pct"],0.12)
    def test_rejects_wide_spread(self):
        d=LiveDetector(); d.observe("BTC-USD",{"mid":100,"spread_bps":2},0)
        self.assertFalse(d.observe("BTC-USD",{"mid":100.2,"spread_bps":12},2)[0])
if __name__=="__main__": unittest.main()
