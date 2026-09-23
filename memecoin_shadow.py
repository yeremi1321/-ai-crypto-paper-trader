"""Research-only memecoin candidate, outcome, and simulated-trade storage."""
import argparse,json,sqlite3
from datetime import datetime,timezone
DB="memecoin_shadow.db"; VERSION="MEME_SHADOW_V2"
PAPER_NOTIONAL_USD=100.0; PAPER_FEE_RATE=.006; PAPER_SLIPPAGE_RATE=.01
DEFAULTS={"min_liquidity_usd":50000.0,"min_makers":200,"max_top10_holder_pct":50.0,"max_dev_holder_pct":10.0,"min_volume_1h_usd":25000.0,"min_score":65.0}

def safety_reasons(x,cfg=DEFAULTS):
 r=[]
 if float(x.get("liquidity_usd",0))<cfg["min_liquidity_usd"]: r.append("LOW_LIQUIDITY")
 if int(x.get("makers",0))<cfg["min_makers"]: r.append("LOW_PARTICIPATION")
 if float(x.get("top10_holder_pct",100))>cfg["max_top10_holder_pct"]: r.append("HOLDER_CONCENTRATION")
 if float(x.get("dev_holder_pct",100))>cfg["max_dev_holder_pct"]: r.append("DEV_CONCENTRATION")
 if x.get("mint_authority_active",True): r.append("MINT_AUTHORITY")
 if x.get("freeze_authority_active",True): r.append("FREEZE_AUTHORITY")
 if not x.get("sellable",False): r.append("SELLABILITY")
 if not x.get("liquidity_locked",False): r.append("LIQUIDITY_CONTROL")
 return r

def score(x):
 s=min(max(float(x.get("price_change_1h_pct",0)),0),30)
 s+=min(max(float(x.get("volume_accel",0))-1,0),4)*7.5
 s+=min(max(float(x.get("holder_growth_1h_pct",0)),0),20)*.75
 s+=10 if x.get("higher_highs",False) else 0; s+=10 if x.get("narrative_momentum",False) else 0
 return round(min(s,100),2)

def evaluate(x):
 b=safety_reasons(x); s=score(x)
 return {"version":VERSION,"token":x.get("token"),"chain":x.get("chain"),"score":s,"eligible":not b and s>=DEFAULTS["min_score"],"blocked_reasons":b}

def init_db(path=DB):
 c=sqlite3.connect(path)
 c.execute("""CREATE TABLE IF NOT EXISTS meme_candidates(id INTEGER PRIMARY KEY,seen_at TEXT,version TEXT,token TEXT,chain TEXT,score REAL,eligible INTEGER,blocked_reasons TEXT,raw_json TEXT)""")
 c.execute("""CREATE TABLE IF NOT EXISTS meme_outcomes(candidate_id INTEGER PRIMARY KEY,token_address TEXT,pair_address TEXT,detected_at TEXT,entry_price REAL,last_price REAL,highest_price REAL,lowest_price REAL,mfe_pct REAL,mae_pct REAL,age_minutes REAL)""")
 c.execute("""CREATE TABLE IF NOT EXISTS meme_paper_trades(id INTEGER PRIMARY KEY,candidate_id INTEGER UNIQUE,token TEXT,token_address TEXT,pair_address TEXT,opened_at TEXT,entry_market_price REAL,entry_price REAL,notional_usd REAL,quantity REAL,entry_fee REAL,status TEXT,highest_price REAL,lowest_price REAL,current_price REAL,current_return_pct REAL,mfe_pct REAL,mae_pct REAL)""")
 c.commit(); return c

def record(conn,x,result):
 now=datetime.now(timezone.utc).isoformat()
 cur=conn.execute("""INSERT INTO meme_candidates(seen_at,version,token,chain,score,eligible,blocked_reasons,raw_json) VALUES(?,?,?,?,?,?,?,?)""",(now,VERSION,x.get("token"),x.get("chain"),result["score"],int(result["eligible"]),json.dumps(result["blocked_reasons"]),json.dumps(x)))
 cid=cur.lastrowid
 if x.get("token_address") and x.get("price_usd"):
  p=float(x["price_usd"])
  conn.execute("INSERT OR IGNORE INTO meme_outcomes VALUES(?,?,?,?,?,?,?,?,?,?,?)",(cid,x.get("token_address"),x.get("pair_address"),now,p,p,p,p,0,0,0))
  if result["eligible"]:
   ep=p*(1+PAPER_SLIPPAGE_RATE); fee=PAPER_NOTIONAL_USD*PAPER_FEE_RATE; qty=(PAPER_NOTIONAL_USD-fee)/ep
   conn.execute("""INSERT OR IGNORE INTO meme_paper_trades(candidate_id,token,token_address,pair_address,opened_at,entry_market_price,entry_price,notional_usd,quantity,entry_fee,status,highest_price,lowest_price,current_price,current_return_pct,mfe_pct,mae_pct) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",(cid,x.get("token"),x.get("token_address"),x.get("pair_address"),now,p,ep,PAPER_NOTIONAL_USD,qty,fee,"OPEN",p,p,p,0,0,0))
 conn.commit()

def self_test():
 x={"token":"TEST","token_address":"abc","pair_address":"pair","chain":"solana","price_usd":.01,"liquidity_usd":100000,"makers":500,"top10_holder_pct":30,"dev_holder_pct":3,"mint_authority_active":False,"freeze_authority_active":False,"sellable":True,"liquidity_locked":True,"volume_1h_usd":100000,"price_change_1h_pct":25,"volume_accel":4,"holder_growth_1h_pct":15,"higher_highs":True,"narrative_momentum":True}
 assert evaluate(x)["eligible"]; c=init_db(":memory:"); record(c,x,evaluate(x))
 assert c.execute("select count(*) from meme_outcomes").fetchone()[0]==1
 assert c.execute("select count(*) from meme_paper_trades").fetchone()[0]==1
 print("memecoin shadow V2 self-test passed")

def main():
 p=argparse.ArgumentParser(); p.add_argument("--input"); p.add_argument("--self-test",action="store_true"); a=p.parse_args()
 if a.self_test: self_test(); return
 if not a.input: p.error("--input is required outside self-test")
 rows=json.load(open(a.input)); rows=[rows] if isinstance(rows,dict) else rows; c=init_db()
 for x in rows: r=evaluate(x); record(c,x,r); print(json.dumps(r))
 c.close()
if __name__=="__main__": main()
