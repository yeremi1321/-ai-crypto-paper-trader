"""Research-only memecoin candidate, outcome, and simulated-trade storage."""
import argparse,json,sqlite3,os
from datetime import datetime,timezone,timedelta
DB="memecoin_shadow.db"; VERSION="MEME_SHADOW_V2" # deploy-sync d545183
PAPER_NOTIONAL_USD=100.0; PAPER_FEE_RATE=.006; PAPER_SLIPPAGE_RATE=.01
MAX_OPEN_PAPER_POSITIONS=5
REENTRY_LOOKBACK=timedelta(minutes=5)

def fresh_reentry(conn,token,price,closed_at,pg,now):
 """Allow a new leg after a close when price breaks recent observed highs.

 The new upswing also has to exceed the paper round-trip cost from its
 observed low. This allows a fresh move after a pullback below the last exit.
 """
 if not closed_at or not price: return False
 since=max(datetime.fromisoformat(closed_at),now-REENTRY_LOOKBACK).isoformat()
 sql="""SELECT price FROM meme_price_snapshots WHERE token_address=?
         AND observed_at>=? AND observed_at<? ORDER BY observed_at DESC LIMIT 30"""
 history=conn.execute(sql.replace("?","%s") if pg else sql,(token,since,now.isoformat())).fetchall()
 if len(history)<2: return False
 cost=((1+PAPER_SLIPPAGE_RATE)/(1-PAPER_SLIPPAGE_RATE)
       *(1+PAPER_FEE_RATE)/(1-PAPER_FEE_RATE)-1)
 prices=[float(v[0]) for v in history]
 return float(price)>max(prices) and float(price)>min(prices)*(1+cost)

def stop_reclaimed(exit_reason,prior_entry_market_price,price):
 """A stopped token must reclaim the failed trade's market entry price."""
 if exit_reason!="STOP_10": return True
 if not prior_entry_market_price or not price: return False
 return float(price)>float(prior_entry_market_price)

DEFAULTS={"min_liquidity_usd":30000.0,"min_makers":100,"max_top10_holder_pct":50.0,"max_dev_holder_pct":10.0,"min_volume_1h_usd":25000.0,"min_score":60.0}

def safety_reasons(x,cfg=DEFAULTS):
 r=[]
 if float(x.get("liquidity_usd",0))<cfg["min_liquidity_usd"]: r.append("LOW_LIQUIDITY")
 if int(x.get("makers",0))<cfg["min_makers"]: r.append("LOW_PARTICIPATION")
 if x.get("top10_holder_pct") is not None and float(x["top10_holder_pct"])>cfg["max_top10_holder_pct"]: r.append("HOLDER_CONCENTRATION")
 if x.get("dev_holder_pct") is not None and float(x["dev_holder_pct"])>cfg["max_dev_holder_pct"]: r.append("DEV_CONCENTRATION")
 if x.get("mint_authority_active") is True: r.append("MINT_AUTHORITY")
 if x.get("freeze_authority_active") is True: r.append("FREEZE_AUTHORITY")
 if x.get("sellable") is False: r.append("SELLABILITY")
 if x.get("liquidity_locked") is False: r.append("LIQUIDITY_CONTROL")
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
 # Keep SQLite for explicit test/local paths. Render uses PostgreSQL when DATABASE_URL is present.
 if path==DB and os.getenv("DATABASE_URL"):
  import psycopg
  c=psycopg.connect(os.environ["DATABASE_URL"])
  c.execute("""CREATE TABLE IF NOT EXISTS meme_candidates(id BIGSERIAL PRIMARY KEY,seen_at TEXT,version TEXT,token TEXT,chain TEXT,score DOUBLE PRECISION,eligible INTEGER,blocked_reasons TEXT,raw_json TEXT,token_address TEXT,pair_address TEXT)""")
  c.execute("""CREATE TABLE IF NOT EXISTS meme_outcomes(candidate_id BIGINT PRIMARY KEY,token_address TEXT,pair_address TEXT,detected_at TEXT,entry_price DOUBLE PRECISION,last_price DOUBLE PRECISION,highest_price DOUBLE PRECISION,lowest_price DOUBLE PRECISION,mfe_pct DOUBLE PRECISION,mae_pct DOUBLE PRECISION,age_minutes DOUBLE PRECISION)""")
  c.execute("""CREATE TABLE IF NOT EXISTS meme_decision_ledger(id BIGSERIAL PRIMARY KEY,candidate_id BIGINT UNIQUE,recorded_at TEXT,version TEXT,token TEXT,token_address TEXT,pair_address TEXT,chain TEXT,venue TEXT,data_source TEXT,regime TEXT,liquidity_usd DOUBLE PRECISION,volume_1h_usd DOUBLE PRECISION,participation INTEGER,estimated_entry_slippage_pct DOUBLE PRECISION,estimated_exit_slippage_pct DOUBLE PRECISION,setup_type TEXT,entry_rule TEXT,risk_rule TEXT,score DOUBLE PRECISION,decision TEXT,vetoes TEXT,simulated_entry_price DOUBLE PRECISION,simulated_entry_fee DOUBLE PRECISION,notional_usd DOUBLE PRECISION,outcome_label TEXT,net_return_pct DOUBLE PRECISION,mfe_pct DOUBLE PRECISION,mae_pct DOUBLE PRECISION,time_in_trade_minutes DOUBLE PRECISION,ai_explanation TEXT,raw_json TEXT)""")
  c.execute("""CREATE TABLE IF NOT EXISTS meme_paper_trades(id BIGSERIAL PRIMARY KEY,candidate_id BIGINT UNIQUE,token TEXT,token_address TEXT,pair_address TEXT,opened_at TEXT,entry_market_price DOUBLE PRECISION,entry_price DOUBLE PRECISION,notional_usd DOUBLE PRECISION,quantity DOUBLE PRECISION,entry_fee DOUBLE PRECISION,status TEXT,highest_price DOUBLE PRECISION,lowest_price DOUBLE PRECISION,current_price DOUBLE PRECISION,current_return_pct DOUBLE PRECISION,mfe_pct DOUBLE PRECISION,mae_pct DOUBLE PRECISION,closed_at TEXT,exit_market_price DOUBLE PRECISION)""")
  c.execute("ALTER TABLE meme_paper_trades ADD COLUMN IF NOT EXISTS exit_reason TEXT")
  c.commit(); return c
 c=sqlite3.connect(path)
 c.execute("""CREATE TABLE IF NOT EXISTS meme_candidates(id INTEGER PRIMARY KEY,seen_at TEXT,version TEXT,token TEXT,chain TEXT,score REAL,eligible INTEGER,blocked_reasons TEXT,raw_json TEXT)""")
 # Pre-spike research needs stable discovery identifiers on both new and legacy DBs.
 cols={r[1] for r in c.execute("PRAGMA table_info(meme_candidates)")}
 if "token_address" not in cols: c.execute("ALTER TABLE meme_candidates ADD COLUMN token_address TEXT")
 if "pair_address" not in cols: c.execute("ALTER TABLE meme_candidates ADD COLUMN pair_address TEXT")
 c.execute("""CREATE TABLE IF NOT EXISTS meme_outcomes(candidate_id INTEGER PRIMARY KEY,token_address TEXT,pair_address TEXT,detected_at TEXT,entry_price REAL,last_price REAL,highest_price REAL,lowest_price REAL,mfe_pct REAL,mae_pct REAL,age_minutes REAL)""")
 c.execute("""CREATE TABLE IF NOT EXISTS meme_decision_ledger(
 id INTEGER PRIMARY KEY,candidate_id INTEGER UNIQUE,recorded_at TEXT,version TEXT,
 token TEXT,token_address TEXT,pair_address TEXT,chain TEXT,venue TEXT,data_source TEXT,
 regime TEXT,liquidity_usd REAL,volume_1h_usd REAL,participation INTEGER,
 estimated_entry_slippage_pct REAL,estimated_exit_slippage_pct REAL,
 setup_type TEXT,entry_rule TEXT,risk_rule TEXT,score REAL,decision TEXT,vetoes TEXT,
 simulated_entry_price REAL,simulated_entry_fee REAL,notional_usd REAL,
 outcome_label TEXT,net_return_pct REAL,mfe_pct REAL,mae_pct REAL,time_in_trade_minutes REAL,
 ai_explanation TEXT,raw_json TEXT)""")
 c.execute("""CREATE TABLE IF NOT EXISTS meme_paper_trades(id INTEGER PRIMARY KEY,candidate_id INTEGER UNIQUE,token TEXT,token_address TEXT,pair_address TEXT,opened_at TEXT,entry_market_price REAL,entry_price REAL,notional_usd REAL,quantity REAL,entry_fee REAL,status TEXT,highest_price REAL,lowest_price REAL,current_price REAL,current_return_pct REAL,mfe_pct REAL,mae_pct REAL,closed_at TEXT,exit_market_price REAL)""")
 if "exit_reason" not in {r[1] for r in c.execute("PRAGMA table_info(meme_paper_trades)")}:
  c.execute("ALTER TABLE meme_paper_trades ADD COLUMN exit_reason TEXT")
 c.commit(); return c
def record(conn,x,result):
 now=datetime.now(timezone.utc).isoformat()
 pg=conn.__class__.__module__.startswith("psycopg")
 # A repeated discovery observation is not a new position. Keep it in the
 # research ledger while limiting simulated exposure and churn per token.
 entry_allowed=bool(result["eligible"] and x.get("price_usd") and x.get("token_address"))
 entry_veto=None
 if entry_allowed:
  ph="%s" if pg else "?"
  open_count=conn.execute("SELECT COUNT(*) FROM meme_paper_trades WHERE status='OPEN'").fetchone()[0]
  if open_count>=MAX_OPEN_PAPER_POSITIONS:
   entry_veto="MAX_OPEN_POSITIONS"
  elif conn.execute(f"SELECT 1 FROM meme_paper_trades WHERE token_address={ph} AND status='OPEN' LIMIT 1",(x["token_address"],)).fetchone():
   entry_veto="TOKEN_ALREADY_OPEN"
  else:
   recent=conn.execute(f"SELECT closed_at,exit_reason,entry_market_price FROM meme_paper_trades WHERE token_address={ph} AND status='CLOSED' ORDER BY id DESC LIMIT 1",(x["token_address"],)).fetchone()
   if recent and not fresh_reentry(conn,x["token_address"],x["price_usd"],recent[0],pg,datetime.fromisoformat(now)):
    entry_veto="NO_FRESH_REENTRY_SETUP"
   elif recent and not stop_reclaimed(recent[1],recent[2],x["price_usd"]):
    entry_veto="STOP_NOT_RECLAIMED"
  entry_allowed=entry_veto is None
 sql="""INSERT INTO meme_candidates(seen_at,version,token,chain,score,eligible,blocked_reasons,raw_json,token_address,pair_address) VALUES(?,?,?,?,?,?,?,?,?,?)"""
 if pg: sql=sql.replace("?","%s")+" RETURNING id"
 cur=conn.execute(sql,(now,VERSION,x.get("token"),x.get("chain"),result["score"],int(result["eligible"]),json.dumps(result["blocked_reasons"]),json.dumps(x),x.get("token_address"),x.get("pair_address")))
 cid=cur.fetchone()[0] if pg else cur.lastrowid
 decision="PAPER_TRADE_CANDIDATE" if entry_allowed else ("PAPER_ENTRY_BLOCKED" if entry_veto else ("REJECT" if result["blocked_reasons"] else "WATCHLIST"))
 vetoes=json.dumps(result["blocked_reasons"]+([entry_veto] if entry_veto else []))
 explanation=("Eligible: safety gates passed and score meets threshold." if result["eligible"]
              else "Rejected by deterministic gates: "+(",".join(result["blocked_reasons"]) or "score below threshold."))
 simulated_entry=None; simulated_fee=None
 if entry_allowed:
  simulated_entry=float(x["price_usd"])*(1+PAPER_SLIPPAGE_RATE)
  simulated_fee=PAPER_NOTIONAL_USD*PAPER_FEE_RATE
 ledger_sql="""INSERT INTO meme_decision_ledger(
 candidate_id,recorded_at,version,token,token_address,pair_address,chain,venue,data_source,regime,
 liquidity_usd,volume_1h_usd,participation,estimated_entry_slippage_pct,estimated_exit_slippage_pct,
 setup_type,entry_rule,risk_rule,score,decision,vetoes,simulated_entry_price,simulated_entry_fee,
 notional_usd,outcome_label,ai_explanation,raw_json)
 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"""
 if pg: ledger_sql=ledger_sql.replace("?","%s")
 conn.execute(ledger_sql,
 (cid,now,VERSION,x.get("token"),x.get("token_address"),x.get("pair_address"),x.get("chain"),x.get("dex"),
 x.get("security_source"),x.get("market_regime","UNKNOWN"),float(x.get("liquidity_usd",0)),
 float(x.get("volume_1h_usd",0)),int(x.get("makers",0)),PAPER_SLIPPAGE_RATE*100,PAPER_SLIPPAGE_RATE*100,
 "MOMENTUM_ACCELERATION","Research candidate after deterministic safety + score gates",
 "Research-only; no live execution; simulated costs enforced",result["score"],decision,vetoes,
  simulated_entry,simulated_fee,PAPER_NOTIONAL_USD if entry_allowed else 0,
 "PENDING",explanation,json.dumps(x)))
 if x.get("token_address") and x.get("price_usd"):
  p=float(x["price_usd"])
  conn.execute(("INSERT INTO meme_outcomes VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING" if pg else "INSERT OR IGNORE INTO meme_outcomes VALUES(?,?,?,?,?,?,?,?,?,?,?)"),(cid,x.get("token_address"),x.get("pair_address"),now,p,p,p,p,0,0,0))
  if entry_allowed:
   ep=p*(1+PAPER_SLIPPAGE_RATE); fee=PAPER_NOTIONAL_USD*PAPER_FEE_RATE; qty=(PAPER_NOTIONAL_USD-fee)/ep
   conn.execute(("""INSERT INTO meme_paper_trades(candidate_id,token,token_address,pair_address,opened_at,entry_market_price,entry_price,notional_usd,quantity,entry_fee,status,highest_price,lowest_price,current_price,current_return_pct,mfe_pct,mae_pct) VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT DO NOTHING""" if pg else """INSERT OR IGNORE INTO meme_paper_trades(candidate_id,token,token_address,pair_address,opened_at,entry_market_price,entry_price,notional_usd,quantity,entry_fee,status,highest_price,lowest_price,current_price,current_return_pct,mfe_pct,mae_pct) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"""),(cid,x.get("token"),x.get("token_address"),x.get("pair_address"),now,p,ep,PAPER_NOTIONAL_USD,qty,fee,"OPEN",p,p,p,0,0,0))
 conn.commit()

def self_test():
 x={"token":"TEST","token_address":"abc","pair_address":"pair","chain":"solana","price_usd":.01,"liquidity_usd":100000,"makers":500,"top10_holder_pct":30,"dev_holder_pct":3,"mint_authority_active":False,"freeze_authority_active":False,"sellable":True,"liquidity_locked":True,"volume_1h_usd":100000,"price_change_1h_pct":25,"volume_accel":4,"holder_growth_1h_pct":15,"higher_highs":True,"narrative_momentum":True}
 assert evaluate(x)["eligible"]; c=init_db(":memory:"); record(c,x,evaluate(x))
 from memecoin_paper import migrate
 migrate(c)
 assert c.execute("select count(*) from meme_outcomes").fetchone()[0]==1
 assert c.execute("select count(*) from meme_paper_trades").fetchone()[0]==1
 row=c.execute("select decision,outcome_label from meme_decision_ledger").fetchone()
 assert row==("PAPER_TRADE_CANDIDATE","PENDING")
 record(c,x,evaluate(x))
 assert c.execute("select count(*) from meme_paper_trades").fetchone()[0]==1
 assert c.execute("select decision,vetoes from meme_decision_ledger order by id desc limit 1").fetchone()==("PAPER_ENTRY_BLOCKED",'["TOKEN_ALREADY_OPEN"]')
 c.execute("UPDATE meme_paper_trades SET status='CLOSED',closed_at=?,exit_market_price=?",(datetime.now(timezone.utc).isoformat(),.02))
 c.execute("CREATE TABLE meme_price_snapshots(observed_at TEXT,token_address TEXT,price REAL)")
 c.commit()
 record(c,x,evaluate(x))
 assert c.execute("select count(*) from meme_paper_trades").fetchone()[0]==1
 assert c.execute("select decision,vetoes from meme_decision_ledger order by id desc limit 1").fetchone()==("PAPER_ENTRY_BLOCKED",'["NO_FRESH_REENTRY_SETUP"]')
 for p in (.0101,.0102):
  c.execute("INSERT INTO meme_price_snapshots VALUES(?,?,?)",(datetime.now(timezone.utc).isoformat(),x["token_address"],p))
 c.commit()
 fresh=dict(x,price_usd=.0105)
 record(c,fresh,evaluate(fresh))
 assert c.execute("select count(*) from meme_paper_trades").fetchone()[0]==2
 bad=dict(x); bad["liquidity_usd"]=10; record(c,bad,evaluate(bad))
 assert c.execute("select count(*) from meme_decision_ledger where decision='REJECT'").fetchone()[0]==1
 print("memecoin shadow V2 self-test passed")

def main():
 p=argparse.ArgumentParser(); p.add_argument("--input"); p.add_argument("--self-test",action="store_true"); a=p.parse_args()
 if a.self_test: self_test(); return
 if not a.input: p.error("--input is required outside self-test")
 rows=json.load(open(a.input)); rows=[rows] if isinstance(rows,dict) else rows; c=init_db()
 for x in rows: r=evaluate(x); record(c,x,r); print(json.dumps(r))
 c.close()
if __name__=="__main__": main()
