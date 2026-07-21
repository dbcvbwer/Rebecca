ARG PYTHON_VERSION=3.13

FROM ghcr.io/astral-sh/uv:python$PYTHON_VERSION-bookworm-slim AS builder

ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=0

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    python3-dev \
    libc6-dev \
    build-essential \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

COPY scripts/rebecca/install_latest_xray.sh /tmp/install_latest_xray.sh
RUN sed -i 's/\r$//' /tmp/install_latest_xray.sh \
    && bash /tmp/install_latest_xray.sh \
    && apt-get remove --purge -y curl unzip \
    && rm -f /tmp/install_latest_xray.sh \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY uv.lock pyproject.toml /build/
RUN uv sync --frozen --no-install-project --no-dev

ADD . /build

RUN uv sync --frozen --no-dev

FROM node:20-bookworm-slim AS dashboard-builder

WORKDIR /dashboard
COPY dashboard/package.json dashboard/package-lock.json* ./
RUN npm ci

COPY dashboard ./
ENV VITE_BASE_API=/api/
RUN npm run build -- --outDir build --assetsDir statics \
    && cp ./build/index.html ./build/404.html

FROM python:$PYTHON_VERSION-slim-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build /code
COPY --from=builder /usr/local/share/xray /usr/local/share/xray
COPY --from=builder /usr/local/bin/xray /usr/local/bin/xray
COPY --from=dashboard-builder /dashboard/build /code/dashboard/build

WORKDIR /code
ENV PATH="/code/.venv/bin:$PATH"

RUN find /code/scripts -type f -name '*.sh' -exec sed -i 's/\r$//' {} + \
    && chmod +x /code/scripts/entrypoint.sh

ENTRYPOINT ["/code/scripts/entrypoint.sh"]
