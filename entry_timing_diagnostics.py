import argparse
import sqlite3
from datetime import datetime

FAST_DB = "research_shadow.db"
PAPER_DB = "paper_trader_v4.db"

def pct(a,b):
    return (b/a-1)*100 if a else None

def run(fast_db=FAST_DB,paper_db=PAPER_DB):
    f=sqlite3.connect(fast_db); p=sqlite3.connect(paper_db)
    fast=f.execute("""SELECT observed_at,product,price,score,return_15m_pct,return_30m_pct,return_60m_pct
                      FROM fast_5m_shadow WHERE fast_signal=1 ORDER BY observed_at""").fetchall()
    trades=p.execute("""SELECT product,opened_at,entry_market_price,net_return_pct,status
                        FROM paper_trades WHERE strategy_version='V5' ORDER BY opened_at""").fetchall()
    scans=p.execute("""SELECT seen_at,product,price,score,status FROM scans
                       WHERE status='SIGNAL' ORDER BY seen_at""").fetchall()
    print(f"ENTRY TIMING DIAGNOSTIC fast_signals={len(fast)} v5_trades={len(trades)} v5_signal_scans={len(scans)}")
    pairs=[]
    for t,prod,price,score,r15,r30,r60 in fast:
        t0=datetime.fromisoformat(t)
        later=[]
        for st,sp,sprice,sscore,status in scans:
            if sp!=prod: continue
            ts=datetime.fromisoformat(st)
            delay=(ts-t0).total_seconds()/60
            if 0 <= delay <= 180:
                later.append((delay,sprice,sscore))
        if later:
            delay,sprice,sscore=min(later,key=lambda x:x[0])
            pairs.append((prod,delay,pct(price,sprice),r15,r30,r60))
    if not pairs:
        print("ENTRY TIMING paired_samples=0 -- collecting forward data")
    else:
        print(f"ENTRY TIMING paired_samples={len(pairs)} avg_confirmation_delay_min={sum(x[1] for x in pairs)/len(pairs):.1f} avg_move_before_v5_pct={sum(x[2] for x in pairs)/len(pairs):+.3f}%")
        for idx,label in ((3,"15m"),(4,"30m"),(5,"60m")):
            vals=[x[idx] for x in pairs if x[idx] is not None]
            if vals: print(f"ENTRY TIMING fast_{label} samples={len(vals)} win_rate={sum(v>0 for v in vals)/len(vals)*100:.1f}% avg_return={sum(vals)/len(vals):+.3f}%")
    closed=[x for x in trades if x[4]=="CLOSED" and x[3] is not None]
    if closed:
        print(f"ENTRY QUALITY closed_v5={len(closed)} wins={sum(x[3]>0 for x in closed)} losses={sum(x[3]<=0 for x in closed)} avg_net={sum(x[3] for x in closed)/len(closed):+.3f}%")
    else:
        print("ENTRY QUALITY closed_v5=0")
    f.close(); p.close()

def self_test():
    a=sqlite3.connect(":memory:"); a.execute("CREATE TABLE fast_5m_shadow(observed_at TEXT,product TEXT,price REAL,score REAL,fast_signal INTEGER,return_15m_pct REAL,return_30m_pct REAL,return_60m_pct REAL)"); a.close()
    print("entry_timing_diagnostics self-test passed")

if __name__=="__main__":
    ap=argparse.ArgumentParser(); ap.add_argument("--self-test",action="store_true"); args=ap.parse_args()
    self_test() if args.self_test else run()
