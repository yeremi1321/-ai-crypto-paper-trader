"""Always-on adaptive memecoin research collector.

Paper/research only. No real orders. Runs discovery every 30 seconds and refreshes
recent candidates/open paper positions every 30 seconds. API calls remain rate-limited.
Exposes a tiny HTTP health endpoint so it can run as a Render web service.
"""
import json, os, sqlite3, threading, time
import requests
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer

from memecoin_discovery import scan
from memecoin_outcomes import run as update_outcomes
from memecoin_paper import run as paper_run

DISCOVERY_SECONDS=float(os.getenv("MEME_DISCOVERY_SECONDS","30"))
REFRESH_SECONDS=float(os.getenv("MEME_REFRESH_SECONDS","30"))
PORT=int(os.getenv("PORT","10000"))
STATE={"started_at":datetime.now(timezone.utc).isoformat(),"cycles":0,"last_discovery":None,"last_refresh":None,"last_error":None,"last_persist":None}
DATABASE_URL=os.getenv("DATABASE_URL","")
PERSIST_SECONDS=float(os.getenv("MEME_PERSIST_SECONDS","30"))

def db_stats():
    out={"observations":0,"eligible":0,"rejected":0,"unique_tokens":0,"snapshots":0,"paper_open":0,"paper_closed":0,"paper_wins":0,"paper_losses":0,"realized_pnl_usd":0.0}
    try:
        c=sqlite3.connect("memecoin_shadow.db")
        out["observations"]=c.execute("select count(*) from meme_candidates").fetchone()[0]
        out["eligible"]=c.execute("select count(*) from meme_candidates where eligible=1").fetchone()[0]
        out["rejected"]=out["observations"]-out["eligible"]
        out["unique_tokens"]=c.execute("select count(distinct token_address) from meme_candidates where token_address is not null").fetchone()[0]
        try: out["snapshots"]=c.execute("select count(*) from meme_price_snapshots").fetchone()[0]
        except sqlite3.OperationalError: pass
        out["paper_open"]=c.execute("select count(*) from meme_paper_trades where status='OPEN'").fetchone()[0]
        out["paper_closed"]=c.execute("select count(*) from meme_paper_trades where status='CLOSED'").fetchone()[0]
        out["paper_wins"]=c.execute("select count(*) from meme_paper_trades where status='CLOSED' and net_pnl_usd>0").fetchone()[0]
        out["paper_losses"]=out["paper_closed"]-out["paper_wins"]
        try: out["realized_pnl_usd"]=round(float(c.execute("select coalesce(sum(net_pnl_usd),0) from meme_paper_trades where status='CLOSED'").fetchone()[0] or 0),2)
        except sqlite3.OperationalError: pass
        c.close()
    except Exception as e: out["stats_error"]=repr(e)
    return out

def persist_snapshot():
    """Persist the collector's SQLite state to the shared database service.

    DATABASE_URL is treated as a private endpoint. The database stores one
    authoritative SQLite snapshot as binary data; this keeps the existing,
    well-tested SQLite trading code unchanged while making state durable and
    shareable with the dashboard.
    """
    if not DATABASE_URL:
        return
    with open("memecoin_shadow.db","rb") as fh:
        data=fh.read()
    r=requests.put(DATABASE_URL.rstrip("/")+"/meme-snapshot",
                   data=data,headers={"Content-Type":"application/octet-stream"},timeout=20)
    r.raise_for_status()
    STATE["last_persist"]=datetime.now(timezone.utc).isoformat()

def restore_snapshot():
    if not DATABASE_URL:
        return
    try:
        r=requests.get(DATABASE_URL.rstrip("/")+"/meme-snapshot",timeout=20)
        if r.status_code==200 and r.content:
            with open("memecoin_shadow.db","wb") as fh: fh.write(r.content)
    except Exception as e:
        print(f"::warning::snapshot restore skipped: {e}",flush=True)

def collector():
    next_discovery=0.0; next_refresh=0.0; next_persist=0.0
    while True:
        now=time.monotonic()
        try:
            if now>=next_discovery:
                scan(int(os.getenv("MEME_DISCOVERY_LIMIT","30")))
                STATE["last_discovery"]=datetime.now(timezone.utc).isoformat()
                next_discovery=now+DISCOVERY_SECONDS
            if now>=next_refresh:
                update_outcomes()
                paper_run()
                STATE["last_refresh"]=datetime.now(timezone.utc).isoformat()
                next_refresh=now+REFRESH_SECONDS
            STATE["cycles"]+=1
            STATE["last_error"]=None
        except Exception as e:
            STATE["last_error"]=repr(e)
            print(f"::warning::fast collector cycle failed: {e}",flush=True)
        time.sleep(max(1,min(5,DISCOVERY_SECONDS,REFRESH_SECONDS)))

class Health(BaseHTTPRequestHandler):
    def do_GET(self):
        body=json.dumps({"status":"ok","mode":"paper_trading","discovery_seconds":DISCOVERY_SECONDS,
                         "refresh_seconds":REFRESH_SECONDS,**STATE,**db_stats()}).encode()
        self.send_response(200); self.send_header("Content-Type","application/json")
        self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self,fmt,*args): pass

if __name__=="__main__":
    if DISCOVERY_SECONDS<30 or REFRESH_SECONDS<30:
        raise SystemExit("Refusing intervals below 30 seconds to reduce upstream API/rate-limit risk.")
    restore_snapshot()\n    threading.Thread(target=collector,daemon=True).start()
    print(f"fast memecoin collector: discovery={DISCOVERY_SECONDS}s refresh={REFRESH_SECONDS}s",flush=True)
    HTTPServer(("0.0.0.0",PORT),Health).serve_forever()
