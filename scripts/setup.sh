#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# zApp bootstrap
# FastAPI + Next.js + PostgreSQL + Docker
# ============================================================

PROJECT_NAME="${1:-zApp}"
ROOT_DIR="$(pwd)/${PROJECT_NAME}"

echo
echo "=================================================="
echo " zApp bootstrap"
echo "=================================================="
echo

read -rp "PostgreSQL host port [5432]: " DB_PORT
DB_PORT="${DB_PORT:-5432}"

read -rp "FastAPI host port [8000]: " API_PORT
API_PORT="${API_PORT:-8000}"

read -rp "Next.js host port [3000]: " WEB_PORT
WEB_PORT="${WEB_PORT:-3000}"

echo
echo "Configuration"
echo "--------------------------------------------------"
echo "Project:    ${PROJECT_NAME}"
echo "PostgreSQL: localhost:${DB_PORT}"
echo "FastAPI:    http://localhost:${API_PORT}"
echo "Next.js:    http://localhost:${WEB_PORT}"
echo "--------------------------------------------------"
echo

if [ -d "${ROOT_DIR}" ]; then
    echo "ERROR: ${ROOT_DIR} already exists."
    exit 1
fi

mkdir -p "${ROOT_DIR}"
cd "${ROOT_DIR}"

# ============================================================
# STRUCTURE
# ============================================================

mkdir -p \
    apps/api/app/adapters \
    apps/api/app/api/v1/routers \
    apps/api/app/api/v1/schemas \
    apps/api/app/cli \
    apps/api/app/core \
    apps/api/app/jobs \
    apps/api/app/libs \
    apps/api/app/models \
    apps/api/app/services \
    apps/api/scripts \
    apps/api/tests \
    apps/web/lib \
    apps/web/public \
    apps/web/tests \
    docs \
    infra/secrets \
    infra/docker

# ============================================================
# PYTHON PACKAGES
# ============================================================

touch \
    apps/api/app/__init__.py \
    apps/api/app/adapters/__init__.py \
    apps/api/app/api/__init__.py \
    apps/api/app/api/v1/__init__.py \
    apps/api/app/api/v1/routers/__init__.py \
    apps/api/app/api/v1/schemas/__init__.py \
    apps/api/app/cli/__init__.py \
    apps/api/app/core/__init__.py \
    apps/api/app/jobs/__init__.py \
    apps/api/app/libs/__init__.py \
    apps/api/app/models/__init__.py \
    apps/api/app/services/__init__.py

# ============================================================
# POSTGRES PASSWORD
# ============================================================

if command -v openssl >/dev/null 2>&1; then
    POSTGRES_PASSWORD="$(openssl rand -hex 24)"
else
    POSTGRES_PASSWORD="zapp_dev_password"
fi

printf '%s\n' "${POSTGRES_PASSWORD}" > infra/secrets/pgpw
chmod 600 infra/secrets/pgpw

# ============================================================
# ENV
# ============================================================

cat > infra/secrets/.env <<EOF
# ============================================================
# zApp
# ============================================================

APP_NAME=zApp
APP_ENV=development

# ============================================================
# PostgreSQL
# ============================================================

POSTGRES_USER=zapp
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=zapp

POSTGRES_HOST=db
POSTGRES_PORT=5432
POSTGRES_HOST_PORT=${DB_PORT}

# ============================================================
# FastAPI
# ============================================================

API_HOST=0.0.0.0
API_PORT=8000
API_HOST_PORT=${API_PORT}

DATABASE_URL=postgresql+asyncpg://zapp:${POSTGRES_PASSWORD}@db:5432/zapp

# ============================================================
# Next.js
# ============================================================

WEB_HOST=0.0.0.0
WEB_PORT=3000
WEB_HOST_PORT=${WEB_PORT}

NEXT_PUBLIC_API_URL=http://localhost:${API_PORT}
EOF

chmod 600 infra/secrets/.env

# ============================================================
# ROOT GITIGNORE
# ============================================================

cat > .gitignore <<'EOF'
# Secrets
infra/secrets/.env
infra/secrets/pgpw

# Python
__pycache__/
*.py[cod]
*.pyo
*.pyd
.venv/
venv/
.pytest_cache/
.mypy_cache/
.ruff_cache/

# Node
node_modules/
.next/
out/
dist/
npm-debug.log*
yarn-debug.log*
pnpm-debug.log*

# IDE
.vscode/
.idea/

# OS
.DS_Store
Thumbs.db

# Logs
*.log
EOF

# ============================================================
# API - CONFIG
# ============================================================

cat > apps/api/app/core/config.py <<'EOF'
import os


class Settings:
    APP_NAME: str = os.getenv("APP_NAME", "zApp")
    APP_ENV: str = os.getenv("APP_ENV", "development")

    API_V1_PREFIX: str = "/api/v1"

    DATABASE_URL: str = os.getenv(
        "DATABASE_URL",
        "postgresql+asyncpg://zapp:zapp@db:5432/zapp",
    )


settings = Settings()
EOF

# ============================================================
# API - DB
# ============================================================

cat > apps/api/app/core/db.py <<'EOF'
from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.core.config import settings


engine = create_async_engine(
    settings.DATABASE_URL,
    pool_pre_ping=True,
)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        yield session
EOF

# ============================================================
# API - SQLALCHEMY BASE
# ============================================================

cat > apps/api/app/models/base.py <<'EOF'
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass
EOF

# ============================================================
# API - SCHEMAS
# ============================================================

cat > apps/api/app/api/v1/schemas/health.py <<'EOF'
from pydantic import BaseModel


class HealthResponse(BaseModel):
    status: str
    service: str
EOF

# ============================================================
# API - ROUTERS
# ============================================================

cat > apps/api/app/api/v1/routers/health.py <<'EOF'
from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.schemas.health import HealthResponse
from app.core.db import get_db


router = APIRouter(
    prefix="/health",
    tags=["health"],
)


@router.get(
    "",
    response_model=HealthResponse,
)
async def health() -> HealthResponse:
    return HealthResponse(
        status="ok",
        service="zApp API",
    )


@router.get("/db")
async def database_health(
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    await db.execute(text("SELECT 1"))

    return {
        "status": "ok",
        "database": "connected",
    }
EOF

cat > apps/api/app/api/v1/router.py <<'EOF'
from fastapi import APIRouter

from app.api.v1.routers.health import router as health_router


api_router = APIRouter()

api_router.include_router(health_router)
EOF

# ============================================================
# API - MAIN
# ============================================================

cat > apps/api/app/main.py <<EOF
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.core.config import settings


app = FastAPI(
    title=settings.APP_NAME,
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:${WEB_PORT}",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root() -> dict[str, str]:
    return {
        "name": "zApp",
        "service": "api",
        "docs": "/docs",
    }


app.include_router(
    api_router,
    prefix=settings.API_V1_PREFIX,
)
EOF

# ============================================================
# API - REQUIREMENTS
# ============================================================

cat > apps/api/requirements.txt <<'EOF'
fastapi>=0.115
uvicorn[standard]>=0.30

sqlalchemy[asyncio]>=2.0
asyncpg>=0.29
alembic>=1.13

pydantic>=2.8
pydantic-settings>=2.4
python-dotenv>=1.0

httpx>=0.27

pytest>=8.0
pytest-asyncio>=0.23
ruff>=0.6
EOF

# ============================================================
# API - TEST
# ============================================================

cat > apps/api/tests/test_health.py <<'EOF'
from fastapi.testclient import TestClient

from app.main import app


client = TestClient(app)


def test_health() -> None:
    response = client.get("/api/v1/health")

    assert response.status_code == 200

    payload = response.json()

    assert payload["status"] == "ok"
    assert payload["service"] == "zApp API"
EOF

cat > apps/api/tests/README.md <<'EOF'
# zApp API tests

Run from the application container:

```bash
pytest
```
EOF

# ============================================================
# NEXT.JS
# ============================================================

echo "Creating Next.js application..."

TEMP_WEB="$(mktemp -d)"

npx create-next-app@latest "${TEMP_WEB}/web" \
    --typescript \
    --eslint \
    --app \
    --src-dir \
    --use-npm \
    --no-tailwind \
    --import-alias="@/*" \
    --yes

cp -R "${TEMP_WEB}/web/." apps/web/
rm -rf "${TEMP_WEB}"

mkdir -p \
    apps/web/lib \
    apps/web/tests

# ============================================================
# WEB - API CLIENT
# ============================================================

cat > apps/web/lib/api.ts <<EOF
const API_URL =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://localhost:${API_PORT}";

export type HealthResponse = {
  status: string;
  service: string;
};

export async function getHealth(): Promise<HealthResponse> {
  const response = await fetch(
    \`\${API_URL}/api/v1/health\`,
    {
      cache: "no-store",
    }
  );

  if (!response.ok) {
    throw new Error(
      \`API returned HTTP \${response.status}\`
    );
  }

  return response.json();
}
EOF

# ============================================================
# WEB - HOME
# ============================================================

cat > apps/web/src/app/page.tsx <<'EOF'
import { getHealth } from "../../lib/api";

export default async function Home() {
  let apiStatus = "offline";

  try {
    const health = await getHealth();
    apiStatus = health.status;
  } catch {
    apiStatus = "offline";
  }

  return (
    <main
      style={{
        maxWidth: "960px",
        margin: "0 auto",
        padding: "80px 24px",
        fontFamily: "system-ui, sans-serif",
      }}
    >
      <p
        style={{
          fontSize: "13px",
          textTransform: "uppercase",
          letterSpacing: "0.14em",
          opacity: 0.55,
        }}
      >
        zApp
      </p>

      <h1
        style={{
          fontSize: "48px",
          margin: "12px 0",
        }}
      >
        zApp
      </h1>

      <p
        style={{
          fontSize: "20px",
          opacity: 0.65,
        }}
      >
        Next.js + FastAPI + PostgreSQL
      </p>

      <div
        style={{
          marginTop: "40px",
          padding: "20px",
          border: "1px solid #ddd",
          borderRadius: "10px",
        }}
      >
        API status: <strong>{apiStatus}</strong>
      </div>
    </main>
  );
}
EOF

# ============================================================
# SINGLE DOCKERFILE
# ============================================================

cat > infra/docker/Dockerfile <<'EOF'
# ============================================================
# zApp application image
#
# One Dockerfile containing:
# - Python / FastAPI
# - Node / Next.js
# ============================================================

FROM node:24-bookworm-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV NODE_ENV=development

# ------------------------------------------------------------
# Python
# ------------------------------------------------------------

RUN apt-get update \
    && apt-get install -y \
        --no-install-recommends \
        python3 \
        python3-pip \
        python3-venv \
        curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# ------------------------------------------------------------
# API dependencies
# ------------------------------------------------------------

COPY apps/api/requirements.txt /workspace/apps/api/requirements.txt

RUN python3 -m pip install \
    --break-system-packages \
    --no-cache-dir \
    -r /workspace/apps/api/requirements.txt

# ------------------------------------------------------------
# Web dependencies
# ------------------------------------------------------------

COPY apps/web/package.json /workspace/apps/web/package.json
COPY apps/web/package-lock.json /workspace/apps/web/package-lock.json

WORKDIR /workspace/apps/web

RUN npm ci

# ------------------------------------------------------------
# Application
# ------------------------------------------------------------

WORKDIR /workspace

COPY apps /workspace/apps

EXPOSE 3000
EXPOSE 8000
EOF

# ============================================================
# DOCKER COMPOSE
# ============================================================

cat > infra/docker/compose.yaml <<'EOF'
services:

  db:
    image: postgres:17-alpine

    restart: unless-stopped

    env_file:
      - ../secrets/.env

    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}

    ports:
      - "${POSTGRES_HOST_PORT}:5432"

    volumes:
      - zapp_postgres:/var/lib/postgresql/data

    healthcheck:
      test:
        [
          "CMD-SHELL",
          "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"
        ]
      interval: 5s
      timeout: 5s
      retries: 10


  api:
    build:
      context: ../..
      dockerfile: infra/docker/Dockerfile

    restart: unless-stopped

    env_file:
      - ../secrets/.env

    working_dir: /workspace/apps/api

    command:
      [
        "uvicorn",
        "app.main:app",
        "--host",
        "0.0.0.0",
        "--port",
        "8000",
        "--reload"
      ]

    ports:
      - "${API_HOST_PORT}:8000"

    volumes:
      - ../../apps:/workspace/apps

    depends_on:
      db:
        condition: service_healthy


  web:
    build:
      context: ../..
      dockerfile: infra/docker/Dockerfile

    restart: unless-stopped

    env_file:
      - ../secrets/.env

    working_dir: /workspace/apps/web

    command:
      [
        "npm",
        "run",
        "dev",
        "--",
        "-H",
        "0.0.0.0"
      ]

    ports:
      - "${WEB_HOST_PORT}:3000"

    volumes:
      - ../../apps:/workspace/apps
      - zapp_node_modules:/workspace/apps/web/node_modules
      - zapp_next:/workspace/apps/web/.next

    depends_on:
      - api


volumes:
  zapp_postgres:
  zapp_node_modules:
  zapp_next:
EOF

# ============================================================
# MAKEFILE
# ============================================================

cat > Makefile <<'EOF'
DOCKER_DIR := infra/docker
COMPOSE := docker compose \
	--env-file infra/secrets/.env \
	-f $(DOCKER_DIR)/compose.yaml

.PHONY: up down build rebuild restart logs ps api-shell web-shell db-shell test

up:
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

build:
	$(COMPOSE) build

rebuild:
	$(COMPOSE) build --no-cache

restart:
	$(COMPOSE) restart

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

api-shell:
	$(COMPOSE) exec api bash

web-shell:
	$(COMPOSE) exec web bash

db-shell:
	$(COMPOSE) exec db sh -c 'psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB"'

test:
	$(COMPOSE) exec api pytest
EOF

# ============================================================
# README
# ============================================================

cat > README.md <<EOF
# zApp

Base application stack:

- Next.js
- FastAPI
- PostgreSQL
- SQLAlchemy
- Docker Compose

## Infrastructure

Docker configuration is centralized in:

\`\`\`
infra/docker/
├── compose.yaml
└── Dockerfile
\`\`\`

Secrets and environment configuration:

\`\`\`
infra/secrets/
├── .env
└── pgpw
\`\`\`

## Start

\`\`\`bash
make up
\`\`\`

or directly:

\`\`\`bash
docker compose \\
  --env-file infra/secrets/.env \\
  -f infra/docker/compose.yaml \\
  up --build
\`\`\`

## Services

Web:

\`\`\`
http://localhost:${WEB_PORT}
\`\`\`

API:

\`\`\`
http://localhost:${API_PORT}
\`\`\`

Swagger:

\`\`\`
http://localhost:${API_PORT}/docs
\`\`\`

API health:

\`\`\`
http://localhost:${API_PORT}/api/v1/health
\`\`\`

DB health:

\`\`\`
http://localhost:${API_PORT}/api/v1/health/db
\`\`\`

PostgreSQL:

\`\`\`
localhost:${DB_PORT}
\`\`\`
EOF

# ============================================================
# OUTPUT
# ============================================================

echo
echo "=================================================="
echo " zApp created"
echo "=================================================="
echo

echo "Project: ${ROOT_DIR}"
echo

if command -v tree >/dev/null 2>&1; then
    tree \
        -L 7 \
        -I 'node_modules|.next' \
        "${ROOT_DIR}"
fi

echo
echo "Run:"
echo
echo "  cd ${PROJECT_NAME}"
echo "  make up"
echo
echo "Endpoints:"
echo
echo "  Web:     http://localhost:${WEB_PORT}"
echo "  API:     http://localhost:${API_PORT}"
echo "  Swagger: http://localhost:${API_PORT}/docs"
echo "  DB:      localhost:${DB_PORT}"
echo
