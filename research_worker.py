"""Background research worker. Read-only; never trades.

The research pages got slow (the candidate study took over a minute), so instead of computing on request,
this worker recomputes every study on a timer in one background thread and the pages serve the latest
finished result instantly. Jobs run one at a time, spaced out, to keep load on the service and database low.

Paths served: /paper-analysis, /paper-analysis-trades, /paper-exit-replay, /paper-candidate-study,
/paper-runner-study
"""
import threading
import time
from datetime import datetime, timezone

INTERVAL_SECONDS = 15 * 60     # full refresh cadence
GAP_SECONDS = 20               # pause between jobs within a refresh
STARTUP_DELAY_SECONDS = 60     # let trading threads settle after a deploy first

_results = {}
_lock = threading.Lock()
_started = False


def _now():
    return datetime.now(timezone.utc).isoformat()


def default_jobs():
    """name -> callable returning {path: payload}. Imports are lazy so tests can inject their own jobs."""
    from memecoin_shadow import init_db
    import memecoin_entry_analysis, memecoin_exit_replay, memecoin_candidate_study, memecoin_runner_study

    def with_conn(fn):
        def run():
            c = init_db()
            try:
                return fn(c)
            finally:
                c.close()
        return run

    def analysis(c):
        summary, trades = memecoin_entry_analysis.run(c, _now())
        return {"/paper-analysis": summary, "/paper-analysis-trades": trades}

    return {
        "analysis": with_conn(analysis),
        "exit_replay": with_conn(lambda c: {"/paper-exit-replay": memecoin_exit_replay.run(c, _now())}),
        "candidate_study": with_conn(lambda c: {"/paper-candidate-study": memecoin_candidate_study.run(c, _now())}),
        "runner_study": with_conn(lambda c: {"/paper-runner-study": memecoin_runner_study.run(c, _now())}),
    }


PATHS = {"/paper-analysis", "/paper-analysis-trades", "/paper-exit-replay", "/paper-candidate-study",
         "/paper-runner-study"}


def run_once(jobs):
    for name, job in jobs.items():
        started = time.monotonic()
        try:
            out = job()
            secs = round(time.monotonic() - started, 1)
            with _lock:
                for path, payload in out.items():
                    _results[path] = {"payload": payload, "computed_at": _now(), "compute_seconds": secs}
        except Exception as e:
            # Keep serving the last good result; the next refresh tries again.
            print(f"::warning::research job {name} failed: {type(e).__name__}: {e}", flush=True)
        yield name


def _loop(jobs, interval, gap, startup_delay, stop):
    if stop.wait(startup_delay):
        return
    while not stop.is_set():
        for _ in run_once(jobs):
            if stop.wait(gap):
                return
        if stop.wait(interval):
            return


def start(jobs=None, interval=INTERVAL_SECONDS, gap=GAP_SECONDS, startup_delay=STARTUP_DELAY_SECONDS, stop=None):
    global _started
    if _started:
        return None
    _started = True
    stop = stop or threading.Event()
    t = threading.Thread(target=_loop, args=(jobs or default_jobs(), interval, gap, startup_delay, stop),
                         daemon=True, name="research-worker")
    t.start()
    return t


def get(path):
    """(payload, http_code). Serves the last finished result instantly, with freshness info added to dict payloads."""
    with _lock:
        r = _results.get(path)
    if r is None:
        return {"status": "warming_up", "detail": "research results are computed in the background; retry in a few minutes"}, 503
    payload = r["payload"]
    if isinstance(payload, dict):
        payload = dict(payload)
        payload["_computed_at"] = r["computed_at"]
        payload["_compute_seconds"] = r["compute_seconds"]
    return payload, 200
