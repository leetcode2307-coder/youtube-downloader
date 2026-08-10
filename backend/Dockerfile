FROM python:3.12-slim

# Install runtime dependencies and clean up apt cache to keep the final image small.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install uv and sync dependencies from lockfile for reproducible installs.
COPY pyproject.toml uv.lock ./
RUN pip install --no-cache-dir uv \
    && uv sync --frozen

# Copy the application source code.
COPY main.py database.py downloader.py ./

# uv installs into /app/.venv — put it on PATH so plain `uvicorn` resolves
ENV PATH="/app/.venv/bin:$PATH"

# Create downloads directory at build time. This directory is ephemeral unless a volume is mounted,
# because files written here are lost on container restart/redeploy on most free hosting tiers.
RUN mkdir -p /app/downloads \
    && useradd --system --create-home --shell /usr/sbin/nologin appuser \
    && chown -R appuser:appuser /app

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD curl -f http://127.0.0.1:8000/ || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]