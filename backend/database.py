"""
Very small SQLite wrapper.
Only two things are ever persisted:
  1. jobs        -> transient status of a download job (queued/downloading/completed/failed)
  2. downloads   -> permanent record of a SUCCESSFULLY completed + merged file
No video bytes ever touch this database — metadata only.
"""
import sqlite3
from contextlib import contextmanager
from pathlib import Path

DB_PATH = Path(__file__).parent / "app.db"


@contextmanager
def get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db():
    with get_conn() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS jobs (
                job_id TEXT PRIMARY KEY,
                url TEXT NOT NULL,
                status TEXT NOT NULL,          -- queued | downloading | completed | failed
                error TEXT,
                filename TEXT,
                created_at TEXT NOT NULL
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS downloads (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                filename TEXT NOT NULL,
                size_mb REAL NOT NULL,
                downloaded_at TEXT NOT NULL     -- ISO timestamp, Asia/Kolkata
            )
            """
        )


def create_job(job_id: str, url: str, created_at: str):
    with get_conn() as conn:
        conn.execute(
            "INSERT INTO jobs (job_id, url, status, created_at) VALUES (?, ?, 'queued', ?)",
            (job_id, url, created_at),
        )


def update_job(job_id: str, status: str, error: str | None = None, filename: str | None = None):
    with get_conn() as conn:
        conn.execute(
            "UPDATE jobs SET status = ?, error = ?, filename = COALESCE(?, filename) WHERE job_id = ?",
            (status, error, filename, job_id),
        )


def get_job(job_id: str):
    with get_conn() as conn:
        row = conn.execute("SELECT * FROM jobs WHERE job_id = ?", (job_id,)).fetchone()
        return dict(row) if row else None


def add_completed_download(filename: str, size_mb: float, downloaded_at: str):
    with get_conn() as conn:
        conn.execute(
            "INSERT INTO downloads (filename, size_mb, downloaded_at) VALUES (?, ?, ?)",
            (filename, size_mb, downloaded_at),
        )


def list_downloads():
    with get_conn() as conn:
        rows = conn.execute(
            "SELECT filename, size_mb, downloaded_at FROM downloads ORDER BY downloaded_at DESC"
        ).fetchall()
        return [dict(r) for r in rows]
