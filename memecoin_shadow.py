"""Research-only memecoin candidate engine.

No orders are placed. Candidates must pass deterministic safety/liquidity filters
before momentum scoring. Feed normalized DEX/on-chain observations as JSON.
"""
import argparse, json, sqlite3
from datetime import datetime, timezone

DB = "memecoin_shadow.db"
VERSION = "MEME_SHADOW_V1"

DEFAULTS = {
    "min_liquidity_usd": 50000.0,
    "min_makers": 200,
    "max_top10_holder_pct": 50.0,
    "max_dev_holder_pct": 10.0,
    "min_volume_1h_usd": 25000.0,
    "min_score": 65.0,
}

def safety_reasons(x, cfg=DEFAULTS):
    reasons = []
    if float(x.get("liquidity_usd", 0)) < cfg["min_liquidity_usd"]: reasons.append("LOW_LIQUIDITY")
    if int(x.get("makers", 0)) < cfg["min_makers"]: reasons.append("LOW_PARTICIPATION")
    if float(x.get("top10_holder_pct", 100)) > cfg["max_top10_holder_pct"]: reasons.append("HOLDER_CONCENTRATION")
    if float(x.get("dev_holder_pct", 100)) > cfg["max_dev_holder_pct"]: reasons.append("DEV_CONCENTRATION")
    if x.get("mint_authority_active", True): reasons.append("MINT_AUTHORITY")
    if x.get("freeze_authority_active", True): reasons.append("FREEZE_AUTHORITY")
    if not x.get("sellable", False): reasons.append("SELLABILITY")
    if not x.get("liquidity_locked", False): reasons.append("LIQUIDITY_CONTROL")
    return reasons

def score(x):
    s = 0.0
    s += min(max(float(x.get("price_change_1h_pct", 0)), 0), 30) * 1.0
    s += min(max(float(x.get("volume_accel", 0)) - 1, 0), 4) * 7.5
    s += min(max(float(x.get("holder_growth_1h_pct", 0)), 0), 20) * 0.75
    s += 10 if x.get("higher_highs", False) else 0
    s += 10 if x.get("narrative_momentum", False) else 0
    return round(min(s, 100), 2)

def evaluate(x):
    blocked = safety_reasons(x)
    s = score(x)
    return {"version": VERSION, "token": x.get("token"), "chain": x.get("chain"),
            "score": s, "eligible": not blocked and s >= DEFAULTS["min_score"],
            "blocked_reasons": blocked}

def init_db(path=DB):
    c=sqlite3.connect(path)
    c.execute("""CREATE TABLE IF NOT EXISTS meme_candidates(
      id INTEGER PRIMARY KEY, seen_at TEXT, version TEXT, token TEXT, chain TEXT,
      score REAL, eligible INTEGER, blocked_reasons TEXT, raw_json TEXT)""")
    c.commit(); return c

def record(conn, x, result):
    conn.execute("""INSERT INTO meme_candidates
      (seen_at,version,token,chain,score,eligible,blocked_reasons,raw_json)
      VALUES(?,?,?,?,?,?,?,?)""",
      (datetime.now(timezone.utc).isoformat(), VERSION, x.get("token"), x.get("chain"),
       result["score"], int(result["eligible"]), json.dumps(result["blocked_reasons"]), json.dumps(x)))
    conn.commit()

def self_test():
    good={"token":"TEST","chain":"solana","liquidity_usd":100000,"makers":500,
          "top10_holder_pct":30,"dev_holder_pct":3,"mint_authority_active":False,
          "freeze_authority_active":False,"sellable":True,"liquidity_locked":True,
          "volume_1h_usd":100000,"price_change_1h_pct":25,"volume_accel":4,
          "holder_growth_1h_pct":15,"higher_highs":True,"narrative_momentum":True}
    assert safety_reasons(good)==[]
    assert evaluate(good)["eligible"]
    bad=dict(good, sellable=False)
    assert not evaluate(bad)["eligible"]
    print("memecoin shadow self-test passed")

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--input", help="JSON file containing one object or a list")
    p.add_argument("--self-test", action="store_true")
    args=p.parse_args()
    if args.self_test: self_test(); return
    if not args.input: p.error("--input is required outside self-test")
    with open(args.input) as f: rows=json.load(f)
    if isinstance(rows, dict): rows=[rows]
    conn=init_db()
    for x in rows:
        r=evaluate(x); record(conn,x,r); print(json.dumps(r))
    conn.close()

if __name__=="__main__": main()
