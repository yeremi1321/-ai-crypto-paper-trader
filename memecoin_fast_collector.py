"""Always-on adaptive memecoin research collector.

Paper/research only. No real orders. Runs discovery every 30 seconds and refreshes
recent candidates/open paper positions every 30 seconds. API calls remain rate-limited.
Exposes a tiny HTTP health endpoint so it can run as a Render web service.
"""
import json, os, threading, time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer

from memecoin_discovery import scan
from memecoin_outcomes import run as update_outcomes
from memecoin_paper import run as paper_run

DISCOVERY_SECONDS=float(os.getenv("MEME_DISCOVERY_SECONDS","30"))
REFRESH_SECONDS=float(os.getenv("MEME_REFRESH_SECONDS","30"))
PORT=int(os.getenv("PORT","10000"))
STATE={"started_at":datetime.now(timezone.utc).isoformat(),"cycles":0,"last_discovery":None,"last_refresh":None,"last_error":None}

def collector():
    next_discovery=0.0; next_refresh=0.0
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
        body=json.dumps({"status":"ok","mode":"paper_research","discovery_seconds":DISCOVERY_SECONDS,
                         "refresh_seconds":REFRESH_SECONDS,**STATE}).encode()
        self.send_response(200); self.send_header("Content-Type","application/json")
        self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self,fmt,*args): pass

if __name__=="__main__":
    if DISCOVERY_SECONDS<30 or REFRESH_SECONDS<30:
        raise SystemExit("Refusing intervals below 30 seconds to reduce upstream API/rate-limit risk.")
    threading.Thread(target=collector,daemon=True).start()
    print(f"fast memecoin collector: discovery={DISCOVERY_SECONDS}s refresh={REFRESH_SECONDS}s",flush=True)
    HTTPServer(("0.0.0.0",PORT),Health).serve_forever()
