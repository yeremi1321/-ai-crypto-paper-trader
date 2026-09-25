"""Fast PAPER-only watcher: polls Coinbase level-1 quotes every ~2 seconds.

The slow strategy still supplies context. This loop only detects live acceleration/breakout
and emits candidates; it never sends real orders.
"""
import argparse, json, time
from collections import deque
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from two_second_confirmation import top_of_book

PRODUCTS=["BTC-USD","ETH-USD","SOL-USD","DOGE-USD","SHIB-USD","AVAX-USD","LINK-USD","ADA-USD","XRP-USD","LTC-USD","BCH-USD"]
POLL_SECONDS=2.0
WINDOW_SECONDS=20
MIN_ACCEL_PCT=0.12
MAX_SPREAD_BPS=10.0

class LiveDetector:
    def __init__(self, window_seconds=WINDOW_SECONDS):
        self.window_seconds=window_seconds
        self.history={}

    def observe(self, product, quote, now=None):
        now=time.time() if now is None else now
        h=self.history.setdefault(product,deque())
        h.append((now,quote["mid"]))
        cutoff=now-self.window_seconds
        while h and h[0][0] < cutoff: h.popleft()
        baseline=min(p for _,p in h)
        accel_pct=(quote["mid"]/baseline-1)*100 if baseline else 0.0
        prior_high=max((p for _,p in list(h)[:-1]),default=quote["mid"])
        breakout=quote["mid"] >= prior_high
        candidate=(len(h)>=2 and accel_pct>=MIN_ACCEL_PCT and breakout
                   and quote["spread_bps"]<MAX_SPREAD_BPS)
        return candidate,{"accel_pct":accel_pct,"baseline":baseline,
                          "prior_high":prior_high,"spread_bps":quote["spread_bps"]}

def run(products=PRODUCTS, interval=POLL_SECONDS):
    detector=LiveDetector()
    with ThreadPoolExecutor(max_workers=len(products)) as pool:
        while True:
            started=time.monotonic()
            results={pool.submit(top_of_book, product): product for product in products}
            successful=[]; errors=[]
            for future in as_completed(results):
                product=results[future]
                try:
                    q=future.result()
                    successful.append(product)
                    ok,detail=detector.observe(product,q)
                    if ok:
                        print(json.dumps({"ts":datetime.now(timezone.utc).isoformat(),
                            "mode":"PAPER_CANDIDATE","product":product,"quote":q,"detail":detail}),flush=True)
                except Exception as e:
                    errors.append(product)
                    print(json.dumps({"mode":"DATA_ERROR","product":product,"error":type(e).__name__}),flush=True)
            elapsed=time.monotonic()-started
            print(json.dumps({"ts":datetime.now(timezone.utc).isoformat(),
                "mode":"PAPER_POLL","products":len(products),"successful":len(successful),
                "errors":errors,"cycle_seconds":round(elapsed,3),
                "products_seen":sorted(successful)}),flush=True)
            time.sleep(max(0.0,interval-elapsed))

if __name__=="__main__":
    p=argparse.ArgumentParser(); p.add_argument("--interval",type=float,default=POLL_SECONDS)
    args=p.parse_args(); run(interval=max(2.0,args.interval))
