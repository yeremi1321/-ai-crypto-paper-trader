"""Research-only crypto news context collector.

Uses public RSS feeds, stores timestamped headlines and deterministic asset/event
tags. It never changes V5 entries, exits, sizing, or risk.
"""
import argparse, hashlib, re, sqlite3
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
import requests
import xml.etree.ElementTree as ET

DB="paper_trader_v4.db"
VERSION="NEWS_CONTEXT_V1"
FEEDS=[
 ("CoinDesk","https://www.coindesk.com/arc/outboundfeeds/rss/"),
 ("Cointelegraph","https://cointelegraph.com/rss"),
]
ASSETS={
 "BTC":["bitcoin","btc"],"ETH":["ethereum","ether","eth"],"SOL":["solana","sol"],
 "DOGE":["dogecoin","doge"],"SHIB":["shiba inu","shib"],"XRP":["xrp","ripple"],
 "ADA":["cardano","ada"],"AVAX":["avalanche","avax"],"LINK":["chainlink"],
}
EVENTS={
 "SECURITY":["hack","exploit","breach","stolen","vulnerability"],
 "LISTING":["listing","listed","delisting","delisted"],
 "REGULATION":["regulation","regulator","sec ","cftc","lawsuit","court"],
 "ETF":[" etf","exchange-traded fund"],
 "OUTAGE":["outage","halt","downtime"],
 "TOKEN_UNLOCK":["token unlock","unlocking"],
}
POS=("approval","approved","launch","surge","record high","partnership","adoption")
NEG=("hack","exploit","breach","lawsuit","delist","outage","collapse","stolen")

def init_db(path=DB):
 c=sqlite3.connect(path)
 c.execute("""CREATE TABLE IF NOT EXISTS news_context(
 id INTEGER PRIMARY KEY, news_id TEXT UNIQUE, collected_at TEXT, published_at TEXT,
 source TEXT, title TEXT, url TEXT, assets TEXT, event_type TEXT, sentiment TEXT,
 version TEXT)"""); c.commit(); return c

def classify(title):
 t=" "+title.lower()+" "
 assets=[a for a,words in ASSETS.items() if any(re.search(r"(?<![a-z0-9])"+re.escape(w)+r"(?![a-z0-9])",t) for w in words)]
 events=[k for k,words in EVENTS.items() if any(w in t for w in words)]
 p=sum(w in t for w in POS); n=sum(w in t for w in NEG)
 sentiment="POSITIVE" if p>n else "NEGATIVE" if n>p else "NEUTRAL"
 return assets,events,sentiment

def parse_date(v):
 try: return parsedate_to_datetime(v).astimezone(timezone.utc).isoformat()
 except Exception: return None

def fetch_feed(source,url):
 r=requests.get(url,timeout=20,headers={"User-Agent":"ai-crypto-paper-trader/news-context-v1"})
 r.raise_for_status(); root=ET.fromstring(r.content); out=[]
 for item in root.findall(".//item")[:50]:
  title=(item.findtext("title") or "").strip(); link=(item.findtext("link") or "").strip()
  if not title: continue
  pub=parse_date(item.findtext("pubDate") or "")
  nid=hashlib.sha256((source+"|"+link+"|"+title).encode()).hexdigest()
  assets,events,sentiment=classify(title)
  out.append((nid,pub,source,title,link,",".join(assets),",".join(events),sentiment))
 return out

def collect(path=DB):
 conn=init_db(path); now=datetime.now(timezone.utc).isoformat(); added=0
 for source,url in FEEDS:
  try:
   for x in fetch_feed(source,url):
    cur=conn.execute("""INSERT OR IGNORE INTO news_context
    (news_id,collected_at,published_at,source,title,url,assets,event_type,sentiment,version)
    VALUES(?,?,?,?,?,?,?,?,?,?)""",(x[0],now,*x[1:],VERSION)); added+=cur.rowcount
   conn.commit()
  except Exception as e: print(f"::warning::News feed unavailable {source}: {e}")
 conn.close(); print(f"news context added: {added}"); return added

def self_test():
 a,e,s=classify("Bitcoin ETF approved after SEC review")
 assert "BTC" in a and "ETF" in e and "REGULATION" in e and s=="POSITIVE"
 a,e,s=classify("Solana outage follows exploit")
 assert "SOL" in a and "OUTAGE" in e and "SECURITY" in e and s=="NEGATIVE"
 print("news context self-test passed")

if __name__=="__main__":
 p=argparse.ArgumentParser(); p.add_argument("--self-test",action="store_true"); a=p.parse_args()
 self_test() if a.self_test else collect()
