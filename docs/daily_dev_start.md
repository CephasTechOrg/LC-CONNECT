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

### Terminal B — Mobile (one simulator)

```bash
# See what is already running
xcrun simctl list devices booted

# If nothing is booted, start one (pick any available iPhone name)
xcrun simctl boot "iPhone 17"
open -a Simulator

cd /Users/cephas/Projects/LC-CONNECT/mobile
flutter devices
flutter run -d <DEVICE_ID>
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

### 3. Start the iOS Simulator(s)

#### List available iPhones

```bash
xcrun simctl list devices available | grep iPhone
```

#### See what is already booted (avoid duplicates)

```bash
xcrun simctl list devices booted
```

Example:

```text
iPhone 17 (63A084EA-565F-465D-B48D-3A5AC02C2A93) (Booted)
```

#### Boot one device by name

```bash
xcrun simctl boot "iPhone 17"
open -a Simulator
```

#### Boot a second, *different* device (two-account / chat testing)

```bash
# Only boot if it is NOT already in the booted list
xcrun simctl boot "iPhone 17 Pro"
open -a Simulator
xcrun simctl list devices booted
```

If you see `Unable to boot device in current state: Booted`, that device is already running — skip boot and use its id below.

#### Boot by UUID (most precise)

```bash
xcrun simctl boot 63A084EA-565F-465D-B48D-3A5AC02C2A93   # iPhone 17 example
xcrun simctl boot 3317DDEF-EFF2-4754-B96E-864E9C3A2730   # iPhone 17 Pro example
```

> Device UUIDs are unique to your Mac. Always copy them from `xcrun simctl list devices` on your machine.

#### Shut down a simulator

```bash
xcrun simctl shutdown 63A084EA-565F-465D-B48D-3A5AC02C2A93
# or shut down all:
xcrun simctl shutdown all
```

### 4. Start Flutter (choose a device by id)

```bash
cd /Users/cephas/Projects/LC-CONNECT/mobile
flutter devices
```

**One phone:**

```bash
flutter run
# or pin to a specific simulator:
flutter run -d 63A084EA-565F-465D-B48D-3A5AC02C2A93
```

**Two phones (two terminals — different ids):**

```bash
# Terminal B — phone 1
cd /Users/cephas/Projects/LC-CONNECT/mobile
flutter run -d 63A084EA-565F-465D-B48D-3A5AC02C2A93

# Terminal C — phone 2 (different id!)
cd /Users/cephas/Projects/LC-CONNECT/mobile
flutter run -d 3317DDEF-EFF2-4754-B96E-864E9C3A2730
```

Rule: same id twice = same phone. Different ids = two separate simulators.

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
- [ ] Checked `xcrun simctl list devices booted` (know which phones are up)
- [ ] Mobile `.env` points at `http://localhost:8000/api/v1`
- [ ] `flutter run -d <id>` on the intended simulator(s)
