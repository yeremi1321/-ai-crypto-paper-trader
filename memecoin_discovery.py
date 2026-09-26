"""Research-only live memecoin discovery.

Discovers recent Solana token profiles from DEX Screener, enriches them with
pair/liquidity/momentum data, optionally adds GoPlus security data, then feeds
the normalized observations into memecoin_shadow. No orders are placed.
"""
import argparse, json, os, time
from datetime import datetime, timezone
import requests
from memecoin_shadow import init_db, evaluate, record

DEX="https://api.dexscreener.com"
GOPLUS="https://api.gopluslabs.io/api/v1/solana/token_security"
SESSION=requests.Session()
SESSION.headers.update({"User-Agent":"ai-crypto-paper-trader/memecoin-shadow-v1"})

def get_json(url, params=None, headers=None, attempts=3):
    err=None
    for n in range(attempts):
        try:
            r=SESSION.get(url,params=params,headers=headers,timeout=20)
            if r.status_code == 429:
                retry_after = r.headers.get("Retry-After")
                wait = float(retry_after) if retry_after and retry_after.isdigit() else 3.0*(n+1)
                err=RuntimeError(f"429 rate limited; retrying after {wait:.1f}s")
                time.sleep(wait); continue
            r.raise_for_status(); return r.json()
        except Exception as e:
            err=e; time.sleep(1.5*(n+1))
    raise RuntimeError(f"request failed: {url}: {err}")

def latest_solana(limit=30):
    rows=get_json(f"{DEX}/token-profiles/latest/v1")
    out=[]; seen=set()
    for x in rows if isinstance(rows,list) else []:
        a=x.get("tokenAddress")
        if x.get("chainId")=="solana" and a and a not in seen:
            seen.add(a); out.append(x)
            if len(out)>=limit: break
    return out

def best_pair(address):
    rows=get_json(f"{DEX}/token-pairs/v1/solana/{address}")
    rows=[x for x in (rows or []) if x.get("priceUsd")]
    return max(rows,key=lambda x: float((x.get("liquidity") or {}).get("usd") or 0),default=None)

def goplus(address):
    token=os.getenv("GOPLUS_TOKEN")
    headers={"Authorization":f"Bearer {token}"} if token else None
    try:
        data=get_json(GOPLUS,{"contract_addresses":address},headers,attempts=2)
        result=data.get("result") or {}
        return result.get(address) or result.get(address.lower()) or {}
    except Exception as e:
        print(f"::warning::GoPlus unavailable for {address}: {e}")
        return {}

def truth(v):
    return str(v).lower() in ("1","true","yes")

def status(sec,key):
    v=sec.get(key) if sec else None
    if isinstance(v,dict): v=v.get("status")
    if v in (None,""): return None
    return truth(v)

def percent(v):
    if v in (None,""): return None
    n=float(v); return n*100 if n<=1 else n

def normalize(profile,pair,sec):
    tx=(pair.get("txns") or {}).get("h1") or {}
    vol=pair.get("volume") or {}
    pc=pair.get("priceChange") or {}
    liq=pair.get("liquidity") or {}
    h1=float(vol.get("h1") or 0); h6=float(vol.get("h6") or 0)
    makers=int(tx.get("buys") or 0)+int(tx.get("sells") or 0)  # participation proxy, not unique wallets
    holders=sec.get("holders") if sec else None
    hp=[percent(h.get("percent")) for h in holders or [] if percent(h.get("percent")) is not None]
    top10=sum(hp) if hp else None
    creator=percent(sec.get("creator_percent")) if sec else None
    if creator is None and sec: creator=percent(sec.get("creator_balance_rate"))
    lp=sec.get("lp_holders") if sec else None
    locked=truth(sec.get("is_locked")) if sec and "is_locked" in sec else (any(truth(h.get("is_locked")) for h in lp) if lp else None)
    mint_active=status(sec,"mintable")
    freeze_active=status(sec,"freezable")
    nontransfer=status(sec,"non_transferable")
    cannot_sell=status(sec,"cannot_sell")
    if cannot_sell is None and sec and isinstance(sec.get("b20_info"),dict): cannot_sell=status(sec["b20_info"],"cannot_sell")
    sellable=False if nontransfer is True or cannot_sell is True else (True if nontransfer is False or cannot_sell is False else (not truth(sec.get("cannot_sell_all")) if sec and "cannot_sell_all" in sec else False))
    # Preserve unavailable security fields as unknown. Paper mode can observe them without falsely classifying unknown as unsafe.
    return {
      "token":(pair.get("baseToken") or {}).get("symbol") or profile.get("tokenAddress"),
      "token_address":profile.get("tokenAddress"),"chain":"solana",
      "pair_address":pair.get("pairAddress"),"dex":pair.get("dexId"),
      "price_usd":float(pair.get("priceUsd") or 0),
      "liquidity_usd":float(liq.get("usd") or 0),"makers":makers,
      "volume_1h_usd":h1,"volume_accel":round(h1/max(h6/6,1),3),
      "price_change_1h_pct":float(pc.get("h1") or 0),
      "market_cap":pair.get("marketCap"),"fdv":pair.get("fdv"),
      "pair_created_at":pair.get("pairCreatedAt"),
      "top10_holder_pct":top10 if top10 is not None else (percent(sec.get("top_10_holder_rate")) if sec and sec.get("top_10_holder_rate") not in (None,"") else None),
      "dev_holder_pct":creator,
      "mint_authority_active":mint_active,"freeze_authority_active":freeze_active,
      "sellable":sellable if sec else None,
      "liquidity_locked":locked,
      "holder_growth_1h_pct":0.0,"higher_highs":float(pc.get("m5") or 0)>0 and float(pc.get("h1") or 0)>0,
      "narrative_momentum":bool((pair.get("boosts") or {}).get("active")),
      "security_source":"goplus" if sec else "unavailable",
      "observed_at":datetime.now(timezone.utc).isoformat()
    }

def scan(limit=30):
    conn=init_db(); n=0
    for p in latest_solana(limit):
        try:
            pair=best_pair(p["tokenAddress"])
            if not pair: continue
            row=normalize(p,pair,goplus(p["tokenAddress"]))
            result=evaluate(row); record(conn,row,result); n+=1
            print(json.dumps({**result,"address":row["token_address"],"liquidity_usd":row["liquidity_usd"]}))
        except Exception as e:
            print(f"::warning::meme discovery error {p.get('tokenAddress')}: {e}")
    conn.close(); print(f"memecoin shadow observations: {n}"); return n

def self_test():
    p={"tokenAddress":"abc"}
    pair={"baseToken":{"symbol":"MEME"},"priceUsd":"0.01","liquidity":{"usd":100000},
          "volume":{"h1":60000,"h6":120000},"priceChange":{"m5":2,"h1":20},
          "txns":{"h1":{"buys":150,"sells":100}},"boosts":{"active":1}}
    sec={"lp_holders":[{"is_locked":"1"}],"holders":[{"percent":"0.20"},{"percent":"0.10"}],
         "mintable":{"status":"0"},"freezable":{"status":"0"},"non_transferable":"0","creator_percent":"0.03"}
    x=normalize(p,pair,sec)
    assert x["liquidity_locked"] and x["sellable"] and not x["mint_authority_active"]
    assert x["top10_holder_pct"]==30.0 and x["makers"]==250
    print("memecoin discovery self-test passed")

if __name__=="__main__":
    ap=argparse.ArgumentParser(); ap.add_argument("--limit",type=int,default=30); ap.add_argument("--self-test",action="store_true")
    a=ap.parse_args(); self_test() if a.self_test else scan(a.limit)
