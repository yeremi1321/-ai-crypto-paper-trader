"""Read the scanner's committed database without relying on a Streamlit redeploy."""

import sqlite3
import time
from urllib.request import Request, urlopen


SCANNER_DB_URL = (
    "https://raw.githubusercontent.com/yeremi1321/-ai-crypto-paper-trader/"
    "main/paper_trader_v4.db"
)


def latest_scanner_db():
    # GitHub's raw-file cache can hold a database for five minutes. A minute
    # bucket gives repeated app sessions one URL while fetching fresh commits.
    url = f"{SCANNER_DB_URL}?minute={int(time.time() // 60)}"
    request = Request(url, headers={"User-Agent": "V5-Paper-Dashboard"})
    with urlopen(request, timeout=12) as response:
        data = response.read(10_000_001)
    if len(data) > 10_000_000 or not data.startswith(b"SQLite format 3\0"):
        raise ValueError("Invalid scanner database response")
    return data


def open_scanner_db(data):
    conn = sqlite3.connect(":memory:")
    conn.deserialize(data)
    if conn.execute("PRAGMA quick_check").fetchone()[0] != "ok":
        conn.close()
        raise ValueError("Scanner database failed integrity check")
    return conn
