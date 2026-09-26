"""Always-on adaptive memecoin research collector.

Paper/research only. No real orders. Runs discovery and recent-candidate refresh
every 30 seconds. An independent thread checks open paper positions every 10
seconds, so slow discovery cannot delay stop/target/time exits.
Exposes a tiny HTTP health endpoint so it can run as a Render web service.
"""
import json, os, sqlite3, threading, time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer

from memecoin_discovery import scan
from memecoin_outcomes import run as update_outcomes
from memecoin_paper import run as paper_run
from memecoin_shadow import init_db
from live_two_second_watcher import run as run_paper_watcher
from memecoin_trade_analysis import run as analyze_paper_history
import memecoin_entry_analysis
import memecoin_exit_replay

DISCOVERY_SECONDS=float(os.getenv("MEME_DISCOVERY_SECONDS","30"))
REFRESH_SECONDS=float(os.getenv("MEME_REFRESH_SECONDS","30"))
OPEN_REFRESH_SECONDS=10.0
PORT=int(os.getenv("PORT","10000"))
STATE={"started_at":datetime.now(timezone.utc).isoformat(),"cycles":0,"last_discovery":None,"last_refresh":None,"last_error":None,
       "last_open_refresh":None,"open_refresh_cycles":0,"last_open_error":None}
ANALYSIS_CACHE_SECONDS=120.0
_ANALYSIS={"at":0.0,"summary":None,"trades":None}
_ANALYSIS_LOCK=threading.Lock()
REPLAY_CACHE_SECONDS=300.0
_REPLAY={"at":0.0,"result":None}
_REPLAY_LOCK=threading.Lock()

def db_stats():
    out={"db_connected":False,"observations":0,"eligible":0,"rejected":0,"unique_tokens":0,"snapshots":0,"paper_open":0,"paper_closed":0,"paper_wins":0,"paper_losses":0,"realized_pnl_usd":0.0}
    try:
        c=init_db()
        out["db_connected"]=True
        out["observations"]=c.execute("select count(*) from meme_candidates").fetchone()[0]
        out["eligible"]=c.execute("select count(*) from meme_candidates where eligible=1").fetchone()[0]
        out["rejected"]=out["observations"]-out["eligible"]
        out["unique_tokens"]=c.execute("select count(distinct token_address) from meme_candidates where token_address is not null").fetchone()[0]
        try: out["snapshots"]=c.execute("select count(*) from meme_price_snapshots").fetchone()[0]
        except Exception: pass
        out["paper_open"]=c.execute("select count(*) from meme_paper_trades where status='OPEN'").fetchone()[0]
        out["paper_closed"]=c.execute("select count(*) from meme_paper_trades where status='CLOSED'").fetchone()[0]
        out["paper_wins"]=c.execute("select count(*) from meme_paper_trades where status='CLOSED' and net_pnl_usd>0").fetchone()[0]
        out["paper_losses"]=out["paper_closed"]-out["paper_wins"]
        try: out["realized_pnl_usd"]=round(float(c.execute("select coalesce(sum(net_pnl_usd),0) from meme_paper_trades where status='CLOSED'").fetchone()[0] or 0),2)
        except Exception: pass
        c.close()
    except Exception as e:
        out["db_connected"]=False
        out["stats_error"]=repr(e)
    return out

def paper_summary():
    """Small read-only response for the separate Streamlit dashboard."""
    c=init_db()
    try:
        def rows(query):
            cur=c.execute(query)
            names=[col[0] for col in cur.description]
            return [dict(zip(names,row)) for row in cur.fetchall()]
        totals=rows("""SELECT COUNT(*) FILTER (WHERE status='OPEN') AS paper_open,
            COUNT(*) FILTER (WHERE status='CLOSED') AS paper_closed,
            COUNT(*) FILTER (WHERE status='CLOSED' AND net_pnl_usd>0) AS paper_wins,
            COALESCE(SUM(net_pnl_usd) FILTER (WHERE status='CLOSED'),0) AS realized_pnl_usd,
            MAX(net_pnl_usd) FILTER (WHERE status='CLOSED') AS best_trade,
            AVG(net_return_pct) FILTER (WHERE status='CLOSED') AS avg_return,
            AVG(mfe_pct) FILTER (WHERE status='CLOSED') AS avg_mfe,
            AVG(mae_pct) FILTER (WHERE status='CLOSED') AS avg_mae
            FROM meme_paper_trades""") if os.getenv("DATABASE_URL") else rows("""SELECT
            SUM(CASE WHEN status='OPEN' THEN 1 ELSE 0 END) AS paper_open,
            SUM(CASE WHEN status='CLOSED' THEN 1 ELSE 0 END) AS paper_closed,
            SUM(CASE WHEN status='CLOSED' AND net_pnl_usd>0 THEN 1 ELSE 0 END) AS paper_wins,
            COALESCE(SUM(CASE WHEN status='CLOSED' THEN net_pnl_usd ELSE 0 END),0) AS realized_pnl_usd,
            MAX(CASE WHEN status='CLOSED' THEN net_pnl_usd END) AS best_trade,
            AVG(CASE WHEN status='CLOSED' THEN net_return_pct END) AS avg_return,
            AVG(CASE WHEN status='CLOSED' THEN mfe_pct END) AS avg_mfe,
            AVG(CASE WHEN status='CLOSED' THEN mae_pct END) AS avg_mae
            FROM meme_paper_trades""")
        open_rows=rows("""SELECT token,opened_at,entry_price,current_price,current_return_pct,mfe_pct,mae_pct
            FROM meme_paper_trades WHERE status='OPEN' ORDER BY id DESC LIMIT 5""")
        recent=rows("""SELECT token,status,opened_at,closed_at,entry_price,current_price,
            exit_price,exit_reason,current_return_pct,net_return_pct,net_pnl_usd,mfe_pct,mae_pct
            FROM meme_paper_trades ORDER BY id DESC LIMIT 300""")
        curve=rows("""SELECT closed_at,net_pnl_usd FROM meme_paper_trades
            WHERE status='CLOSED' ORDER BY closed_at,id""")
        return {"as_of":datetime.now(timezone.utc).isoformat(),"mode":"paper_trading",
                "totals":totals[0],"open_positions":open_rows,"recent_trades":recent,
                "closed_pnl_series":curve}
    finally:
        c.close()

def paper_analysis():
    with _ANALYSIS_LOCK:
        if _ANALYSIS["summary"] is None or time.monotonic()-_ANALYSIS["at"]>ANALYSIS_CACHE_SECONDS:
            c=init_db()
            try:
                summary,trades=memecoin_entry_analysis.run(c,datetime.now(timezone.utc).isoformat())
            finally:
                c.close()
            _ANALYSIS.update(at=time.monotonic(),summary=summary,trades=trades)
        return _ANALYSIS["summary"],_ANALYSIS["trades"]

def exit_replay():
    """Read-only exit-rule replay, cached for five minutes."""
    with _REPLAY_LOCK:
        if _REPLAY["result"] is None or time.monotonic()-_REPLAY["at"]>REPLAY_CACHE_SECONDS:
            c=init_db()
            try:
                result=memecoin_exit_replay.run(c,datetime.now(timezone.utc).isoformat())
            finally:
                c.close()
            _REPLAY.update(at=time.monotonic(),result=result)
        return _REPLAY["result"]

def collector(stop=None):
    next_discovery=0.0; next_refresh=0.0
    while not (stop and stop.is_set()):
        try:
            now=time.monotonic()
            if now>=next_discovery:
                next_discovery=now+DISCOVERY_SECONDS
                scan(int(os.getenv("MEME_DISCOVERY_LIMIT","30")))
                STATE["last_discovery"]=datetime.now(timezone.utc).isoformat()
            now=time.monotonic()
            if now>=next_refresh:
                next_refresh=now+REFRESH_SECONDS
                update_outcomes(exclude_open=True)
                STATE["last_refresh"]=datetime.now(timezone.utc).isoformat()
            STATE["cycles"]+=1
            STATE["last_error"]=None
        except Exception as e:
            STATE["last_error"]=repr(e)
            print(f"::warning::fast collector cycle failed: {e}",flush=True)
        time.sleep(1)

def open_position_watcher(stop=None,interval=None):
    """Refresh and close open paper positions independently of discovery."""
    interval=OPEN_REFRESH_SECONDS if interval is None else interval
    next_run=0.0
    while not (stop and stop.is_set()):
        now=time.monotonic()
        if now>=next_run:
            next_run=now+interval
            try:
                update_outcomes(only_open=True)
                paper_run()
                STATE["last_open_refresh"]=datetime.now(timezone.utc).isoformat()
                STATE["open_refresh_cycles"]+=1
                STATE["last_open_error"]=None
            except Exception as e:
                STATE["last_open_error"]=repr(e)
                print(f"::warning::open-position refresh failed: {e}",flush=True)
        time.sleep(max(0.0,min(1.0,next_run-time.monotonic())))

class Health(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path=="/paper-exit-replay":
            try:
                payload=exit_replay(); code=200
            except Exception as e:
                payload={"status":"unavailable","error":type(e).__name__}; code=503
        elif self.path in ("/paper-analysis","/paper-analysis-trades"):
            try:
                summary,trades=paper_analysis()
                payload=summary if self.path=="/paper-analysis" else trades
                code=200
            except Exception as e:
                payload={"status":"unavailable","error":type(e).__name__}
                code=503
        elif self.path=="/paper-summary":
            try:
                payload=paper_summary()
                code=200
            except Exception as e:
                payload={"status":"unavailable","error":type(e).__name__}
                code=503
        else:
            stats=db_stats()
            payload={"status":"ok" if stats.get("db_connected") else "degraded","mode":"paper_trading","database":"postgres" if os.getenv("DATABASE_URL") else "sqlite","database_connected":stats.get("db_connected",False),"discovery_seconds":DISCOVERY_SECONDS,
                     "refresh_seconds":REFRESH_SECONDS,"open_refresh_seconds":OPEN_REFRESH_SECONDS,**STATE,**stats}
            code=200
        body=json.dumps(payload).encode()
        self.send_response(code); self.send_header("Content-Type","application/json")
        self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self,fmt,*args): pass

if __name__=="__main__":
    if DISCOVERY_SECONDS<30 or REFRESH_SECONDS<30:
        raise SystemExit("Refusing intervals below 30 seconds to reduce upstream API/rate-limit risk.")
    threading.Thread(target=collector,daemon=True,name="meme-collector").start()
    threading.Thread(target=open_position_watcher,daemon=True,name="meme-open-positions").start()
    try:
        analyze_paper_history()
    except Exception as e:
        print(f"::warning::paper history analysis failed: {e}",flush=True)
    threading.Thread(target=run_paper_watcher,daemon=True,name="paper-two-second-watcher").start()
    print(f"fast memecoin collector: discovery={DISCOVERY_SECONDS}s refresh={REFRESH_SECONDS}s open_refresh={OPEN_REFRESH_SECONDS}s",flush=True)
    HTTPServer(("0.0.0.0",PORT),Health).serve_forever()
