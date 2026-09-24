"""Research-only pre-spike feature study. Never places orders."""
import argparse, json, sqlite3, statistics
from datetime import datetime

DB="memecoin_shadow.db"
VERSION="MEME_PRE_SPIKE_V1"
WINDOWS=(5,10,15,20)
TARGETS=(10,20,30)

def tables(conn):
    conn.execute("""CREATE TABLE IF NOT EXISTS meme_pre_spike_research(
      id INTEGER PRIMARY KEY AUTOINCREMENT, generated_at TEXT DEFAULT CURRENT_TIMESTAMP,
      version TEXT, window_minutes INTEGER, target_pct REAL, samples INTEGER,
      hits INTEGER, hit_rate_pct REAL, avg_score_hit REAL, avg_score_miss REAL,
      avg_liquidity_hit REAL, avg_liquidity_miss REAL)""")
    conn.commit()

def _candidate_rows(conn):
    # raw_json is the immutable discovery-time feature payload.
    return conn.execute("""SELECT id,token_address,seen_at,score,raw_json
      FROM meme_candidates WHERE token_address IS NOT NULL AND seen_at IS NOT NULL""").fetchall()

def _max_forward(conn, token, seen_at, entry, minutes):
    snaps=conn.execute("""SELECT observed_at,price FROM meme_price_snapshots
      WHERE token_address=? AND observed_at>=? ORDER BY observed_at""",(token,seen_at)).fetchall()
    if not snaps or not entry: return None
    start=datetime.fromisoformat(seen_at)
    vals=[]
    covered=False
    for observed,price in snaps:
        age=(datetime.fromisoformat(observed)-start).total_seconds()/60
        if age < 0: continue
        if age <= minutes: vals.append((price/entry-1)*100)
        if age >= minutes:
            covered=True
            break
    return max(vals) if vals and covered else None

def run(path=DB):
    conn=sqlite3.connect(path); tables(conn)
    cols={r[1] for r in conn.execute("PRAGMA table_info(meme_candidates)")}
    required={"id","token_address","seen_at","score","raw_json"}
    if not required.issubset(cols):
        print("PRE-SPIKE waiting: discovery schema does not expose required immutable features")
        conn.close(); return
    outcomes={r[0]:r[1] for r in conn.execute(
        "SELECT token_address,entry_price FROM meme_outcomes WHERE entry_price>0")}
    rows=_candidate_rows(conn)
    print(f"PRE-SPIKE candidates={len(rows)} version={VERSION}")
    for window in WINDOWS:
        evaluated=[]
        for _,token,seen,score,raw in rows:
            entry=outcomes.get(token)
            if not entry: continue
            forward=_max_forward(conn,token,seen,entry,window)
            if forward is None: continue
            try: payload=json.loads(raw or "{}")
            except Exception: payload={}
            liq=float(payload.get("liquidity_usd") or 0)
            evaluated.append((float(score or 0),liq,forward))
        for target in TARGETS:
            hits=[x for x in evaluated if x[2]>=target]
            misses=[x for x in evaluated if x[2]<target]
            def avg(group,idx):
                return round(statistics.mean(x[idx] for x in group),3) if group else None
            result=(VERSION,window,target,len(evaluated),len(hits),
                    round(100*len(hits)/len(evaluated),2) if evaluated else 0,
                    avg(hits,0),avg(misses,0),avg(hits,1),avg(misses,1))
            conn.execute("""INSERT INTO meme_pre_spike_research(
              version,window_minutes,target_pct,samples,hits,hit_rate_pct,
              avg_score_hit,avg_score_miss,avg_liquidity_hit,avg_liquidity_miss)
              VALUES(?,?,?,?,?,?,?,?,?,?)""",result)
            print({"window_min":window,"target_pct":target,"samples":len(evaluated),
                   "hits":len(hits),"hit_rate_pct":result[5],
                   "avg_score_hit":result[6],"avg_score_miss":result[7],
                   "avg_liquidity_hit":result[8],"avg_liquidity_miss":result[9]})
    conn.commit(); conn.close()

def self_test():
    c=sqlite3.connect(":memory:"); tables(c)
    assert c.execute("SELECT COUNT(*) FROM meme_pre_spike_research").fetchone()[0]==0
    c.close(); print("meme pre-spike research self-test passed")

if __name__=="__main__":
    p=argparse.ArgumentParser(); p.add_argument("--self-test",action="store_true")
    a=p.parse_args(); self_test() if a.self_test else run()
