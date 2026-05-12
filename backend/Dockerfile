# syntax=docker/dockerfile:1.7

# --- Stage 1: fetch Tectonic binary (LaTeX renderer used by Person A's resume tailor) ---
FROM debian:bookworm-slim AS tectonic
ARG TECTONIC_VERSION=0.15.0
ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl xz-utils \
 && rm -rf /var/lib/apt/lists/*
RUN set -eux; \
    case "$TARGETARCH" in \
      amd64) arch="x86_64";; \
      arm64) arch="aarch64";; \
      *) echo "unsupported arch: $TARGETARCH" >&2; exit 1;; \
    esac; \
    curl -fsSL -o /tmp/tectonic.tar.gz \
      "https://github.com/tectonic-typesetting/tectonic/releases/download/tectonic@${TECTONIC_VERSION}/tectonic-${TECTONIC_VERSION}-${arch}-unknown-linux-musl.tar.gz"; \
    mkdir -p /tmp/tectonic-extract && tar -xzf /tmp/tectonic.tar.gz -C /tmp/tectonic-extract; \
    install -m 0755 /tmp/tectonic-extract/tectonic /usr/local/bin/tectonic

# --- Stage 2: install Python deps with uv ---
FROM python:3.12-slim AS builder
ENV UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_PYTHON_DOWNLOADS=never
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/astral-sh/uv:0.5.4 /uv /usr/local/bin/uv
WORKDIR /app
COPY pyproject.toml uv.lock* ./
RUN uv sync --frozen --no-install-project --no-dev
COPY . .
RUN uv sync --frozen --no-dev

# --- Stage 3: runtime ---
FROM python:3.12-slim
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH=/opt/venv/bin:$PATH \
    TECTONIC_CACHE_DIR=/var/cache/tectonic
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates fontconfig \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p $TECTONIC_CACHE_DIR
COPY --from=tectonic /usr/local/bin/tectonic /usr/local/bin/tectonic
COPY --from=builder /opt/venv /opt/venv
WORKDIR /app
COPY . .

# Pre-warm Tectonic package cache so cold starts on Railway don't pay the first-render tax.
RUN echo "\\documentclass{article}\\begin{document}warmup\\end{document}" > /tmp/warm.tex \
 && tectonic --keep-logs=false --print=false /tmp/warm.tex || true \
 && rm -f /tmp/warm.* /tmp/warm.pdf

EXPOSE 8000
# On Railway, FIREBASE_CREDENTIALS_B64 holds the base64-encoded service-account JSON.
# Decode it to disk on startup and point FIREBASE_CREDENTIALS_PATH at it.
CMD ["sh", "-c", "if [ -n \"$FIREBASE_CREDENTIALS_B64\" ]; then echo \"$FIREBASE_CREDENTIALS_B64\" | base64 -d > /app/firebase_credentials.json && export FIREBASE_CREDENTIALS_PATH=/app/firebase_credentials.json; fi; exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
