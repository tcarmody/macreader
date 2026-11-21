# DataPoints backend: FastAPI served by uvicorn.
#
# Python comes from the base image; uv installs the locked dependencies into
# /app/.venv. Matches local dev, where .python-version pins 3.14 too.
FROM python:3.14-slim

COPY --from=ghcr.io/astral-sh/uv:0.13.9 /uv /uvx /bin/

WORKDIR /app

# Use the base image's interpreter (never download one), compile bytecode at
# install time for faster startup, and copy rather than hardlink from the cache.
ENV UV_PYTHON_DOWNLOADS=never \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

# Install dependencies first so the layer caches across code changes.
# --frozen: install exactly uv.lock, failing if it's out of date with pyproject.
COPY pyproject.toml uv.lock .python-version ./
RUN uv sync --frozen --no-dev --no-install-project

# Application code (the importable `backend` package).
COPY backend ./backend

# SQLite and the search index live on the Railway Volume mounted at /app/data
# (DB_PATH=/app/data/articles.db; see DEPLOYMENT.md).
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

EXPOSE 5005

# Railway injects $PORT; bind 0.0.0.0 so the service is reachable. Falls back
# to 5005 for plain `docker run`.
CMD ["sh", "-c", "uvicorn backend.server:app --host 0.0.0.0 --port ${PORT:-5005}"]
