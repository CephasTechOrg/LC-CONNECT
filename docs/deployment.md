# LC Connect — Backend Deployment (Render)

This document covers how the LC Connect FastAPI backend is deployed to Render, including every configuration decision, the problems encountered during initial deployment, and how they were fixed.

---

## Table of Contents

1. [Overview](#1-overview)
2. [render.yaml — Full Configuration](#2-renderyaml--full-configuration)
3. [Environment Variables](#3-environment-variables)
4. [Database URL — asyncpg Format](#4-database-url--asyncpg-format)
5. [Supabase Transaction Pooler — Why Port 6543](#5-supabase-transaction-pooler--why-port-6543)
6. [PYTHONPATH — Module Discovery Fix](#6-pythonpath--module-discovery-fix)
7. [CORS — Allowing the Flutter App](#7-cors--allowing-the-flutter-app)
8. [Render Free Tier Behavior](#8-render-free-tier-behavior)
9. [Deployment Checklist](#9-deployment-checklist)
10. [Troubleshooting — Deployment Failures We Hit](#10-troubleshooting--deployment-failures-we-hit)

---

## 1. Overview

| Item | Value |
|---|---|
| Provider | [Render](https://render.com) |
| Service type | Web service |
| Runtime | Python 3.12 |
| Region | Oregon (US West) |
| Plan | Free |
| Root directory | `lc_connect_backend` |
| Health check | `GET /health` |
| Production URL | `https://lc-connect-api.onrender.com` |

The backend is a FastAPI app served by `uvicorn`. On startup, it runs `scripts/init_db.py` to create any missing tables and seed lookup data, then starts the API server.

---

## 2. render.yaml — Full Configuration

The file lives at the repository root (`render.yaml`):

```yaml
services:
  - type: web
    name: lc-connect-api
    env: python
    region: oregon
    plan: free
    branch: main
    rootDir: lc_connect_backend
    buildCommand: |
      pip install --upgrade pip
      pip install -r requirements.txt
    startCommand: PYTHONPATH=. python scripts/init_db.py && uvicorn app.main:app --host 0.0.0.0 --port $PORT
    healthCheckPath: /health
    envVars:
      - key: PYTHON_VERSION
        value: "3.12.0"
      - key: ENVIRONMENT
        value: production
      - key: SUPABASE_PROFILE_BUCKET
        value: profile-images
      - key: MAX_PROFILE_IMAGE_MB
        value: "5"
      # These are set manually in Render dashboard (sync: false = not in YAML)
      - key: DATABASE_URL
        sync: false
      - key: JWT_SECRET_KEY
        sync: false
      - key: CORS_ORIGINS
        sync: false
      - key: SUPABASE_URL
        sync: false
      - key: SUPABASE_SERVICE_ROLE_KEY
        sync: false
```

### sync: false

Variables marked `sync: false` are declared in the YAML so Render knows they exist, but their values are **not** stored in the YAML file. They must be set manually in the Render dashboard under:

```
Service → Environment → Add Environment Variable
```

This prevents secrets from being committed to git. The YAML is safe to commit because it contains no actual secret values.

---

## 3. Environment Variables

Set these manually in the Render dashboard for the `lc-connect-api` service:

| Variable | Source | Notes |
|---|---|---|
| `DATABASE_URL` | Supabase → Settings → Database → Transaction pooler URL | Must use port 6543, not 5432 |
| `JWT_SECRET_KEY` | Generate with `python -c "import secrets; print(secrets.token_hex(32))"` | Keep this secret — never commit it |
| `CORS_ORIGINS` | Your Flutter app's origin, or `*` for development | Comma-separated list |
| `SUPABASE_URL` | Supabase → Settings → API → Project URL | e.g., `https://xxxxx.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase → Settings → API → service_role key | Backend-only, never in Flutter |

Variables set directly in the YAML (no manual step needed):

| Variable | Value |
|---|---|
| `PYTHON_VERSION` | `3.12.0` |
| `ENVIRONMENT` | `production` |
| `SUPABASE_PROFILE_BUCKET` | `profile-images` |
| `MAX_PROFILE_IMAGE_MB` | `5` |

---

## 4. Database URL — asyncpg Format

### The problem

SQLAlchemy's async engine requires the `postgresql+asyncpg://` URL scheme. Supabase provides connection strings in the standard `postgresql://` format. Pasting the Supabase URL directly into `DATABASE_URL` causes:

```
sqlalchemy.exc.NoSuchModuleError: Can't load plugin: sqlalchemy.dialects:postgresql
```

Or a silent failure where the `psycopg` synchronous driver is used instead.

### The fix — database.py normalization

`lc_connect_backend/app/database.py` converts the URL automatically:

```python
def _async_url(url: str) -> str:
    """Convert postgresql:// or postgres:// to postgresql+asyncpg://, strip whitespace."""
    url = url.strip()   # removes trailing newline from copy-paste
    for prefix in ('postgresql://', 'postgres://'):
        if url.startswith(prefix):
            return 'postgresql+asyncpg://' + url[len(prefix):]
    return url

def _is_local(url: str) -> bool:
    return 'localhost' in url or '127.0.0.1' in url

_db_url = _async_url(settings.database_url)

_connect_args = (
    {}
    if _is_local(_db_url)
    else {'ssl': 'require', 'statement_cache_size': 0}
)

engine = create_async_engine(
    _db_url,
    echo=False,
    pool_pre_ping=True,
    connect_args=_connect_args,
)
```

This means you can paste the Supabase URL as-is into the Render dashboard. The backend normalizes it at startup.

### Why .strip()

Copying a URL from the Supabase dashboard and pasting into Render sometimes adds a trailing newline. Without `.strip()`, the database name becomes `postgres\n` and Postgres throws:

```
database "postgres\n" does not exist
```

---

## 5. Supabase Transaction Pooler — Why Port 6543

Supabase provides two database connection modes:

| Mode | Port | Prepared statements | Best for |
|---|---|---|---|
| Session pooler | 5432 | Supported | Direct connections, long-lived sessions |
| Transaction pooler | **6543** | **Not supported** | Serverless, cloud deployments |

### Why Transaction pooler for Render

Render's free tier spins down the service after 15 minutes of inactivity. When it spins back up, it creates new database connections. The Session pooler (port 5432) can time out during this reconnection because it tries to maintain session state that no longer exists on the pooler's side.

Transaction pooler is stateless per-transaction, which is compatible with a service that may restart frequently.

### asyncpg + Transaction pooler requirement

asyncpg (the async Python Postgres driver) caches prepared statements by default. The Transaction pooler does not maintain per-connection state, so cached prepared statements fail with:

```
asyncpg.exceptions.InvalidSQLStatementNameError
```

The fix is `statement_cache_size: 0` in `connect_args`:

```python
_connect_args = {'ssl': 'require', 'statement_cache_size': 0}
```

This disables the prepared statement cache for asyncpg when connecting to a non-local database.

### Getting the Transaction pooler URL from Supabase

```
Supabase Dashboard → Settings → Database → Connection string → Transaction (tab)
```

The URL will contain port `6543`. Copy it and paste it into the `DATABASE_URL` environment variable on Render.

---

## 6. PYTHONPATH — Module Discovery Fix

### The problem

The start command runs `python scripts/init_db.py`. Inside `init_db.py`, the script does:

```python
from app.database import engine, Base
```

When Python runs `scripts/init_db.py` from the `lc_connect_backend/` root directory, it does not automatically add the current directory to `sys.path`. So `from app.database import ...` fails with:

```
ModuleNotFoundError: No module named 'app'
```

### The fix

Prepend `PYTHONPATH=.` to the command:

```yaml
startCommand: PYTHONPATH=. python scripts/init_db.py && uvicorn app.main:app --host 0.0.0.0 --port $PORT
```

`PYTHONPATH=.` adds the current working directory to Python's module search path. Since `rootDir` in render.yaml is `lc_connect_backend`, the current directory at startup is `lc_connect_backend/`, which contains the `app/` package.

`uvicorn` does not need `PYTHONPATH=.` because it handles module discovery differently, but having it set does not hurt.

---

## 7. CORS — Allowing the Flutter App

The backend uses FastAPI's `CORSMiddleware`. Allowed origins are set via the `CORS_ORIGINS` environment variable (comma-separated list).

### For production with the Flutter app

Flutter mobile apps make API calls from the device's network layer, not from a browser origin. Technically, CORS is a browser enforcement mechanism and does not apply to mobile HTTP clients. However, the CORS middleware must allow `*` or the specific origin if you ever test from a browser (e.g., FastAPI's `/docs` UI or any web-based testing).

For the Render deployment, set:

```
CORS_ORIGINS=*
```

Or to be more restrictive while still allowing browser access to `/docs`:

```
CORS_ORIGINS=https://lc-connect-api.onrender.com,http://localhost:3000
```

### For local development

The local `.env` default:

```env
CORS_ORIGINS=http://localhost:3000,http://localhost:8080,http://127.0.0.1:8000
```

---

## 8. Render Free Tier Behavior

Render's free tier has important constraints to know:

| Behavior | Details |
|---|---|
| **Spin-down** | Service stops after 15 minutes of no incoming requests |
| **Cold start** | First request after spin-down takes 30–60 seconds to respond |
| **No persistent disk** | Anything written to disk is lost on restart (not an issue — all data is in Supabase/Postgres) |
| **750 hours/month** | Free tier allows 750 compute hours per month (enough for one always-on service) |

### Impact on the app

When a user opens the Flutter app after the backend has been idle:
- The first API call will be slow (30–60 seconds)
- Subsequent calls are fast
- The Flutter app shows a loading spinner during this cold start

This is acceptable for the MVP. For production at scale, upgrade to a paid Render plan or add a health check cron job to keep the service warm.

### Keeping the service warm (optional)

If cold starts are disruptive during demos or testing, you can use a free external ping service (UptimeRobot, Freshping) to call `/health` every 10 minutes. This prevents the service from spinning down.

---

## 9. Deployment Checklist

Use this before every deployment:

- [ ] `render.yaml` is committed to the `main` branch
- [ ] `rootDir` is set to `lc_connect_backend`
- [ ] `DATABASE_URL` in Render dashboard uses Transaction pooler URL (port 6543)
- [ ] `JWT_SECRET_KEY` is set in Render dashboard
- [ ] `SUPABASE_URL` is set in Render dashboard
- [ ] `SUPABASE_SERVICE_ROLE_KEY` is set in Render dashboard
- [ ] `CORS_ORIGINS` is set in Render dashboard
- [ ] `requirements.txt` is up to date (`pip freeze > requirements.txt` inside `.venv`)
- [ ] Local `.env` is in `.gitignore` (never commit secrets)
- [ ] `/health` endpoint returns `{"status": "ok"}`

### Triggering a deploy

Render auto-deploys on push to `main`. You can also trigger manually:

```
Render Dashboard → lc-connect-api → Manual Deploy → Deploy latest commit
```

### Viewing logs

```
Render Dashboard → lc-connect-api → Logs
```

Logs show build output, startup output, and request logs in real time.

---

## 10. Troubleshooting — Deployment Failures We Hit

These are the actual failures encountered during the initial Render deployment of LC Connect, and how each was fixed.

### Failure 1: ModuleNotFoundError: No module named 'app'

**When:** `python scripts/init_db.py` ran during startup.

**Error:**
```
ModuleNotFoundError: No module named 'app'
```

**Cause:** Python could not find the `app/` package because the current directory was not in `sys.path`.

**Fix:** Added `PYTHONPATH=.` to the start command:
```yaml
startCommand: PYTHONPATH=. python scripts/init_db.py && uvicorn ...
```

---

### Failure 2: sqlalchemy URL parse error

**When:** Backend started but could not connect to the database.

**Error:**
```
sqlalchemy.exc.ArgumentError: Could not parse rfc1738 URL from string 'postgresql://...'
```

**Cause:** SQLAlchemy async engine requires `postgresql+asyncpg://`, not `postgresql://`.

**Fix:** Added `_async_url()` normalization function to `database.py`. The function converts the prefix on startup.

---

### Failure 3: database "postgres\n" does not exist

**When:** Backend connected to Supabase but the database was not found.

**Error:**
```
sqlalchemy.exc.OperationalError: database "postgres\n" does not exist
```

**Cause:** Copy-pasting the DATABASE_URL from Supabase dashboard added a trailing newline character.

**Fix:** Added `.strip()` inside `_async_url()`. Also cleaned up the Render dashboard value to remove the trailing newline.

---

### Failure 4: Connection timeout (port 5432)

**When:** Backend started but database queries hung and eventually timed out.

**Error:**
```
asyncpg.exceptions.TimeoutError: Connection attempt failed
```

**Cause:** Using the Session pooler URL (port 5432). From Render Oregon, connections to Supabase's Session pooler were timing out.

**Fix:** Switched to the Transaction pooler URL (port 6543) from Supabase's connection settings.

---

### Failure 5: asyncpg prepared statement cache error

**When:** After switching to Transaction pooler, some database operations failed.

**Error:**
```
asyncpg.exceptions.InvalidSQLStatementNameError: prepared statement does not exist
```

**Cause:** asyncpg's prepared statement cache is incompatible with Transaction pooler's stateless model.

**Fix:** Added `statement_cache_size: 0` to `connect_args` in `database.py`:
```python
_connect_args = {'ssl': 'require', 'statement_cache_size': 0}
```

---

### Failure 6: Pydantic ValidationError for DATABASE_URL and JWT_SECRET_KEY

**When:** Backend started but crashed immediately.

**Error:**
```
pydantic_core._pydantic_core.ValidationError: DATABASE_URL Field required
```

**Cause:** The `.env` file was missing from the repository (it had been deleted during a `git filter-repo` run to remove secrets from history).

**Fix:** Recreated `.env` from `.env.example` with correct local values. Added `.env` to `.gitignore` to prevent accidental future deletion. Set values in Render dashboard for production.
