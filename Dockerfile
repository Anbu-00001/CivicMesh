# syntax=docker/dockerfile:1.7
# CivicMesh — single-stage image. Jac builds the React client itself
# (via bun) during `jac build`, so we don't need a separate Node stage.
FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    BUN_INSTALL=/opt/bun \
    PATH=/opt/bun/bin:$PATH

# System deps: curl + unzip for bun installer, git for any pip VCS deps,
# build-essential for native wheels (litellm has a few).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    curl ca-certificates git unzip build-essential \
    && rm -rf /var/lib/apt/lists/*

# Bun is required for the Jac client toolchain (vite-on-bun under the hood).
RUN curl -fsSL https://bun.sh/install | bash \
    && /opt/bun/bin/bun --version

WORKDIR /app

# Python deps first for layer-cache wins.
COPY requirements.txt ./
RUN pip install -r requirements.txt

# Project source. .dockerignore strips venv, node_modules, .jac cache, .git.
COPY . .

# Pre-build the production client bundle. Jac caches the build into
# civicmesh/.jac/client; the runtime CMD then serves that bundle along
# with the REST/WS API on a single port. Done at image-build time so
# cold start is fast and the deploy doesn't need npm/bun network access.
WORKDIR /app/civicmesh
RUN jac build app.jac --client web

# Graph state lives in .jac/data/anchor_store.db (Jaseci's SQLite anchor
# store). On Render's free tier there is no persistent disk, so this
# directory is part of the ephemeral container filesystem: it survives
# sleep/wake cycles but is wiped on redeploys. SeedWalker is idempotent
# and repopulates the graph on first request after each redeploy.
RUN mkdir -p /app/civicmesh/.jac/data

EXPOSE 7860

# Production startup: --no-dev disables HMR/Vite dev server so the React
# client is served from the pre-built bundle and the REST + WebSocket API
# bind to the same port.
#
# Port priority: $PORT env var (Render injects 10000) → default 7860
# (Hugging Face Spaces). We patch jac.toml at runtime so jac's internal
# config matches the actual port — avoids a mismatch where the CLI flag
# says one port but jac.toml says another.
CMD ["sh", "-c", "\
  P=${PORT:-7860} && \
  sed -i \"s/^port = .*/port = $P/\" jac.toml && \
  sed -i \"s/^host = .*/host = \\\"0.0.0.0\\\"/\" jac.toml && \
  exec jac start app.jac --no-dev --port $P --host 0.0.0.0\
"]
