# LC Connect — Daily Development Start

Use this every time you sit down to work.  
For first-time Mac setup, see [`local_dev_setup.md`](./local_dev_setup.md).

You need **two terminals** (plus the iOS Simulator).

---

## Quick start (copy/paste)

### Terminal A — Backend

```bash
cd /Users/cephas/Projects/LC-CONNECT/backend
source .venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Leave this running. You should see:

```text
Application startup complete.
Uvicorn running on http://0.0.0.0:8000
```

### Terminal B — Mobile

```bash
open -a Simulator
cd /Users/cephas/Projects/LC-CONNECT/mobile
flutter run
```

Leave this running. Hot keys:

| Key | Action |
|-----|--------|
| `r` | Hot reload (UI/code tweaks) |
| `R` | Hot restart (state reset; needed after `.env` changes) |
| `q` | Quit the app session |

---

## Step-by-step

### 1. Start PostgreSQL

Make sure your local Postgres is running (Postgres.app, Homebrew service, or Docker — whichever you use).

Database expected by default local `.env`:

```text
lc_connect_db on localhost:5432
```

### 2. Start the backend

```bash
cd /Users/cephas/Projects/LC-CONNECT/backend
source .venv/bin/activate
```

Confirm the prompt shows `(.venv)`.

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Health check (optional, third terminal):

```bash
curl http://localhost:8000/health
```

Docs: [http://localhost:8000/docs](http://localhost:8000/docs)

### 3. Start the iOS Simulator

```bash
open -a Simulator
```

Pick an iPhone device if needed (e.g. **iPhone 17**).

### 4. Start Flutter

```bash
cd /Users/cephas/Projects/LC-CONNECT/mobile
flutter devices
flutter run
```

If multiple devices appear, pick the iPhone simulator when prompted, or:

```bash
flutter run -d <device_id>
```

---

## Confirm you are in local mode

### Mobile `.env`

```env
API_BASE_URL=http://localhost:8000/api/v1
ENV=development
# API_BASE_URL=https://lc-connect-api.onrender.com/api/v1   # keep commented for local
```

### Backend `.env`

```env
DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/lc_connect_db
SUPABASE_URL=https://YOURPROJECT.supabase.co
SUPABASE_JWT_SECRET=<legacy-jwt-secret>
```

After editing either `.env`:

- Backend: uvicorn `--reload` usually picks it up; if not, stop and restart Terminal A.
- Mobile: press **`R`** (hot restart) or quit (`q`) and `flutter run` again.

---

## What talks to what (local day)

```text
Simulator app
  → Supabase Auth (cloud)     signup / login / OTP
  → FastAPI localhost:8000    bootstrap, profiles, rest of API
       → local Postgres       users, profiles, matches, messages
```

---

## Stopping for the day

1. In Flutter terminal: press `q`
2. In backend terminal: `Ctrl+C`
3. Optionally quit Simulator

---

## Common daily issues

| Symptom | Fix |
|---------|-----|
| `flutter: command not found` | `source ~/.zshrc` or open a new terminal |
| `No module named 'asyncpg'` / weird import errors | You forgot `source .venv/bin/activate` |
| Port 8000 in use | `lsof -i :8000` → `kill <PID>` → start uvicorn again |
| App hits Render instead of local | Mobile `.env` still on production URL → switch to localhost → `R` |
| No iPhone device | `open -a Simulator` then `flutter devices` |
| Signup network / SocketException | Restart Simulator + full `flutter run`; check VPN / Wi‑Fi |
| 401 after login | Backend missing/wrong `SUPABASE_JWT_SECRET`; restart uvicorn |

---

## Optional commands you may need occasionally

### Reinstall mobile packages

```bash
cd /Users/cephas/Projects/LC-CONNECT/mobile
flutter pub get
```

### Reinstall backend packages

```bash
cd /Users/cephas/Projects/LC-CONNECT/backend
source .venv/bin/activate
pip install -r requirements.txt
```

### Apply new database migrations

```bash
cd /Users/cephas/Projects/LC-CONNECT/backend
source .venv/bin/activate
alembic upgrade head
```

### Check Flutter environment

```bash
flutter doctor
```

---

## Suggested daily checklist

- [ ] Postgres running
- [ ] Backend terminal: `.venv` activated + uvicorn on `:8000`
- [ ] `curl http://localhost:8000/health` OK
- [ ] Simulator open
- [ ] Mobile `.env` points at `http://localhost:8000/api/v1`
- [ ] `flutter run` on iPhone Simulator
