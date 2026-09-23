"""Update memecoin outcomes and open simulated positions from live DEX prices."""
import json
from datetime import datetime,timezone
from memecoin_shadow import init_db
from memecoin_discovery import best_pair
def pct(a,b): return ((b/a)-1)*100 if a else 0
def run():
 c=init_db(); now=datetime.now(timezone.utc); addresses={r[0] for r in c.execute("select token_address from meme_outcomes union select token_address from meme_paper_trades where status='OPEN'")}
 for a in addresses:
  try:
   pair=best_pair(a)
   if not pair or not pair.get("priceUsd"): continue
   p=float(pair["priceUsd"])
   for r in c.execute("select candidate_id,detected_at,entry_price,highest_price,lowest_price from meme_outcomes where token_address=?",(a,)).fetchall():
    cid,det,entry,hi,lo=r; hi=max(hi,p); lo=min(lo,p); age=(now-datetime.fromisoformat(det)).total_seconds()/60
    c.execute("update meme_outcomes set last_price=?,highest_price=?,lowest_price=?,mfe_pct=?,mae_pct=?,age_minutes=? where candidate_id=?",(p,hi,lo,pct(entry,hi),pct(entry,lo),age,cid))
   for r in c.execute("select id,entry_price,highest_price,lowest_price from meme_paper_trades where token_address=? and status='OPEN'",(a,)).fetchall():
    i,entry,hi,lo=r; hi=max(hi,p); lo=min(lo,p)
    c.execute("update meme_paper_trades set highest_price=?,lowest_price=?,current_price=?,current_return_pct=?,mfe_pct=?,mae_pct=? where id=?",(hi,lo,p,pct(entry,p),pct(entry,hi),pct(entry,lo),i))
   c.commit()
  except Exception as e: print(f"::warning::outcome update failed {a}: {e}")
 c.close()
if __name__=="__main__": run()
