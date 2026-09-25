"""Shared memecoin database compatibility helpers."""
import os, sqlite3

def database_url():
    return os.getenv("DATABASE_URL","")

def is_postgres(path="memecoin_shadow.db"):
    url=database_url() if path=="memecoin_shadow.db" else str(path)
    return url.startswith(("postgres://","postgresql://"))

class PgConn:
    dialect="postgres"
    def __init__(self,url):
        import psycopg
        self._c=psycopg.connect(url)
    def execute(self,sql,params=()):
        sql=sql.replace("INSERT OR IGNORE INTO","INSERT INTO")
        if "INSERT INTO" in sql and "ON CONFLICT" not in sql and ("meme_outcomes" in sql or "meme_paper_trades" in sql):
            sql=sql.rstrip()+" ON CONFLICT DO NOTHING"
        return self._c.execute(sql.replace("?","%s"),params)
    def commit(self): return self._c.commit()
    def close(self): return self._c.close()

def connect(path="memecoin_shadow.db"):
    if is_postgres(path):
        return PgConn(database_url() if path=="memecoin_shadow.db" else path)
    return sqlite3.connect(path)
