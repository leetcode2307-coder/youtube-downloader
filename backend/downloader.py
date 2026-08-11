"""
Runs yt-dlp as a background subprocess (never blocks the FastAPI event loop),
waits for it to finish downloading + merging, then reports back the final
file path on disk. The video itself never passes through Python memory —
yt-dlp writes straight to the downloads/ folder.
"""
import asyncio
import os
import re
from pathlib import Path
from datetime import datetime
from zoneinfo import ZoneInfo

import database

BASE_DIR = Path(__file__).parent
DOWNLOADS_DIR = BASE_DIR / "downloads"
DOWNLOADS_DIR.mkdir(exist_ok=True)

# Optional: path to a Netscape-format cookies.txt exported from YOUR OWN
# already-logged-in browser session. When present, yt-dlp presents these
# cookies to YouTube so it can fetch videos your account can already see
# (age-gated, or "sign in to confirm you're not a bot" checks). This does
# NOT add any login/auth screen to the app itself — the app stays anonymous
# and single-user; this only lets the server prove *its own* yt-dlp calls
# come from an account you already control.
COOKIES_FILE = Path(os.environ.get("COOKIES_FILE", BASE_DIR / "cookies.txt"))

KOLKATA = ZoneInfo("Asia/Kolkata")

# Matches a plain YouTube / youtu.be URL
YOUTUBE_URL_RE = re.compile(
    r"^(https?://)?(www\.)?(youtube\.com/watch\?v=|youtu\.be/|youtube\.com/shorts/)[\w\-]+"
)


def is_valid_youtube_url(url: str) -> bool:
    return bool(YOUTUBE_URL_RE.match(url.strip()))


def kolkata_now_iso() -> str:
    return datetime.now(KOLKATA).isoformat()


async def run_download(job_id: str, url: str):
    """Background task: launch yt-dlp, wait for completion, update DB."""
    database.update_job(job_id, status="downloading")

    # Exact command style requested: best video + best audio, merged to mp4.
    # --print after_move:filepath reliably prints the FINAL file path once
    # yt-dlp has finished downloading, merging, and moving the file.
    cmd = [
        "yt-dlp",
        "-f", "bv*+ba/b",
        "--merge-output-format", "mp4",
        "-o", str(DOWNLOADS_DIR / "%(title)s.%(ext)s"),
        "--no-playlist",
        "--print", "after_move:filepath",
    ]

    if COOKIES_FILE.exists():
        cmd += ["--cookies", str(COOKIES_FILE)]

    cmd.append(url)

    try:
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout_bytes, stderr_bytes = await process.communicate()
        stdout = stdout_bytes.decode(errors="ignore").strip()
        stderr = stderr_bytes.decode(errors="ignore").strip()

        if process.returncode != 0:
            reason = _friendly_error(stderr) or "yt-dlp failed"
            database.update_job(job_id, status="failed", error=reason)
            return

        # Last non-empty line of stdout is the final merged file path
        lines = [line for line in stdout.splitlines() if line.strip()]
        if not lines:
            database.update_job(job_id, status="failed", error="Could not determine output file")
            return

        final_path = Path(lines[-1].strip())
        if not final_path.exists():
            database.update_job(job_id, status="failed", error="Downloaded file not found on disk")
            return

        size_mb = round(final_path.stat().st_size / (1024 * 1024), 2)
        filename = final_path.name
        timestamp = kolkata_now_iso()

        # Only NOW — after a fully successful download + merge — do we
        # record it in history.
        database.add_completed_download(filename, size_mb, timestamp)
        database.update_job(job_id, status="completed", filename=filename)

    except FileNotFoundError:
        database.update_job(
            job_id, status="failed",
            error="yt-dlp is not installed or not on PATH"
        )
    except Exception as exc:  # noqa: BLE001
        database.update_job(job_id, status="failed", error=str(exc)[:300])


def _friendly_error(stderr: str) -> str:
    lowered = stderr.lower()
    if "private video" in lowered:
        return "This video is private"
    if "video unavailable" in lowered:
        return "Video unavailable"
    if "sign in to confirm" in lowered or "age" in lowered and "restrict" in lowered:
        if COOKIES_FILE.exists():
            return "Age-restricted: your cookies.txt may be expired — re-export it"
        return "Age-restricted or requires sign-in — add cookies.txt to enable (see README)"
    if "unable to download webpage" in lowered or "urlopen error" in lowered:
        return "Network error while contacting YouTube"
    if "unsupported url" in lowered:
        return "Not a valid YouTube URL"
    # Fall back to last meaningful line from yt-dlp's stderr
    for line in reversed(stderr.splitlines()):
        if line.strip().startswith("ERROR:"):
            return line.strip().replace("ERROR:", "").strip()
    return stderr.strip()[:200] if stderr.strip() else None