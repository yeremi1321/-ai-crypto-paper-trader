"""Research-only analysis of memecoin entry timing and exit hypotheses.

Reads observed shadow outcomes. It does not place orders or change production rules.
"""
import argparse, sqlite3, statistics
DB="memecoin_shadow.db"
VERSION="MEME_RESEARCH_V2"

def init(conn):
 conn.execute("""CREATE TABLE IF NOT EXISTS meme_research_summary(
  id INTEGER PRIMARY KEY, generated_at TEXT DEFAULT CURRENT_TIMESTAMP,
  version TEXT, cohort TEXT, samples INTEGER, avg_mfe_pct REAL, avg_mae_pct REAL,
  avg_last_return_pct REAL, hit_10_pct INTEGER, hit_20_pct INTEGER,
  stopped_10_pct INTEGER)"""); conn.commit()

def pct(a,b): return ((b/a)-1)*100 if a else 0.0

def summarize(path=DB):
 conn=sqlite3.connect(path); init(conn)
 rows=conn.execute("""SELECT entry_price,last_price,highest_price,lowest_price,age_minutes
 FROM meme_outcomes WHERE entry_price>0 AND last_price>0""").fetchall()
 if not rows:
  print("No memecoin outcomes available yet; research waits for observations."); return None
 mfe=[pct(r[0],r[2]) for r in rows]; mae=[pct(r[0],r[3]) for r in rows]; last=[pct(r[0],r[1]) for r in rows]
 result={"version":VERSION,"samples":len(rows),"avg_mfe_pct":round(statistics.mean(mfe),3),
 "avg_mae_pct":round(statistics.mean(mae),3),"avg_last_return_pct":round(statistics.mean(last),3),
 "hit_10_pct":sum(x>=10 for x in mfe),"hit_20_pct":sum(x>=20 for x in mfe),
 "stopped_10_pct":sum(x<=-10 for x in mae)}
 conn.execute("""INSERT INTO meme_research_summary(version,cohort,samples,avg_mfe_pct,avg_mae_pct,
 avg_last_return_pct,hit_10_pct,hit_20_pct,stopped_10_pct) VALUES(?,?,?,?,?,?,?,?,?)""",
 (VERSION,"ALL",result["samples"],result["avg_mfe_pct"],result["avg_mae_pct"],result["avg_last_return_pct"],
 result["hit_10_pct"],result["hit_20_pct"],result["stopped_10_pct"])); conn.commit()
 paths=replay_paths(conn)
 conn.close()
 print(result)
 print({"path_replay":paths})
 return result


def replay_paths(conn):
 """Replay exits only on paths with timely snapshots and full horizon coverage."""
 exists=conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='meme_price_snapshots'").fetchone()
 if not exists: return []
 candidates=conn.execute("""SELECT candidate_id,token_address,detected_at,entry_price
 FROM meme_outcomes WHERE entry_price>0""").fetchall()
 rules=[("TP10_SL10",10,-10,20),("TP20_SL10",20,-10,20),("TP25_SL10",25,-10,20),
        ("TIME10_SL10",None,-10,10),("TIME20_SL10",None,-10,20)]
 results=[]
 for name,tp,sl,minutes in rules:
  returns=[]; eligible_paths=0; rejected_late=0; rejected_short=0
  for _,token,detected,entry in candidates:
   snaps=conn.execute("""SELECT observed_at,price FROM meme_price_snapshots
    WHERE token_address=? AND observed_at>=? ORDER BY observed_at""",(token,detected)).fetchall()
   if not snaps: continue
   start=__import__("datetime").datetime.fromisoformat(detected)
   parsed=[((__import__("datetime").datetime.fromisoformat(o)-start).total_seconds()/60,p) for o,p in snaps]
   # A replay is valid only when observation begins near detection and spans the rule horizon.
   if parsed[0][0] > 5:
    rejected_late += 1; continue
   if parsed[-1][0] < minutes:
    rejected_short += 1; continue
   eligible_paths += 1
   chosen=None
   for age,price in parsed:
    if age < 0 or age > minutes: continue
    ret=pct(entry,price)
    if ret<=sl:
     chosen=sl; break
    if tp is not None and ret>=tp:
     chosen=tp; break
   if chosen is None:
    # Time exit uses the first snapshot at/after the requested horizon.
    after=[(age,price) for age,price in parsed if age>=minutes]
    if after: chosen=pct(entry,after[0][1])
   if chosen is not None: returns.append(chosen)
  row={"rule":name,"valid_paths":eligible_paths,"samples":len(returns),
       "rejected_late_start":rejected_late,"rejected_short_path":rejected_short}
  if returns:
   row.update({"avg_return_pct":round(statistics.mean(returns),3),
               "win_rate_pct":round(100*sum(x>0 for x in returns)/len(returns),1)})
  results.append(row)
 return results

def self_test():
 c=sqlite3.connect(":memory:"); init(c)
 c.execute("""CREATE TABLE meme_outcomes(candidate_id INTEGER PRIMARY KEY,token_address TEXT,pair_address TEXT,
 detected_at TEXT,entry_price REAL,last_price REAL,highest_price REAL,lowest_price REAL,mfe_pct REAL,mae_pct REAL,age_minutes REAL)""")
 c.execute("INSERT INTO meme_outcomes VALUES(1,'a','p','t',100,105,125,90,25,-10,60)")
 c.commit()
 rows=c.execute("select entry_price,last_price,highest_price,lowest_price from meme_outcomes").fetchall()
 assert round(pct(rows[0][0],rows[0][2]),2)==25 and round(pct(rows[0][0],rows[0][3]),2)==-10
 print("memecoin entry/exit research self-test passed")

if __name__=="__main__":
 p=argparse.ArgumentParser(); p.add_argument("--self-test",action="store_true"); a=p.parse_args()
 self_test() if a.self_test else summarize()
