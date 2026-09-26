"""Record-only attention signals for memecoin discoveries. Never trades, never blocks an entry.

Memecoin prices are driven by attention, so this records free attention proxies at discovery time for later
testing. Almost everything comes from data DEX Screener already returns to discovery (the token profile and
the pair); the only extra request is DEX Screener's top-boosts list, fetched at most once per minute.

All fields are numeric so the candidate study can test them automatically:
  attn_boosts_active       paid boosts currently active on the pair (paid promotion)
  attn_boost_top_amount    total boost amount if the token is on DEX Screener's top-boosts list, else 0
  attn_social_count        distinct social links + websites across profile and pair
  attn_has_twitter / attn_has_telegram / attn_has_website   0 or 1
  attn_txns_5m             buys + sells in the last 5 minutes
  attn_tx_accel_5m         5-minute trades vs the 1-hour per-5-minute average (attention arriving now)
  attn_volume_accel_5m     same for volume
  attn_buy_ratio_5m / attn_buy_ratio_1h    share of trades that are buys
Any failure leaves fields out (never guessed) and never raises.
"""
import json
import threading
import time
import urllib.request

TOP_BOOSTS_URL = "https://api.dexscreener.com/token-boosts/top/v1"
CACHE_SECONDS = 60.0
TIMEOUT_SECONDS = 5.0
_cache = {"at": -1e9, "value": None}
_lock = threading.Lock()


def _fetch_top_boosts():
    req = urllib.request.Request(TOP_BOOSTS_URL, headers={"User-Agent": "meme-paper-research/1.0"})
    with urllib.request.urlopen(req, timeout=TIMEOUT_SECONDS) as r:
        return json.loads(r.read().decode())


def top_boosts(fetch=None, clock=time.monotonic):
    """{token_address: total_amount} for Solana tokens on the top-boosts list; None if unavailable."""
    fetch = fetch or _fetch_top_boosts
    with _lock:
        if clock() - _cache["at"] < CACHE_SECONDS:
            return _cache["value"]
        try:
            rows = fetch()
            value = {}
            for r in rows if isinstance(rows, list) else []:
                if r.get("chainId") == "solana" and r.get("tokenAddress"):
                    value[r["tokenAddress"]] = float(r.get("totalAmount") or r.get("amount") or 0)
        except Exception as e:
            print(f"::warning::top boosts unavailable: {type(e).__name__}", flush=True)
            value = None
        _cache.update(at=clock(), value=value)
        return value


def _num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


def _links(profile, pair):
    """Distinct (kind, url) pairs from the profile links and the pair's info block."""
    out = set()
    for l in (profile or {}).get("links") or []:
        kind = (l.get("type") or l.get("label") or "website").lower()
        out.add((kind, (l.get("url") or "").lower()))
    info = (pair or {}).get("info") or {}
    for s in info.get("socials") or []:
        kind = (s.get("type") or s.get("platform") or "social").lower()
        out.add((kind, (s.get("url") or s.get("handle") or "").lower()))
    for w in info.get("websites") or []:
        out.add(("website", (w.get("url") or "").lower()))
    return {(k, u) for k, u in out if u}


def signals(profile, pair, boosts=None):
    pair = pair or {}
    tx = pair.get("txns") or {}
    m5, h1 = tx.get("m5") or {}, tx.get("h1") or {}
    b5, s5 = _num(m5.get("buys")), _num(m5.get("sells"))
    b1, s1 = _num(h1.get("buys")), _num(h1.get("sells"))
    vol = pair.get("volume") or {}
    v5, v1 = _num(vol.get("m5")), _num(vol.get("h1"))
    links = _links(profile, pair)
    kinds = {k for k, _ in links}
    out = {
        "attn_boosts_active": _num((pair.get("boosts") or {}).get("active")),
        "attn_social_count": float(len(links)),
        "attn_has_twitter": 1.0 if kinds & {"twitter", "x"} else 0.0,
        "attn_has_telegram": 1.0 if "telegram" in kinds else 0.0,
        "attn_has_website": 1.0 if "website" in kinds else 0.0,
        "attn_txns_5m": b5 + s5,
        "attn_tx_accel_5m": round((b5 + s5) / max((b1 + s1) / 12, 1), 3),
        "attn_volume_accel_5m": round(v5 / max(v1 / 12, 1), 3),
    }
    if b5 + s5 > 0:
        out["attn_buy_ratio_5m"] = round(b5 / (b5 + s5), 3)
    if b1 + s1 > 0:
        out["attn_buy_ratio_1h"] = round(b1 / (b1 + s1), 3)
    if boosts is not None:
        out["attn_boost_top_amount"] = boosts.get((profile or {}).get("tokenAddress"), 0.0)
    return out


def annotate(row, profile, pair, fetch=None, clock=time.monotonic):
    """Return a copy of the normalized discovery row with attention fields added. Never raises."""
    try:
        y = dict(row)
        y.update(signals(profile, pair, top_boosts(fetch, clock)))
        return y
    except Exception:
        return row
