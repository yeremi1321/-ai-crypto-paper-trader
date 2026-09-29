"""Self-learning memecoin outcome predictor. Paper/research only: never trades, never blocks an entry.

Loop, for every discovered token:
  1. PREDICT  - at discovery, estimate the chance that buying now under the live paper rules
                (+20% target, -10% stop, 20-minute max hold, 1% slippage + 0.6% fee each side)
                ends as a net WIN, the chance it ends as a SEVERE LOSS (price gapping through the
                stop, e.g. a rug), and the expected net return from both. The prediction is stored before
                the outcome exists, so it can never peek at the future.
  2. RESOLVE  - once the recorded price path decides the trade (target, stop, or time), store what
                actually happened next to what was predicted.
  3. LEARN    - update an online logistic model from that outcome (predict-then-learn, so every
                recorded score is honest out-of-sample), and write a short "lesson" for confident
                misses naming the signals that misled it.
  4. REPORT   - calibration, learning curve, how its picks would have done versus the bot's own
                paper trades, and data-driven suggestions for what to change. Nothing is promoted
                into the live rules automatically.

Repeated discoveries of the same token within one trade horizon are skipped (they are the same bet),
unless the bot actually opened a paper trade on that observation.
"""
import argparse
import heapq
import json
import math
import random
from datetime import datetime, timedelta, timezone

from memecoin_candidate_study import FEE, SLIP, TP, SL, HORIZON_S, END_TOLERANCE_S, net_return_pct, _pct

VERSION = "MEME_PREDICTOR_V2"
DB = "memecoin_shadow.db"
GRACE_S = 10 * 60             # a path still undecided this long after the horizon is unresolvable
BACKFILL_DAYS = 7              # a fresh model first replays this much history, oldest first
CHUNK = timedelta(hours=6)     # candidates handled per step while catching up on history
WARMUP = 50                    # resolved outcomes before the predictor states an opinion
LEARNING_RATE = 0.1
L2 = 1e-3
PRIOR_WIN_RATE = 0.25
SEVERE_LOSS_PCT = -20.0        # net loss at least twice the planned stop: the price gapped through it
PRIOR_SEVERE_RATE = 0.2
CONFIDENT_MISS = 0.5           # |predicted - actual| at or above this writes a lesson
Z_CLIP = 5.0
TRADED = "PAPER_TRADE_CANDIDATE"

# Pre-registered forward tests. Each rule is fixed before the data that judges it exists and is evaluated only on
# the bot's real paper trades opened after registration, using the chances the predictor recorded before each trade.
# Never edit a rule after registration; add a new one instead. Nothing here changes live trading.
MIN_VERDICT_TRADES = 40
MIN_VERDICT_SKIPPED = 10
BOOTSTRAP_SAMPLES = 1000
HYPOTHESES = [
    {"name": "skip_high_severe_risk",
     "registered_at": "2026-09-28T09:30:00+00:00",
     "motivation": "predictor report 2026-09-28 08:38Z (history re-scored without look-ahead): the bot's riskiest "
                   "quarter of entries (p_severe_loss >= 0.313) averaged -7.2%/trade vs -5.7% for the rest "
                   "(364 vs 1,095 trades)",
     "statement": "Skipping bot entries whose recorded severe-loss chance is >= 31% improves average net return per "
                  "trade over taking every bot entry.",
     "skip_if": {"field": "p_severe_loss", "at_least": 0.31}},
    {"name": "skip_high_severe_risk_fixed_150",
     "registered_at": "2026-09-29T07:00:00+00:00",
     "motivation": "skip_high_severe_risk has no fixed end and is re-judged on every report, so repeatedly checking it "
                   "until it crosses 90% could pass by chance (it read 62% on 55 trades, then 88% on 82). This copy is "
                   "decided exactly once, blind.",
     "statement": "Same rule as skip_high_severe_risk, judged once on exactly the first 150 bot trades opened after "
                  "registration.",
     "skip_if": {"field": "p_severe_loss", "at_least": 0.31},
     # Results stay hidden until all 150 trades have closed; the verdict at that point is final.
     "decide_at_trades": 150},
]


def _f(x, k):
    v = x.get(k)
    if v is None or isinstance(v, str) and not v.strip():
        return None
    try:
        v = float(v)
    except (TypeError, ValueError):
        return None
    return v if math.isfinite(v) else None


def _slog(v):
    return None if v is None else math.copysign(math.log1p(abs(v)), v)


def features(x, eligible=None):
    """Numeric signals known at discovery. Missing fields are left out and treated as average."""
    out = {}

    def put(name, v):
        if v is not None:
            out[name] = float(v)

    liq, vol, cap = _f(x, "liquidity_usd"), _f(x, "volume_1h_usd"), _f(x, "market_cap") or _f(x, "fdv")
    put("log_liquidity", _slog(liq))
    put("log_volume_1h", _slog(vol))
    put("log_makers", _slog(_f(x, "makers")))
    put("log_market_cap", _slog(cap))
    put("volume_accel", _slog(min(_f(x, "volume_accel") or 0, 50)) if _f(x, "volume_accel") is not None else None)
    put("price_change_1h", _slog(_f(x, "price_change_1h_pct")))
    put("turnover", _slog(vol / liq) if vol is not None and liq else None)
    put("liquidity_to_cap", min(liq / cap, 5) if liq is not None and cap else None)
    created, observed = _f(x, "pair_created_at"), x.get("observed_at")
    if created and observed:
        try:
            age_h = (datetime.fromisoformat(observed).timestamp() * 1000 - created) / 3.6e6
            put("log_pair_age_h", math.log1p(max(age_h, 0)))
        except ValueError:
            pass
    for k in ("sol_ret_15m_pct", "sol_ret_60m_pct", "sol_ret_240m_pct", "top10_holder_pct", "dev_holder_pct",
              "attn_boosts_active", "attn_social_count", "attn_has_twitter", "attn_has_telegram",
              "attn_has_website", "attn_tx_accel_5m", "attn_volume_accel_5m", "attn_buy_ratio_5m",
              "attn_buy_ratio_1h"):
        put(k.replace("_pct", ""), _f(x, k))
    put("log_boost_amount", _slog(_f(x, "attn_boost_top_amount")))
    put("log_txns_5m", _slog(_f(x, "attn_txns_5m")))
    for k in ("higher_highs", "narrative_momentum", "mint_authority_active", "freeze_authority_active"):
        if isinstance(x.get(k), bool):
            out[k] = float(x[k])
    out["security_unknown"] = float(x.get("security_source") != "goplus")
    if eligible is not None:
        out["passed_bot_gates"] = float(bool(eligible))
    return out


def _sigmoid(z):
    return 1 / (1 + math.exp(-max(-35.0, min(35.0, z))))


class Model:
    """Online logistic regression on running-standardized features, AdaGrad steps, L2 shrinkage."""

    def __init__(self, state=None, prior=PRIOR_WIN_RATE):
        s = state or {}
        self.w = dict(s.get("w", {}))
        self.bias = s.get("bias", math.log(prior / (1 - prior)))
        self.g2 = dict(s.get("g2", {}))
        self.stats = {k: list(v) for k, v in s.get("stats", {}).items()}  # name -> [count, mean, M2]
        self.n = s.get("n", 0)
        self.wins = s.get("wins", 0)
        self.win_sum = s.get("win_sum", 0.0)
        self.loss_sum = s.get("loss_sum", 0.0)
        self.severe_n = s.get("severe_n", 0)
        self.severe_sum = s.get("severe_sum", 0.0)
        self.cursor_id = s.get("cursor_id", 0)
        # Second head: chance of a severe loss. None until trained (older saved states lack it).
        self.severe = Model(s["severe"], PRIOR_SEVERE_RATE) if "severe" in s else None

    def state(self):
        out = {"w": self.w, "bias": self.bias, "g2": self.g2, "stats": self.stats, "n": self.n,
               "wins": self.wins, "win_sum": self.win_sum, "loss_sum": self.loss_sum,
               "severe_n": self.severe_n, "severe_sum": self.severe_sum, "cursor_id": self.cursor_id}
        if self.severe is not None:
            out["severe"] = self.severe.state()
        return out

    def _z(self, feats):
        z = {}
        for k, v in feats.items():
            cnt, mean, m2 = self.stats.get(k, (0, 0.0, 0.0))
            if cnt < 2:
                continue
            sd = math.sqrt(m2 / (cnt - 1)) or 1.0
            z[k] = max(-Z_CLIP, min(Z_CLIP, (v - mean) / sd))
        return z

    def predict(self, feats):
        """(probability of a net win, {feature: logit contribution})."""
        contrib = {k: self.w.get(k, 0.0) * v for k, v in self._z(feats).items()}
        return _sigmoid(self.bias + sum(contrib.values())), contrib

    def avg_win(self):
        return self.win_sum / self.wins if self.wins else TP - 2 * 100 * (SLIP + FEE)

    def avg_loss(self):
        losses = self.n - self.wins
        return self.loss_sum / losses if losses else -SL - 2 * 100 * (SLIP + FEE)

    def avg_severe(self):
        return self.severe_sum / self.severe_n if self.severe_n else 2 * SEVERE_LOSS_PCT

    def avg_mild_loss(self):
        mild = self.n - self.wins - self.severe_n
        return (self.loss_sum - self.severe_sum) / mild if mild else -SL - 2 * 100 * (SLIP + FEE)

    def expected_return(self, p, p_severe=None):
        if p_severe is None:
            return p * self.avg_win() + (1 - p) * self.avg_loss()
        p_severe = min(p_severe, 1 - p)
        return p * self.avg_win() + p_severe * self.avg_severe() + (1 - p - p_severe) * self.avg_mild_loss()

    def predict_all(self, feats):
        """(p_win, p_severe_loss or None, expected net return %)."""
        p, _ = self.predict(feats)
        ps = self.severe.predict(feats)[0] if self.severe is not None else None
        return p, ps, self.expected_return(p, ps)

    def learn_outcome(self, feats, net):
        """Update both heads and the return tallies from one resolved trade."""
        if self.severe is None:
            self.severe = Model(prior=PRIOR_SEVERE_RATE)
        self.severe.learn(feats, net <= SEVERE_LOSS_PCT, net)
        if net <= SEVERE_LOSS_PCT:
            self.severe_n += 1
            self.severe_sum += net
        self.learn(feats, net > 0, net)

    def learn(self, feats, won, net):
        for k, v in feats.items():  # Welford running mean/variance
            cnt, mean, m2 = self.stats.get(k, (0, 0.0, 0.0))
            cnt += 1
            d = v - mean
            mean += d / cnt
            self.stats[k] = [cnt, mean, m2 + d * (v - mean)]
        p, _ = self.predict(feats)
        err = p - (1.0 if won else 0.0)
        for k, z in self._z(feats).items():
            g = err * z + L2 * self.w.get(k, 0.0)
            self.g2[k] = self.g2.get(k, 0.0) + g * g
            self.w[k] = self.w.get(k, 0.0) - LEARNING_RATE * g / math.sqrt(self.g2[k] + 1e-8)
        self.g2["__bias__"] = self.g2.get("__bias__", 0.0) + err * err
        self.bias -= LEARNING_RATE * err / math.sqrt(self.g2["__bias__"] + 1e-8)
        self.n += 1
        if won:
            self.wins += 1
            self.win_sum += net
        else:
            self.loss_sum += net


def outcome(entry, path, window_closed):
    """Live paper rule on [(secs, price)], same semantics as memecoin_candidate_study.simulate_live.

    Returns (reason, net_return_pct, max_up_pct, decided_at_secs) or None while undecided. The
    'last quote near the horizon' fallback only applies once no later quote can still arrive."""
    max_up = 0.0
    for t, p in path:
        if t > HORIZON_S + END_TOLERANCE_S:
            break
        ret = _pct(entry, p)
        max_up = max(max_up, ret)
        if ret <= -SL:
            return "STOP", net_return_pct(entry, p), max_up, t
        if ret >= TP:
            return "TARGET", net_return_pct(entry, p), max_up, t
        if t >= HORIZON_S:
            return "TIME", net_return_pct(entry, p), max_up, t
    inside = [s for s in path if s[0] <= HORIZON_S + END_TOLERANCE_S]
    if window_closed and inside and inside[-1][0] >= HORIZON_S - END_TOLERANCE_S:
        t, p = inside[-1]
        return "TIME", net_return_pct(entry, p), max_up, t
    return None


def _blame(contrib, happened, top=2):
    wrong = sorted(((v, k) for k, v in contrib.items() if (v > 0) != happened and v), key=lambda t: -abs(t[0]))[:top]
    return ", ".join(f"{k} ({v:+.2f})" for v, k in wrong) or "the base rate alone"


def lesson(p, won, reason, net, contrib, p_severe=None, severe_contrib=None):
    """One sentence naming what misled a confident miss (win call, or a severe loss it did not see coming)."""
    out = []
    if abs(p - (1.0 if won else 0.0)) >= CONFIDENT_MISS:
        said = "win" if not won else "lose"
        out.append(f"Predicted {p:.0%} win but it ended {reason} ({net:+.1f}%). Pushed toward '{said}' mostly by "
                   f"{_blame(contrib, won)}; those weights were corrected by this outcome.")
    if p_severe is not None and net <= SEVERE_LOSS_PCT and p_severe < 1 - CONFIDENT_MISS:
        out.append(f"Severe loss ({net:+.1f}%) it rated only {p_severe:.0%} likely. Looked safe mostly because of "
                   f"{_blame(severe_contrib or {}, True)}.")
    return " ".join(out) or None


# ---------------------------------------------------------------- storage

def _pg(c):
    return c.__class__.__module__.startswith("psycopg")


def _q(c, sql):
    return sql.replace("?", "%s") if _pg(c) else sql


def init(c):
    real = "DOUBLE PRECISION" if _pg(c) else "REAL"
    key = "BIGSERIAL PRIMARY KEY" if _pg(c) else "INTEGER PRIMARY KEY"
    c.execute(f"""CREATE TABLE IF NOT EXISTS meme_predictions(id {key},candidate_id BIGINT UNIQUE,token TEXT,
        token_address TEXT,predicted_at TEXT,model_version TEXT,model_updates INTEGER,entry_price {real},
        p_win {real},expected_net_return_pct {real},would_trade INTEGER,bot_decision TEXT,features_json TEXT,
        status TEXT,resolved_at TEXT,actual_reason TEXT,actual_net_return_pct {real},actual_max_up_pct {real},
        won INTEGER,brier {real},lesson TEXT)""")
    added = {"p_severe_loss": real, "severe_loss": "INTEGER", "brier_severe": real}
    if _pg(c):
        for name, typ in added.items():
            c.execute(f"ALTER TABLE meme_predictions ADD COLUMN IF NOT EXISTS {name} {typ}")
    else:
        cols = {r[1] for r in c.execute("PRAGMA table_info(meme_predictions)")}
        for name, typ in added.items():
            if name not in cols:
                c.execute(f"ALTER TABLE meme_predictions ADD COLUMN {name} {typ}")
    c.execute("CREATE INDEX IF NOT EXISTS meme_predictions_status ON meme_predictions(status, predicted_at)")
    c.execute("CREATE TABLE IF NOT EXISTS meme_predictor_state(id INTEGER PRIMARY KEY,updated_at TEXT,state_json TEXT)")
    c.commit()
    try:  # resolution reads snapshots by time window
        c.execute("CREATE INDEX IF NOT EXISTS meme_snapshots_time ON meme_price_snapshots(observed_at)")
        c.commit()
    except Exception:
        c.rollback()  # snapshot table not created yet


def load_model(c):
    row = c.execute("SELECT state_json FROM meme_predictor_state WHERE id=1").fetchone()
    model = Model(json.loads(row[0]) if row else None)
    if model.severe is None and model.n:
        rescore_history(c, model)
    return model


def rescore_history(c, model):
    """One-time upgrade of a V1 model: train the severe-loss head and re-score every stored prediction.

    Replays resolved predictions in time order and, for each one, predicts with only the outcomes
    resolved before it, so the upgraded history is as honest as if V2 had run from the start. The
    win-probability column is left as originally recorded."""
    cols = "candidate_id,predicted_at,resolved_at,status,features_json,actual_net_return_pct,model_updates,p_win"
    rows = c.execute(f"SELECT {cols} FROM meme_predictions ORDER BY predicted_at,id").fetchall()
    head = Model(prior=PRIOR_SEVERE_RATE)
    tally = Model()  # only its return tallies are used
    done = sorted(((r[2], i) for i, r in enumerate(rows) if r[3] == "RESOLVED" and r[5] is not None))
    j, out = 0, []
    for cid, at, _, status, fj, net, updates, p in rows:
        while j < len(done) and done[j][0] <= at:
            _, _, _, _, fj2, net2, _, _ = rows[done[j][1]]
            f2 = json.loads(fj2 or "{}")
            head.learn(f2, net2 <= SEVERE_LOSS_PCT, net2)
            tally.n += 1
            tally.wins += net2 > 0
            if net2 > 0:
                tally.win_sum += net2
            else:
                tally.loss_sum += net2
            if net2 <= SEVERE_LOSS_PCT:
                tally.severe_n += 1
                tally.severe_sum += net2
            j += 1
        ps = head.predict(json.loads(fj or "{}"))[0]
        er = tally.expected_return(p, ps)
        severe = None if net is None else int(net <= SEVERE_LOSS_PCT)
        out.append((ps, er, int(updates >= WARMUP and er > 0), severe,
                    None if severe is None else (ps - severe) ** 2, cid))
    c.cursor().executemany(_q(c, """UPDATE meme_predictions SET p_severe_loss=?,expected_net_return_pct=?,
        would_trade=?,severe_loss=?,brier_severe=? WHERE candidate_id=?"""), out)
    # Continue live from everything resolved so far.
    for _, i in done[j:]:
        net2 = rows[i][5]
        head.learn(json.loads(rows[i][4] or "{}"), net2 <= SEVERE_LOSS_PCT, net2)
    severe = [rows[i][5] for _, i in done if rows[i][5] <= SEVERE_LOSS_PCT]
    model.severe_n, model.severe_sum = len(severe), sum(severe)
    model.severe = head
    c.commit()


def save_model(c, model, now):
    args = (now, json.dumps(model.state()))
    if c.execute(_q(c, "UPDATE meme_predictor_state SET updated_at=?,state_json=? WHERE id=1"), args).rowcount == 0:
        c.execute(_q(c, "INSERT INTO meme_predictor_state(id,updated_at,state_json) VALUES(1,?,?)"), args)


def _utc(s):
    d = datetime.fromisoformat(s)
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)


def step(c, now=None):
    """Resolve and learn from matured predictions, then predict new discoveries. Returns a small summary.

    While catching up on history, each call handles one CHUNK of candidates and treats the end of that
    chunk as 'now', so the model only ever learns from outcomes that were known at prediction time."""
    now = now or datetime.now(timezone.utc)
    init(c)
    model = load_model(c)
    since_default = (now - timedelta(days=BACKFILL_DAYS)).isoformat()
    cands = c.execute(_q(c, """SELECT m.id,m.seen_at,m.token,m.token_address,m.eligible,m.raw_json,l.decision
        FROM meme_candidates m LEFT JOIN meme_decision_ledger l ON l.candidate_id=m.id
        WHERE m.id>? AND m.seen_at>=? AND m.seen_at<=? AND m.token_address IS NOT NULL ORDER BY m.id"""),
                      (model.cursor_id, since_default, now.isoformat())).fetchall()
    caught_up = True
    if cands:
        limit = (_utc(cands[0][1]) + CHUNK).isoformat()
        chunk = [r for r in cands if r[1] <= limit]
        caught_up = len(chunk) == len(cands)
        cands = chunk
    as_of = now if caught_up else _utc(cands[-1][1])
    pending = c.execute(_q(c, """SELECT id,candidate_id,token_address,predicted_at,entry_price,p_win,features_json,
        p_severe_loss FROM meme_predictions WHERE status='PENDING' AND predicted_at<=?"""), (as_of.isoformat(),)).fetchall()
    starts = [r[3] for r in pending] + [r[1] for r in cands]
    if not starts:
        save_model(c, model, now.isoformat()); c.commit()
        return {"predicted": 0, "resolved": 0, "unresolvable": 0, "model_updates": model.n, "caught_up": True}
    try:
        snaps = c.execute(_q(c, """SELECT token_address,observed_at,price FROM meme_price_snapshots
            WHERE observed_at>=? AND observed_at<=? ORDER BY observed_at"""), (min(starts), as_of.isoformat())).fetchall()
    except Exception:
        c.rollback()
        snaps = []
    by_tok = {}
    for tok, at, price in snaps:
        if price:
            by_tok.setdefault(tok, []).append((at, float(price)))

    def resolve_at(token, start, entry):
        s = _utc(start)
        path = [((_utc(at) - s).total_seconds(), p) for at, p in by_tok.get(token, ()) if at > start]
        closed = (as_of - s).total_seconds() >= HORIZON_S + END_TOLERANCE_S
        return outcome(entry, path, closed), (as_of - s).total_seconds() > HORIZON_S + GRACE_S

    # Last prediction time per token, to skip repeated observations of the same bet.
    recent = {tok: at for tok, at in c.execute(_q(c, """SELECT token_address,MAX(predicted_at) FROM meme_predictions
        WHERE predicted_at>=? GROUP BY token_address"""), ((_utc(min(starts)) - timedelta(seconds=HORIZON_S)).isoformat(),))}
    queue = []  # (decided_at_iso, seq, item) - outcomes become learnable at the moment they were decided
    seq = 0
    updates, dead = [], []

    def schedule(item):
        nonlocal seq
        res, expired = resolve_at(item["token_address"], item["predicted_at"], item["entry_price"])
        if res:
            decided = (_utc(item["predicted_at"]) + timedelta(seconds=res[3])).isoformat()
            heapq.heappush(queue, (decided, seq, item, res)); seq += 1
        elif expired:
            dead.append(item)

    def drain(until):
        while queue and queue[0][0] <= until:
            decided, _, item, (reason, net, max_up, _) = heapq.heappop(queue)
            won, severe = net > 0, net <= SEVERE_LOSS_PCT
            _, contrib = model.predict(item["features"])  # what the model believed just before this outcome
            severe_contrib = model.severe.predict(item["features"])[1] if model.severe is not None else {}
            item_p, item_ps = item["p_win"], item["p_severe"]
            model.learn_outcome(item["features"], net)
            updates.append((item, decided, reason, net, max_up, won, (item_p - won) ** 2,
                            lesson(item_p, won, reason, net, contrib, item_ps, severe_contrib), severe,
                            None if item_ps is None else (item_ps - severe) ** 2))

    for pid, cid, tok, at, entry, p, fj, ps in pending:
        schedule({"id": pid, "candidate_id": cid, "token_address": tok, "predicted_at": at,
                  "entry_price": entry, "p_win": p, "p_severe": ps, "features": json.loads(fj or "{}")})
    inserts = []
    for cid, seen, token, tok, eligible, raw, decision in cands:
        drain(seen)
        model.cursor_id = cid
        try:
            x = json.loads(raw) if raw else {}
        except ValueError:
            x = {}
        price = _f(x, "price_usd")
        if not price:
            continue
        last = recent.get(tok)
        if decision != TRADED and last and (_utc(seen) - _utc(last)).total_seconds() < HORIZON_S:
            continue
        recent[tok] = seen
        feats = features(x, eligible)
        p, ps, er = model.predict_all(feats)
        item = {"id": None, "candidate_id": cid, "token_address": tok, "predicted_at": seen,
                "entry_price": price * (1 + SLIP), "p_win": p, "p_severe": ps, "features": feats}
        inserts.append((cid, token, tok, seen, VERSION, model.n, item["entry_price"], p, ps, er,
                        int(model.n >= WARMUP and er > 0), decision, json.dumps(feats)))
        schedule(item)
    drain(as_of.isoformat())

    cur = c.cursor()
    if inserts:
        cur.executemany(_q(c, """INSERT INTO meme_predictions(candidate_id,token,token_address,predicted_at,model_version,
            model_updates,entry_price,p_win,p_severe_loss,expected_net_return_pct,would_trade,bot_decision,
            features_json,status) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,'PENDING')""" + (" ON CONFLICT DO NOTHING" if _pg(c) else "")), inserts)
    done = [(decided, reason, net, max_up, int(won), brier, les, int(severe), brier_s, item["candidate_id"])
            for item, decided, reason, net, max_up, won, brier, les, severe, brier_s in updates]
    if done:
        cur.executemany(_q(c, """UPDATE meme_predictions SET status='RESOLVED',resolved_at=?,actual_reason=?,
            actual_net_return_pct=?,actual_max_up_pct=?,won=?,brier=?,lesson=?,severe_loss=?,brier_severe=?
            WHERE candidate_id=?"""), done)
    if dead:
        cur.executemany(_q(c, "UPDATE meme_predictions SET status='UNRESOLVABLE',resolved_at=? WHERE candidate_id=?"),
                        [(as_of.isoformat(), item["candidate_id"]) for item in dead])
    save_model(c, model, now.isoformat())
    c.commit()
    return {"predicted": len(inserts), "resolved": len(done), "unresolvable": len(dead),
            "model_updates": model.n, "caught_up": caught_up}


def catch_up(c, now=None, max_steps=500):
    now = now or datetime.now(timezone.utc)
    total = {"predicted": 0, "resolved": 0, "unresolvable": 0}
    for _ in range(max_steps):
        r = step(c, now)
        for k in total:
            total[k] += r[k]
        if r["caught_up"]:
            break
    return {**total, "model_updates": r["model_updates"], "caught_up": r["caught_up"]}


# ---------------------------------------------------------------- report

def _brier(rows, p_of, y_of):
    return sum((p_of(r) - y_of(r)) ** 2 for r in rows) / len(rows) if rows else None


def _auc(rows, p_of, y_of):
    pos = [p_of(r) for r in rows if y_of(r)]
    neg = [p_of(r) for r in rows if not y_of(r)]
    if not pos or not neg:
        return None
    ranked = sorted([(p, 1) for p in pos] + [(p, 0) for p in neg])
    rank_sum, i = 0.0, 0
    while i < len(ranked):  # average ranks over ties
        j = i
        while j < len(ranked) and ranked[j][0] == ranked[i][0]:
            j += 1
        rank_sum += (i + j + 1) / 2 * sum(1 for k in range(i, j) if ranked[k][1])
        i = j
    return (rank_sum - len(pos) * (len(pos) + 1) / 2) / (len(pos) * len(neg))


def _scorecard(rows, p_key, y_key, prior):
    """Prequential accuracy, learning curve and calibration for one head.

    The baseline is the running outcome rate, which also only knew the past."""
    p_of, y_of, b_of = (lambda r: r[p_key]), (lambda r: r[y_key]), (lambda r: r["_base"])
    seen = 0
    for i, r in enumerate(rows):
        r["_base"] = (seen + prior * 10) / (i + 10)
        seen += r[y_key]
    b, b0 = _brier(rows, p_of, y_of), _brier(rows, b_of, y_of)
    acc = {"n": len(rows), "brier": _r(b), "baseline_brier": _r(b0),
           "skill_vs_baseline_pct": _r(100 * (1 - b / b0), 1) if b is not None and b0 else None,
           "auc": _r(_auc(rows, p_of, y_of), 3),
           "hit_rate_at_50pct": _r(sum((r[p_key] >= .5) == bool(r[y_key]) for r in rows) / len(rows), 3)
           if rows else None}
    windows = []
    size = max(25, len(rows) // 6) if rows else 1
    for i in range(0, len(rows), size):
        w = rows[i:i + size]
        if len(w) >= 10:
            bw, bw0 = _brier(w, p_of, y_of), _brier(w, b_of, y_of)
            windows.append({"from": w[0]["predicted_at"], "n": len(w), "brier": _r(bw),
                            "skill_vs_baseline_pct": _r(100 * (1 - bw / bw0), 1) if bw0 else None,
                            "auc": _r(_auc(w, p_of, y_of), 3)})
    buckets = []
    for lo, hi in ((0, .1), (.1, .2), (.2, .3), (.3, .4), (.4, .5), (.5, .7), (.7, 1.01)):
        w = [r for r in rows if lo <= r[p_key] < hi]
        if w:
            buckets.append({"predicted": f"{lo:.0%}-{min(hi, 1):.0%}", "n": len(w),
                            "avg_predicted_pct": round(100 * sum(r[p_key] for r in w) / len(w), 1),
                            "actual_pct": round(100 * sum(r[y_key] for r in w) / len(w), 1)})
    return acc, windows, buckets


def _signals(model):
    ranked = sorted(model.w.items(), key=lambda kv: kv[1])
    return ([{"feature": k, "weight": round(v, 3)} for k, v in ranked[::-1][:6] if v > 0],
            [{"feature": k, "weight": round(v, 3)} for k, v in ranked[:6] if v < 0])


def _policy(rows):
    if not rows:
        return {"n": 0}
    nets = [r["actual_net_return_pct"] for r in rows]
    return {"n": len(rows), "win_rate_pct": round(100 * sum(r["won"] for r in rows) / len(rows), 1),
            "avg_net_return_pct": round(sum(nets) / len(nets), 2),
            "total_pnl_usd_at_100": round(sum(nets), 2)}


def _r(x, n=4):
    return None if x is None else round(x, n)


def report(c, recent_n=25):
    init(c)
    cols = ["candidate_id", "token", "predicted_at", "model_updates", "p_win", "p_severe_loss",
            "expected_net_return_pct", "would_trade", "bot_decision", "status", "resolved_at", "actual_reason",
            "actual_net_return_pct", "actual_max_up_pct", "won", "severe_loss", "brier", "lesson"]
    model = load_model(c)  # upgrades a V1 history before it is read
    rows = [dict(zip(cols, r)) for r in c.execute(f"SELECT {','.join(cols)} FROM meme_predictions ORDER BY predicted_at,id")]
    res = [r for r in rows if r["status"] == "RESOLVED"]
    scored = [r for r in res if r["model_updates"] >= WARMUP]  # judge only predictions made after warm-up
    scored_severe = [r for r in scored if r["p_severe_loss"] is not None and r["severe_loss"] is not None]
    pos, neg = _signals(model)
    out = {"version": VERSION, "as_of": datetime.now(timezone.utc).isoformat(), "mode": "paper_research",
           "rule": f"win = net > 0 under +{TP:.0f}% target / -{SL:.0f}% stop / {HORIZON_S // 60}m hold, "
                   f"{SLIP:.0%} slippage + {FEE:.1%} fee each side; severe loss = net <= {SEVERE_LOSS_PCT:.0f}%",
           "counts": {"predictions": len(rows), "resolved": len(res),
                      "pending": sum(r["status"] == "PENDING" for r in rows),
                      "unresolvable": sum(r["status"] == "UNRESOLVABLE" for r in rows),
                      "model_updates": model.n, "scored_after_warmup": len(scored)},
           "model": {"learned_win_rate_pct": round(100 * model.wins / model.n, 1) if model.n else None,
                     "learned_severe_loss_rate_pct": round(100 * model.severe_n / model.n, 1) if model.n else None,
                     "avg_win_net_pct": round(model.avg_win(), 2), "avg_loss_net_pct": round(model.avg_loss(), 2),
                     "avg_mild_loss_net_pct": round(model.avg_mild_loss(), 2),
                     "avg_severe_loss_net_pct": round(model.avg_severe(), 2),
                     "top_positive_signals": pos, "top_negative_signals": neg}}
    out["accuracy"], out["learning_curve"], out["calibration"] = _scorecard(scored, "p_win", "won", PRIOR_WIN_RATE)
    sev_pos, sev_neg = _signals(model.severe) if model.severe is not None else ([], [])
    acc, curve, cal = _scorecard(scored_severe, "p_severe_loss", "severe_loss", PRIOR_SEVERE_RATE)
    out["severe_loss"] = {"accuracy": acc, "learning_curve": curve, "calibration": cal,
                          "raises_risk": sev_pos, "lowers_risk": sev_neg}

    picks = [r for r in scored if r["would_trade"]]
    bot = [r for r in scored if r["bot_decision"] == TRADED]
    out["policies"] = {"buy_every_discovery": _policy(scored), "predictor_picks": _policy(picks),
                       "bot_paper_entries": _policy(bot),
                       "bot_entries_predictor_would_skip": _policy([r for r in bot if not r["would_trade"]]),
                       "bot_entries_predictor_agreed": _policy([r for r in bot if r["would_trade"]]),
                       "predictor_picks_bot_rejected": _policy([r for r in picks if r["bot_decision"] != TRADED])}
    # Would skipping the bot's riskiest entries (top quarter by predicted severe-loss chance) have helped?
    rated = sorted((r for r in bot if r["p_severe_loss"] is not None), key=lambda r: r["p_severe_loss"])
    cut = len(rated) - len(rated) // 4
    out["policies"]["bot_entries_riskiest_quarter"] = _policy(rated[cut:])
    out["policies"]["bot_entries_other_three_quarters"] = _policy(rated[:cut])
    if rated[cut:]:
        out["policies"]["bot_entries_riskiest_quarter"]["min_p_severe_loss"] = _r(rated[cut]["p_severe_loss"], 3)
    out["preregistered_hypotheses"] = preregistered(c)
    out["suggestions"] = suggestions(out, model)
    out["recent_lessons"] = [{"token": r["token"], "at": r["resolved_at"], "lesson": r["lesson"]}
                             for r in res[::-1] if r["lesson"]][:10]
    out["recent_predictions"] = [{k: (_r(r[k], 3) if isinstance(r[k], float) else r[k]) for k in
                                  ("token", "predicted_at", "p_win", "p_severe_loss", "expected_net_return_pct",
                                   "would_trade", "bot_decision", "status", "actual_reason", "actual_net_return_pct",
                                   "won")}
                                 for r in rows[::-1][:recent_n]]
    return out


def preregistered(c, seed=31):
    """Judge each registered rule on real bot paper trades opened after its registration time."""
    try:
        trades = c.execute("""SELECT t.opened_at,t.net_return_pct,p.p_win,p.p_severe_loss FROM meme_paper_trades t
            JOIN meme_predictions p ON p.candidate_id=t.candidate_id
            WHERE t.status='CLOSED' AND t.net_return_pct IS NOT NULL ORDER BY t.opened_at""").fetchall()
    except Exception:
        c.rollback()  # paper engine has not added its exit columns yet
        trades = []
    out = []
    for h in HYPOTHESES:
        rule = h["skip_if"]
        rows = [(net, (p_sev if rule["field"] == "p_severe_loss" else p_win))
                for opened, net, p_win, p_sev in trades if opened >= h["registered_at"]]
        rows = [(net, v) for net, v in rows if v is not None]
        n = h.get("decide_at_trades")
        if n and len(rows) < n:
            out.append({**h, "trades_so_far": len(rows),
                        "verdict": f"blind: decided once at {n} trades (have {len(rows)}); interim results hidden"})
            continue
        if n:
            rows = rows[:n]
        skip = [net for net, v in rows if v >= rule["at_least"]]
        keep = [net for net, v in rows if v < rule["at_least"]]
        every = [net for net, _ in rows]

        def side(vals):
            return {"trades": len(vals), "avg_net_return_pct": _r(sum(vals) / len(vals), 2) if vals else None,
                    "win_rate_pct": _r(100 * sum(v > 0 for v in vals) / len(vals), 1) if vals else None,
                    "pnl_usd_at_100": _r(sum(vals), 2)}
        rng = random.Random(seed)
        beats = positive = done = 0
        for _ in range(BOOTSTRAP_SAMPLES if keep and skip else 0):
            sample = [rng.choice(rows) for _ in rows]
            k = [net for net, v in sample if v < rule["at_least"]]
            if not k:
                continue
            beats += sum(k) / len(k) > sum(net for net, _ in sample) / len(sample)
            positive += sum(k) > 0
            done += 1
        pct = _r(100 * beats / done, 1) if done else None
        kept, allr = side(keep), side(every)
        if len(rows) < MIN_VERDICT_TRADES or len(skip) < MIN_VERDICT_SKIPPED:
            verdict = (f"collecting: need {MIN_VERDICT_TRADES}+ bot trades after registration with "
                       f"{MIN_VERDICT_SKIPPED}+ skipped (have {len(rows)} / {len(skip)})")
        elif kept["avg_net_return_pct"] <= allr["avg_net_return_pct"]:
            verdict = "REJECTED: skipping does not improve on taking every bot entry"
        elif pct >= 90:
            verdict = "SUPPORTED: improves on every-entry in >=90% of bootstrap samples -> eligible for a paper trial (needs owner OK)"
        else:
            verdict = "NOT SUPPORTED: ahead but not reliably"
        out.append({**h, "kept": kept, "skipped": side(skip), "every_entry": allr,
                    "bootstrap_pct_kept_beats_every": pct,
                    "bootstrap_pct_kept_profitable": _r(100 * positive / done, 1) if done else None,
                    "verdict": verdict})
    return out


def suggestions(rep, model):
    """Plain-language next steps drawn only from resolved, post-warm-up predictions."""
    s, acc, pol = [], rep["accuracy"], rep["policies"]
    n = rep["counts"]["scored_after_warmup"]
    if n < 100:
        s.append(f"Still learning: {n} scored outcomes so far. Treat everything below as provisional until ~100+.")
    if acc["skill_vs_baseline_pct"] is not None:
        if acc["skill_vs_baseline_pct"] <= 0:
            s.append("Predictions are not yet beating the plain running win rate. The recorded features may not "
                     "carry enough signal; new inputs (holder growth, order flow, social velocity) are the next lever.")
        else:
            s.append(f"Predictions beat the running win rate by {acc['skill_vs_baseline_pct']}% (Brier skill).")
    curve = rep["learning_curve"]
    if len(curve) >= 3 and all(w["skill_vs_baseline_pct"] is not None for w in (curve[0], curve[-1])):
        trend = curve[-1]["skill_vs_baseline_pct"] - curve[0]["skill_vs_baseline_pct"]
        s.append(f"Skill {'improved' if trend > 0 else 'declined'} by {abs(trend):.1f} points from the first to the "
                 f"latest window{'' if trend > 0 else ' - the market may have shifted; recent outcomes carry the most weight'}.")
    skip, agree = pol["bot_entries_predictor_would_skip"], pol["bot_entries_predictor_agreed"]
    if skip["n"] >= 5 and agree["n"] >= 5:
        diff = agree["avg_net_return_pct"] - skip["avg_net_return_pct"]
        if diff > 0:
            s.append(f"Bot entries the predictor liked averaged {agree['avg_net_return_pct']:+.1f}% vs "
                     f"{skip['avg_net_return_pct']:+.1f}% for ones it would skip ({skip['n']} trades). Candidate rule "
                     f"to test forward: only enter when expected return > 0.")
        else:
            s.append("Filtering bot entries by the predictor would not have helped yet; keep it record-only.")
    elif skip["n"] >= 5:
        s.append(f"The predictor would have skipped {skip['n']} bot entries, which averaged "
                 f"{skip['avg_net_return_pct']:+.1f}%.")
    rejected = pol["predictor_picks_bot_rejected"]
    if rejected["n"] >= 10 and rejected["avg_net_return_pct"] > 0:
        s.append(f"{rejected['n']} tokens the bot's gates rejected were predictor picks averaging "
                 f"{rejected['avg_net_return_pct']:+.1f}%: review which gate blocked them.")
    worst = max(rep["calibration"], key=lambda b: abs(b["avg_predicted_pct"] - b["actual_pct"]) if b["n"] >= 10 else 0,
                default=None)
    if worst and worst["n"] >= 10 and abs(worst["avg_predicted_pct"] - worst["actual_pct"]) >= 10:
        way = "overconfident" if worst["avg_predicted_pct"] > worst["actual_pct"] else "underconfident"
        s.append(f"Most {way} around {worst['predicted']} win predictions: said {worst['avg_predicted_pct']}%, "
                 f"got {worst['actual_pct']}% (n={worst['n']}).")
    sev = rep["severe_loss"]
    if sev["accuracy"]["skill_vs_baseline_pct"] is not None and sev["accuracy"]["n"] >= 100:
        sk = sev["accuracy"]["skill_vs_baseline_pct"]
        s.append(f"Severe-loss warnings are {'better' if sk > 0 else 'no better'} than the running severe-loss rate "
                 f"({sk:+.1f}% Brier skill, AUC {sev['accuracy']['auc']}).")
    risky, rest = pol["bot_entries_riskiest_quarter"], pol["bot_entries_other_three_quarters"]
    if risky["n"] >= 10 and rest["n"] >= 10:
        if risky["avg_net_return_pct"] < rest["avg_net_return_pct"]:
            s.append(f"The bot's riskiest quarter of entries (predicted severe-loss chance >= "
                     f"{risky['min_p_severe_loss']:.0%}) averaged {risky['avg_net_return_pct']:+.1f}% vs "
                     f"{rest['avg_net_return_pct']:+.1f}% for the rest. Candidate rule to test forward: skip those.")
        else:
            s.append("Skipping the bot's highest severe-risk entries would not have helped yet.")
    for h in rep.get("preregistered_hypotheses", []):
        s.append(f"Forward test '{h['name']}': {h['verdict']}.")
    if sev["raises_risk"]:
        s.append(f"Biggest severe-loss warning sign learned: {sev['raises_risk'][0]['feature']}.")
    if rep["model"]["top_positive_signals"]:
        top = rep["model"]["top_positive_signals"][0]["feature"]
        s.append(f"Strongest learned win signal: {top}. Strongest warning sign: "
                 f"{(rep['model']['top_negative_signals'] or [{'feature': 'none yet'}])[0]['feature']}.")
    return s


# ---------------------------------------------------------------- CLI

def self_test():
    from memecoin_shadow import init_db
    c = init_db(":memory:")
    c.execute("CREATE TABLE meme_price_snapshots(id INTEGER PRIMARY KEY,observed_at TEXT,token_address TEXT,"
              "pair_address TEXT,price REAL,liquidity_usd REAL,volume_1h_usd REAL)")
    t0 = datetime.now(timezone.utc) - timedelta(hours=3)
    for i in range(120):
        seen = t0 + timedelta(minutes=i)
        good = i % 3 == 0
        x = {"token": f"T{i}", "token_address": f"a{i}", "price_usd": 1.0, "liquidity_usd": 50000,
             "volume_accel": 5.0 if good else 0.3, "observed_at": seen.isoformat()}
        c.execute("INSERT INTO meme_candidates(id,seen_at,token,eligible,raw_json,token_address) VALUES(?,?,?,?,?,?)",
                  (i + 1, seen.isoformat(), x["token"], 1, json.dumps(x), x["token_address"]))
        c.execute("INSERT INTO meme_price_snapshots(observed_at,token_address,price) VALUES(?,?,?)",
                  ((seen + timedelta(minutes=5)).isoformat(), x["token_address"], 1.4 if good else 0.8))
    c.commit()
    r = catch_up(c)
    assert r["caught_up"] and r["resolved"] == 120, r
    rep = report(c)
    assert rep["counts"]["resolved"] == 120
    assert rep["model"]["top_positive_signals"][0]["feature"] == "volume_accel", rep["model"]
    assert rep["accuracy"]["auc"] > .9, rep["accuracy"]
    assert rep["severe_loss"]["lowers_risk"][0]["feature"] == "volume_accel", rep["severe_loss"]
    assert step(c)["predicted"] == 0
    c.close()
    print("memecoin predictor self-test passed")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db", default=DB)
    ap.add_argument("--report", action="store_true", help="print the full JSON report")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        return self_test()
    from memecoin_shadow import init_db
    c = init_db(a.db)  # the default path uses PostgreSQL when DATABASE_URL is set
    try:
        print({"meme_predictor_step": catch_up(c)})
        rep = report(c)
        if a.report:
            print(json.dumps(rep, indent=1))
        else:
            print({"counts": rep["counts"], "accuracy": rep["accuracy"]})
            for line in rep["suggestions"]:
                print("-", line)
    finally:
        c.close()


if __name__ == "__main__":
    main()
