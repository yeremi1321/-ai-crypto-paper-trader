"""Storage retention for the memecoin research database. Never touches trades or predictions.

The free Render Postgres has 1 GB. The collector writes a full discovery payload every 30 seconds and a price
snapshot per tracked token, so without pruning it filled the disk in about five days and the database was
suspended. This keeps what the research needs and drops the bulk:

  * price snapshots older than SNAPSHOT_DAYS, except for tokens the bot paper-traded (kept TRADED_SNAPSHOT_DAYS)
  * the full discovery payload (raw_json) of repeat sightings older than PAYLOAD_DAYS; a token's FIRST sighting and
    any sighting the bot traded keep theirs (the candidate study, predictor and trade analysis read those)
  * the duplicate payload copy in the decision ledger, except for traded candidates

Paper trades, predictions, predictor state, outcomes and ledger decisions are never deleted. When the database
passes SOFT_LIMIT_BYTES the windows shrink (tight mode) so it can never fill up again.
"""
from datetime import datetime, timedelta, timezone

SNAPSHOT_DAYS = 4
TRADED_SNAPSHOT_DAYS = 30
PAYLOAD_DAYS = 2
SOFT_LIMIT_BYTES = 700 * 1024 * 1024
TIGHT = {"snapshot_days": 1, "traded_snapshot_days": 7, "payload_days": 0.5}
INTERVAL_SECONDS = 3600


def _pg(c):
    return c.__class__.__module__.startswith("psycopg")


def _q(c, sql):
    return sql.replace("?", "%s") if _pg(c) else sql


def db_size_bytes(c):
    try:
        if _pg(c):
            return int(c.execute("SELECT pg_database_size(current_database())").fetchone()[0])
        pages = c.execute("PRAGMA page_count").fetchone()[0]
        return int(pages * c.execute("PRAGMA page_size").fetchone()[0])
    except Exception:
        c.rollback()
        return None


def _tables(c):
    if _pg(c):
        return {r[0] for r in c.execute("SELECT tablename FROM pg_tables WHERE schemaname='public'")}
    return {r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")}


def run(c, now=None):
    """Prune once. Returns what was removed plus the database size before and after."""
    now = now or datetime.now(timezone.utc)
    before = db_size_bytes(c)
    tight = before is not None and before > SOFT_LIMIT_BYTES
    snap_days, traded_days, payload_days = ((TIGHT["snapshot_days"], TIGHT["traded_snapshot_days"],
                                             TIGHT["payload_days"]) if tight else
                                            (SNAPSHOT_DAYS, TRADED_SNAPSHOT_DAYS, PAYLOAD_DAYS))
    cutoff = lambda days: (now - timedelta(days=days)).isoformat()
    tables = _tables(c)
    out = {"tight_mode": tight, "snapshots_deleted": 0, "payloads_cleared": 0, "ledger_payloads_cleared": 0}
    traded_tokens = "SELECT token_address FROM meme_paper_trades WHERE token_address IS NOT NULL"
    traded_ids = "SELECT candidate_id FROM meme_paper_trades WHERE candidate_id IS NOT NULL"
    if "meme_price_snapshots" in tables:
        out["snapshots_deleted"] += c.execute(_q(c, f"""DELETE FROM meme_price_snapshots WHERE observed_at<?
            AND token_address NOT IN ({traded_tokens})"""), (cutoff(snap_days),)).rowcount
        out["snapshots_deleted"] += c.execute(_q(c, "DELETE FROM meme_price_snapshots WHERE observed_at<?"),
                                              (cutoff(traded_days),)).rowcount
        c.commit()
    if "meme_candidates" in tables:
        out["payloads_cleared"] = c.execute(_q(c, f"""UPDATE meme_candidates SET raw_json=NULL
            WHERE seen_at<? AND raw_json IS NOT NULL AND id NOT IN ({traded_ids})
            AND id NOT IN (SELECT MIN(id) FROM meme_candidates WHERE token_address IS NOT NULL GROUP BY token_address)"""),
                                            (cutoff(payload_days),)).rowcount
        c.commit()
    if "meme_decision_ledger" in tables:
        out["ledger_payloads_cleared"] = c.execute(_q(c, f"""UPDATE meme_decision_ledger SET raw_json=NULL
            WHERE recorded_at<? AND raw_json IS NOT NULL AND candidate_id NOT IN ({traded_ids})"""),
                                                   (cutoff(min(payload_days, 1)),)).rowcount
        c.commit()
    out["size_mb_before"] = None if before is None else round(before / 2 ** 20, 1)
    after = db_size_bytes(c)  # Postgres reuses freed space rather than shrinking, so this may not drop at once
    out["size_mb_after"] = None if after is None else round(after / 2 ** 20, 1)
    return out
