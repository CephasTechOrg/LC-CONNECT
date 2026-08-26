# LC Connect — Daily Development Start

Use this every time you sit down to work.  
For first-time Mac setup, see `[local_dev_setup.md](./local_dev_setup.md)`.

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

Optional — local Redis (only needed to exercise multi-instance fan-out):

```bash
docker run --rm -p 6379:6379 redis:7-alpine
# in backend/.env: REDIS_URL=redis://127.0.0.1:6379/0
# then restart uvicorn — logs should show "redis: connected"
```

Without `REDIS_URL`, the API stays single-instance (in-memory EventBus + rate limits). That is fine for day-to-day local work.

### Terminal B — Mobile (one simulator)

```bash
# See what is already running
xcrun simctl list devices booted

# If nothing is booted, start one (pick any available iPhone name)
xcrun simctl boot "iPhone 17"
open -a Simulator

cd /Users/cephas/Projects/LC-CONNECT/mobile
flutter devices
flutter run -d <317DDEF-EFF2-4754-B96E-864E9C3A2730>
```

Leave this running. Hot keys:


| Key | Action                                                 |
| --- | ------------------------------------------------------ |
| `r` | Hot reload (UI/code tweaks)                            |
| `R` | Hot restart (state reset; needed after `.env` changes) |
| `q` | Quit the app session                                   |


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



### 3b. Start the Android emulator (Mac) — for **push-notification** testing

> Why Android: **FCM push only fires on a Google-Play Android target.** iOS push needs a paid
> Apple Developer account (not set up yet), so the Pixel emulator is how we test real pushes today.
> Everything else (chat, typing, in-app UI) works on iOS too.

**List Android emulators (the launch-by-id names):**

```bash
cd /Users/cephas/Projects/LC-CONNECT/mobile
flutter emulators
```

```text
Pixel_7             • Pixel 7       • Google       • android   ← our emulator id
```

**Launch it (by id):**

```bash
flutter emulators --launch Pixel_7
```

(Or just press ▶️ next to Pixel 7 in Android Studio → **Virtual Device Manager**.)

**Confirm it's running — note the device id:**

```bash
flutter devices
```

```text
sdk gphone64 arm64 (mobile) • emulator-5554 • android-arm64 • Android (emulator)
```

> The running **device id** is `emulator-5554` (the first emulator is always `-5554`; a second is
> `-5556`, etc.). Use that id with `flutter run -d`. Don't confuse it with the **emulator id**
> `Pixel_7`, which is only for `flutter emulators --launch`.

**Run the app on it:**

```bash
flutter run -d emulator-5554
```

`adb` **(Android's device tool) lives here** — not on `PATH` by default:

```bash
~/Library/Android/sdk/platform-tools/adb devices
# Optional convenience — add to PATH once (then just `adb`):
echo 'export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

**Shut the emulator down:** close its window, or:

```bash
~/Library/Android/sdk/platform-tools/adb -s emulator-5554 emu kill
```

**Two-account push test:** run the app on **Android** (`emulator-5554` = the recipient that gets the
🔔) and sign in as the other account on an **iPhone simulator** (the sender). Sign in on Android →
allow notifications → **close the app** → send from iOS → push arrives on Android in ~3s.

### 4. Start Flutter (choose a device by id)

```bash
cd /Users/cephas/Projects/LC-CONNECT/mobile
flutter devices
```

**One phone:**

```bash
flutter run
# or pin to a specific device:
flutter run -d 63A084EA-565F-465D-B48D-3A5AC02C2A93   # an iPhone simulator (by UUID)
flutter run -d emulator-5554                          # the Android emulator (see 3b)
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
- Mobile: press `**R**` (hot restart) or quit (`q`) and `flutter run` again.

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


| Symptom                                           | Fix                                                                                                              |
| ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `flutter: command not found`                      | `source ~/.zshrc` or open a new terminal                                                                         |
| `No module named 'asyncpg'` / weird import errors | You forgot `source .venv/bin/activate`                                                                           |
| Port 8000 in use                                  | `lsof -i :8000` → `kill <PID>` → start uvicorn again                                                             |
| App hits Render instead of local                  | Mobile `.env` still on production URL → switch to localhost → `R`                                                |
| No iPhone device                                  | `open -a Simulator` then `flutter devices`                                                                       |
| Android emulator missing from `flutter devices`   | Wait for it to finish booting, or `flutter emulators --launch Pixel_7`                                           |
| Push never arrives on Android                     | Emulator must use a **Google Play** system image; app must be **closed**; backend log shows `Push enabled (FCM)` |
| `adb: command not found`                          | Use full path `~/Library/Android/sdk/platform-tools/adb` or add it to `PATH` (see 3b)                            |
| Signup network / SocketException                  | Restart Simulator + full `flutter run`; check VPN / Wi‑Fi                                                        |
| 401 after login                                   | Backend missing/wrong `SUPABASE_JWT_SECRET`; restart uvicorn                                                     |


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

- Postgres running
- Backend terminal: `.venv` activated + uvicorn on `:8000`
- `curl http://localhost:8000/health` OK
- Checked `xcrun simctl list devices booted` (know which phones are up)
- Mobile `.env` points at `http://localhost:8000/api/v1`
- `flutter run -d <id>` on the intended simulator(s)

