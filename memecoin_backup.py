"""Backup and restore of the memecoin results that matter. Paper/research only.

On 2026-09-30 the free Render Postgres filled up and had to be deleted, losing ~1,550 paper trades, ~8,000
predictions and the predictor's learned state. This keeps a small copy in the repo instead:

  export(c)          -> dict of paper trades, predictions and predictor state (served at /backup-export; a nightly
                        GitHub workflow saves it gzipped to BACKUP_PATH)
  restore_if_fresh() -> on collector start, if the database has no discoveries yet and BACKUP_PATH exists, load it

Bulk research data (price snapshots, discovery payloads) is not backed up; retention prunes it anyway. Prediction
features are kept for FEATURE_DAYS, enough for the predictor's backfill window.
"""
import gzip
import json
import os
from datetime import datetime, timedelta, timezone

BACKUP_PATH = "backups/memecoin_backup.json.gz"
FEATURE_DAYS = 7
FORMAT = 1


def _pg(c):
    return c.__class__.__module__.startswith("psycopg")


def _q(c, sql):
    return sql.replace("?", "%s") if _pg(c) else sql


def _columns(c, table):
    if _pg(c):
        return [r[0] for r in c.execute(_q(c, """SELECT column_name FROM information_schema.columns
            WHERE table_name=? ORDER BY ordinal_position"""), (table,))]
    return [r[1] for r in c.execute(f"PRAGMA table_info({table})")]


def _rows(c, table, where=""):
    cols = _columns(c, table)
    if not cols:
        return {"columns": [], "rows": []}
    return {"columns": cols, "rows": [list(r) for r in c.execute(f"SELECT {','.join(cols)} FROM {table} {where}")]}


def export(c, now=None):
    import memecoin_paper
    import memecoin_predictor
    now = now or datetime.now(timezone.utc)
    memecoin_paper.migrate(c)
    memecoin_predictor.init(c)
    preds = _rows(c, "meme_predictions", "ORDER BY id")
    if "features_json" in preds["columns"]:
        fi, pi = preds["columns"].index("features_json"), preds["columns"].index("predicted_at")
        keep_after = (now - timedelta(days=FEATURE_DAYS)).isoformat()
        for r in preds["rows"]:
            if (r[pi] or "") < keep_after:
                r[fi] = None
    state = c.execute("SELECT state_json FROM meme_predictor_state WHERE id=1").fetchone()
    return {"format": FORMAT, "exported_at": now.isoformat(), "mode": "paper_trading",
            "paper_trades": _rows(c, "meme_paper_trades", "ORDER BY id"),
            "predictions": preds,
            "predictor_state": state[0] if state else None}


def _insert(c, table, block):
    have = set(_columns(c, table))
    idx = [i for i, col in enumerate(block["columns"]) if col in have]
    if not idx or not block["rows"]:
        return 0
    cols = [block["columns"][i] for i in idx]
    sql = f"INSERT INTO {table}({','.join(cols)}) VALUES({','.join('?' * len(cols))})"
    c.cursor().executemany(_q(c, sql), [[r[i] for i in idx] for r in block["rows"]])
    return len(block["rows"])


def restore(c, data):
    """Load a backup into an empty database. Returns counts. Refuses if discoveries already exist."""
    import memecoin_paper
    import memecoin_predictor
    memecoin_paper.migrate(c)
    memecoin_predictor.init(c)
    if c.execute("SELECT COUNT(*) FROM meme_candidates").fetchone()[0]:
        raise RuntimeError("refusing to restore into a database that already has discoveries")
    trades, preds = dict(data["paper_trades"]), data["predictions"]
    if "status" in trades["columns"]:  # an open position in a day-old backup cannot be priced honestly
        si = trades["columns"].index("status")
        trades["rows"] = [r for r in trades["rows"] if r[si] != "OPEN"]
    # Stub discovery rows keep candidate ids reserved, so new discoveries cannot collide with restored ids.
    ids = set()
    for block in (trades, preds):
        if "candidate_id" in block["columns"]:
            i = block["columns"].index("candidate_id")
            ids |= {r[i] for r in block["rows"] if r[i] is not None}
    if ids:
        c.cursor().executemany(_q(c, "INSERT INTO meme_candidates(id,seen_at,version) VALUES(?,?,?)"),
                               [(i, data["exported_at"], "RESTORED_STUB") for i in sorted(ids)])
    out = {"paper_trades": _insert(c, "meme_paper_trades", trades),
           "predictions": _insert(c, "meme_predictions", preds), "candidate_stubs": len(ids)}
    if data.get("predictor_state"):
        c.execute(_q(c, "INSERT INTO meme_predictor_state(id,updated_at,state_json) VALUES(1,?,?)"),
                  (data["exported_at"], data["predictor_state"]))
    if _pg(c):
        for table in ("meme_candidates", "meme_paper_trades", "meme_predictions"):
            c.execute(f"""SELECT setval(pg_get_serial_sequence('{table}','id'),
                GREATEST((SELECT COALESCE(MAX(id),0) FROM {table}),1))""")
    c.commit()
    return out


def restore_if_fresh(c, path=BACKUP_PATH):
    if not os.path.exists(path) or c.execute("SELECT COUNT(*) FROM meme_candidates").fetchone()[0]:
        return None
    with gzip.open(path, "rt") as f:
        return restore(c, json.load(f))
