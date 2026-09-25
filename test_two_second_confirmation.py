import unittest
from unittest.mock import Mock
from two_second_confirmation import confirm_two_seconds

class Response:
    def __init__(self,bid,ask): self.bid=bid; self.ask=ask
    def raise_for_status(self): pass
    def json(self): return {"bids":[[str(self.bid),"1"]],"asks":[[str(self.ask),"1"]]}

def setup():
    return dict(market_regime="risk_on",vwap=99,ema20=101,ema50=98,close=102,
        previous_highest_high_20=100,relative_volume=2.0,no_event_risk=True)

class TestTwoSecondConfirmation(unittest.TestCase):
    def test_holds_for_two_seconds(self):
        session=Mock(); session.get.side_effect=[Response(101,101.05),Response(101.1,101.15)]
        ok,detail=confirm_two_seconds("BTC-USD",setup(),sleep=lambda _:None,session=session)
        self.assertTrue(ok); self.assertTrue(detail["held_breakout"])

    def test_rejects_fast_reversal(self):
        session=Mock(); session.get.side_effect=[Response(101,101.05),Response(99.8,99.85)]
        ok,_=confirm_two_seconds("BTC-USD",setup(),sleep=lambda _:None,session=session)
        self.assertFalse(ok)

if __name__=="__main__": unittest.main()
