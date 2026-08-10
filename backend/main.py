import uuid

from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

import database
import downloader

app = FastAPI(title="YouTube Downloader API", version="1.0.0")

# Flutter (mobile/desktop/emulator) calls this API directly — CORS wide open
# for local development. Tighten this if you ever deploy publicly.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def on_startup():
    database.init_db()


class DownloadRequest(BaseModel):
    url: str


class DownloadResponse(BaseModel):
    job_id: str
    status: str


class StatusResponse(BaseModel):
    job_id: str
    status: str
    filename: str | None = None
    error: str | None = None


class HistoryItem(BaseModel):
    filename: str
    size_mb: float
    downloaded_at: str


@app.post("/download", response_model=DownloadResponse)
async def start_download(payload: DownloadRequest, background_tasks: BackgroundTasks):
    url = payload.url.strip()

    if not url:
        raise HTTPException(status_code=400, detail="URL is required")
    if not downloader.is_valid_youtube_url(url):
        raise HTTPException(status_code=400, detail="Please provide a valid YouTube URL")

    job_id = str(uuid.uuid4())
    database.create_job(job_id, url, downloader.kolkata_now_iso())

    # Fire-and-forget: runs in the background, does not block the request.
    background_tasks.add_task(downloader.run_download, job_id, url)

    return DownloadResponse(job_id=job_id, status="queued")


@app.get("/status/{job_id}", response_model=StatusResponse)
async def get_status(job_id: str):
    job = database.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    return StatusResponse(
        job_id=job["job_id"],
        status=job["status"],
        filename=job.get("filename"),
        error=job.get("error"),
    )


@app.get("/history", response_model=list[HistoryItem])
async def get_history():
    """Only successfully completed + merged downloads ever appear here."""
    return database.list_downloads()


@app.get("/")
async def root():
    return {"message": "YouTube Downloader API is running"}
