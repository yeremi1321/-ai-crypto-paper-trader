"""The faster refresh must request prices only for open paper positions."""
import sqlite3
import tempfile
from pathlib import Path
from unittest.mock import patch

import memecoin_outcomes
from memecoin_shadow import init_db


def test_open_refresh():
    with tempfile.TemporaryDirectory() as directory:
        path = str(Path(directory) / "paper.db")
        conn = init_db(path)
        conn.execute("""INSERT INTO meme_paper_trades(candidate_id,token_address,opened_at,
            entry_price,status,highest_price,lowest_price,current_price)
            VALUES(1,'active','2026-09-26T07:00:00+00:00',1,'OPEN',1,1,1)""")
        conn.execute("""INSERT INTO meme_paper_trades(candidate_id,token_address,opened_at,
            entry_price,status,highest_price,lowest_price,current_price)
            VALUES(2,'closed','2026-09-26T07:00:00+00:00',1,'CLOSED',1,1,1)""")
        conn.commit()
        conn.close()
        called = []

        def quote(address):
            called.append(address)
            return {"priceUsd": "0.89", "pairAddress": "pair", "liquidity": {"usd": 50000}}

        with patch.object(memecoin_outcomes, "init_db", lambda: init_db(path)), \
             patch.object(memecoin_outcomes, "best_pair", quote), \
             patch.object(memecoin_outcomes.time, "sleep"):
            memecoin_outcomes.run(only_open=True)
        conn = sqlite3.connect(path)
        assert called == ["active"]
        assert conn.execute("SELECT current_price FROM meme_paper_trades WHERE status='OPEN'").fetchone()[0] == .89
        conn.close()


if __name__ == "__main__":
    test_open_refresh()
    print("open paper position refresh test passed")
