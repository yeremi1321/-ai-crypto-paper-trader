"""Update memecoin outcomes, snapshots, and open simulated positions from live DEX prices.

Research-only. No orders are placed.
"""
import time
from datetime import datetime, timezone
from memecoin_shadow import init_db
from memecoin_discovery import best_pair

REQUEST_DELAY_SECONDS = 0.35

def pct(a,b): return ((b/a)-1)*100 if a else 0

def ensure_snapshot_table(c):
    c.execute("""CREATE TABLE IF NOT EXISTS meme_price_snapshots(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      observed_at TEXT NOT NULL,
      token_address TEXT NOT NULL,
      pair_address TEXT,
      price REAL NOT NULL,
      liquidity_usd REAL,
      volume_1h_usd REAL
    )""")
    c.execute("""CREATE INDEX IF NOT EXISTS meme_snapshots_token_time
                 ON meme_price_snapshots(token_address, observed_at)""")
    c.commit()

def run():
 c=init_db(); ensure_snapshot_table(c); now=datetime.now(timezone.utc)
 addresses={r[0] for r in c.execute("select token_address from meme_outcomes union select token_address from meme_paper_trades where status='OPEN'")}
 updated=0; failed=0
 for a in addresses:
  try:
   pair=best_pair(a)
   if not pair or not pair.get("priceUsd"): continue
   p=float(pair["priceUsd"])
   liq=float((pair.get("liquidity") or {}).get("usd") or 0)
   vol=float((pair.get("volume") or {}).get("h1") or 0)
   c.execute("""INSERT INTO meme_price_snapshots(
      observed_at,token_address,pair_address,price,liquidity_usd,volume_1h_usd
    ) VALUES(?,?,?,?,?,?)""",(now.isoformat(),a,pair.get("pairAddress"),p,liq,vol))
   for r in c.execute("select candidate_id,detected_at,entry_price,highest_price,lowest_price from meme_outcomes where token_address=?",(a,)).fetchall():
    cid,det,entry,hi,lo=r; hi=max(hi,p); lo=min(lo,p); age=(now-datetime.fromisoformat(det)).total_seconds()/60
    c.execute("update meme_outcomes set last_price=?,highest_price=?,lowest_price=?,mfe_pct=?,mae_pct=?,age_minutes=? where candidate_id=?",(p,hi,lo,pct(entry,hi),pct(entry,lo),age,cid))
   for r in c.execute("select id,entry_price,highest_price,lowest_price from meme_paper_trades where token_address=? and status='OPEN'",(a,)).fetchall():
    i,entry,hi,lo=r; hi=max(hi,p); lo=min(lo,p)
    c.execute("update meme_paper_trades set highest_price=?,lowest_price=?,current_price=?,current_return_pct=?,mfe_pct=?,mae_pct=? where id=?",(hi,lo,p,pct(entry,p),pct(entry,hi),pct(entry,lo),i))
   c.commit(); updated+=1
  except Exception as e:
   failed+=1; print(f"::warning::outcome update failed {a}: {e}")
  time.sleep(REQUEST_DELAY_SECONDS)
 print(f"memecoin outcome updates: {updated}; failed: {failed}; snapshots recorded: {updated}")
 c.close()

if __name__=="__main__": run()
