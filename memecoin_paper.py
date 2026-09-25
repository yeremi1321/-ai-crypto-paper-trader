"""Deterministic memecoin paper execution engine. No real orders are placed."""
import argparse, sqlite3
from datetime import datetime, timezone
from memecoin_shadow import init_db, PAPER_FEE_RATE, PAPER_SLIPPAGE_RATE

DB="memecoin_shadow.db"; VERSION="MEME_PAPER_V1"
TP_PCT=20.0; SL_PCT=-10.0; MAX_HOLD_MIN=20.0; MAX_OPEN=5

def pct(a,b): return ((b/a)-1)*100 if a else 0.0

def migrate(c):
 cols={r[1] for r in c.execute("PRAGMA table_info(meme_paper_trades)")}
 additions={"closed_at":"TEXT","exit_market_price":"REAL","exit_price":"REAL","exit_fee":"REAL",
 "net_pnl_usd":"REAL","net_return_pct":"REAL","exit_reason":"TEXT","strategy_version":"TEXT"}
 for name,typ in additions.items():
  if name not in cols: c.execute(f"ALTER TABLE meme_paper_trades ADD COLUMN {name} {typ}")
 c.commit()

def close_positions(c, now=None):
 now=now or datetime.now(timezone.utc); closed=[]
 rows=c.execute("""SELECT id,candidate_id,token,entry_price,quantity,entry_fee,opened_at,current_price,
 highest_price,lowest_price FROM meme_paper_trades WHERE status='OPEN' ORDER BY id""").fetchall()
 for i,cid,token,entry,qty,entry_fee,opened,current,hi,lo in rows:
  if not current or not entry: continue
  ret=pct(entry,current); age=(now-datetime.fromisoformat(opened)).total_seconds()/60
  reason=None
  if ret<=SL_PCT: reason="STOP_10"
  elif ret>=TP_PCT: reason="TARGET_20"
  elif age>=MAX_HOLD_MIN: reason="TIME_20"
  if not reason: continue
  # Conservative simulated exit: adverse 1% slippage plus 0.6% exit fee.
  exit_market=float(current); exit_price=exit_market*(1-PAPER_SLIPPAGE_RATE)
  gross=float(qty)*exit_price; exit_fee=gross*PAPER_FEE_RATE
  proceeds=gross-exit_fee; net_pnl=proceeds-(float(qty)*float(entry)+float(entry_fee))
  invested=float(qty)*float(entry)+float(entry_fee)
  net_ret=100*net_pnl/invested if invested else 0
  c.execute("""UPDATE meme_paper_trades SET status='CLOSED',closed_at=?,exit_market_price=?,exit_price=?,
   exit_fee=?,net_pnl_usd=?,net_return_pct=?,exit_reason=?,strategy_version=? WHERE id=?""",
   (now.isoformat(),exit_market,exit_price,exit_fee,net_pnl,net_ret,reason,VERSION,i))
  label="WIN" if net_pnl>0 else "LOSS"
  c.execute("""UPDATE meme_decision_ledger SET outcome_label=?,net_return_pct=?,mfe_pct=?,mae_pct=?,
   time_in_trade_minutes=? WHERE candidate_id=?""",(label,net_ret,pct(entry,hi),pct(entry,lo),age,cid))
  closed.append((token,reason,round(net_ret,2)))
 c.commit(); return closed

def summary(c):
 open_n=c.execute("SELECT COUNT(*) FROM meme_paper_trades WHERE status='OPEN'").fetchone()[0]
 closed=c.execute("SELECT COUNT(*) FROM meme_paper_trades WHERE status='CLOSED'").fetchone()[0]
 wins=c.execute("SELECT COUNT(*) FROM meme_paper_trades WHERE status='CLOSED' AND net_pnl_usd>0").fetchone()[0]
 pnl=c.execute("SELECT COALESCE(SUM(net_pnl_usd),0) FROM meme_paper_trades WHERE status='CLOSED'").fetchone()[0]
 print({"version":VERSION,"open":open_n,"closed":closed,"wins":wins,"losses":closed-wins,"realized_pnl_usd":round(pnl,2)})

def run(path=DB):
 c=init_db(path); migrate(c)
 closed=close_positions(c)
 for x in closed: print({"meme_paper_close":x})
 summary(c); c.close()

def self_test():
 c=init_db(":memory:"); migrate(c)
 now=datetime.now(timezone.utc); opened=now.replace(microsecond=0).isoformat()
 c.execute("""INSERT INTO meme_paper_trades(candidate_id,token,token_address,pair_address,opened_at,
 entry_market_price,entry_price,notional_usd,quantity,entry_fee,status,highest_price,lowest_price,
 current_price,current_return_pct,mfe_pct,mae_pct) VALUES(1,'TEST','a','p',?,1,1,100,99.4,.6,'OPEN',1.25,.95,1.25,25,25,-5)""",(opened,))
 c.execute("""INSERT INTO meme_decision_ledger(candidate_id,outcome_label) VALUES(1,'PENDING')"""); c.commit()
 out=close_positions(c,now); assert out and out[0][1]=="TARGET_20"
 assert c.execute("SELECT status FROM meme_paper_trades").fetchone()[0]=="CLOSED"
 assert c.execute("SELECT outcome_label FROM meme_decision_ledger").fetchone()[0]=="WIN"
 c.close(); print("meme paper trader self-test passed")

if __name__=="__main__":
 p=argparse.ArgumentParser(); p.add_argument("--self-test",action="store_true"); a=p.parse_args()
 self_test() if a.self_test else run()
