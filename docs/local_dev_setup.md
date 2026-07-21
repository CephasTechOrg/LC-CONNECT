# LC Connect — First-Time Local Setup (Mac)

Use this guide once when you join the project or set up a new Mac.  
For day-to-day work after this, see [`daily_dev_start.md`](./daily_dev_start.md).

**Target machine:** macOS (Apple Silicon or Intel)  
**Primary mobile target:** iOS Simulator (iPhone)

---

## What you will install

| Tool | Purpose |
|------|---------|
| Xcode | iOS build tools + Simulator |
| Flutter SDK | Build and run the mobile app |
| CocoaPods | iOS dependency helper (Flutter may still need it) |
| Python 3.11+ | Backend virtual environment |
| PostgreSQL | Local app database |
| Git | Clone the repo |

You also need access to the team’s **Supabase** project (Auth + keys).

---

## 1. Clone the repository

```bash
git clone <REPO_URL>
cd LC-CONNECT
```

Repo layout you will use most:

```text
LC-CONNECT/
  backend/     # FastAPI
  mobile/      # Flutter
  docs/        # Documentation
  architecture_review/   # Architecture source of truth
```

---

## 2. Install Xcode and the iOS Simulator

### 2.1 Install Xcode

1. Open the **App Store**.
2. Search for **Xcode** and install it (large download).
3. Open **Xcode** once and accept the license agreement.

### 2.2 Point command-line tools at Xcode

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

Confirm:

```bash
xcodebuild -version
```

### 2.3 Download the iOS Simulator runtime

On current Xcode versions:

1. Open **Xcode**.
2. Go to **Xcode → Settings…**
3. Open the **Components** tab  
   (some newer docs say “Platforms” — if you see that instead, use it).
4. Download **iOS** (Simulator runtime). This can take a while and is several GB.
5. When finished, open the Simulator:

```bash
open -a Simulator
```

Or: **Xcode → Open Developer Tool → Simulator**.

Confirm devices exist:

```bash
xcrun simctl list devices available
```

You should see devices like `iPhone 17`, `iPhone 17 Pro`, etc.

---

## 3. Install Flutter

### 3.1 Install the SDK

Recommended location:

```bash
mkdir -p ~/development
cd ~/development
git clone https://github.com/flutter/flutter.git -b stable --depth 1
```

### 3.2 Add Flutter to your PATH

Add this to `~/.zshrc`:

```bash
# Flutter SDK
export PATH="$HOME/development/flutter/bin:$PATH"
```

Reload your shell:

```bash
source ~/.zshrc
```

Confirm:

```bash
flutter --version
flutter doctor
```

### 3.3 What `flutter doctor` should look like for this project

You want:

- **Flutter** — green check
- **Xcode** — installed (CocoaPods warning is OK if Pods install later)
- **Connected devices** — macOS / Chrome is fine before Simulator is open

**Android SDK is optional** for now. This project is developed primarily on the **iOS Simulator**.

---

## 4. Install CocoaPods (iOS)

Flutter/iOS often needs CocoaPods.

### Option A — Homebrew (recommended if available)

```bash
brew install cocoapods
pod --version
```

### Option B — Ruby gem (if Homebrew is not installed)

macOS system Ruby is often too old for the **latest** CocoaPods. Prefer a pinned version:

```bash
gem install zeitwerk -v 2.6.18 --user-install
gem install i18n -v 1.14.8 --user-install
gem install activesupport -v 6.1.7.10 --user-install
gem install cocoapods-core -v 1.11.3 --user-install
gem install cocoapods -v 1.11.3 --user-install
```

Add gems to PATH in `~/.zshrc` (Ruby 2.6 example):

```bash
export PATH="$HOME/.gem/ruby/2.6.0/bin:$PATH"
```

```bash
source ~/.zshrc
pod --version
```

> Note: Newer Flutter may use Swift Package Manager for some iOS deps.  
> Having CocoaPods installed is still recommended so `flutter doctor` and plugins stay happy.

---

## 5. Install PostgreSQL (local database)

You need a local Postgres database for app data (users, profiles, matches, messages).

**Auth** still talks to **cloud Supabase Auth**.  
**App data** uses **local Postgres** when `DATABASE_URL` points at localhost.

Suggested local database:

```text
Host:     localhost
Port:     5432
Database: lc_connect_db
User:     postgres
Password: postgres
```

Create the database (example with `psql`):

```bash
createdb lc_connect_db
# or
psql -U postgres -c "CREATE DATABASE lc_connect_db;"
```

If you use **Postgres.app**, make sure its `bin` is on your PATH (often already added in `~/.zshrc`).

---

## 6. Backend setup (FastAPI)

```bash
cd /path/to/LC-CONNECT/backend
```

### 6.1 Create a Python virtual environment

```bash
python3 -m venv .venv
source .venv/bin/activate
```

Your prompt should show `(.venv)`.

### 6.2 Install dependencies

```bash
pip install -r requirements.txt
```

### 6.3 Create backend `.env`

```bash
cp .env.example .env
```

Fill at least these keys:

| Key | Where to get it | Required for |
|-----|-----------------|--------------|
| `DATABASE_URL` | Local Postgres connection string | App data |
| `SUPABASE_URL` | Supabase → Project Settings → API → Project URL | Auth verification |
| `SUPABASE_JWT_SECRET` | Supabase → API → **Legacy JWT Secret** | Verifying mobile tokens |
| `SUPABASE_JWT_AUDIENCE` | Usually `authenticated` | Token checks |
| `ALLOWED_EMAIL_DOMAINS` | Default campus domains are fine | Signup policy |
| `JWT_SECRET_KEY` | Any long random string | Only if legacy auth is enabled |
| `AUTH_LEGACY_ENABLED` | `true` during migration rollback window | Legacy custom JWT |

Example local database URL:

```env
DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/lc_connect_db
```

**Important:** `SUPABASE_JWT_SECRET` is the **Legacy JWT Secret** (long base64-looking string).  
It is **not** an `sb_...` key and **not** the anon/service_role `eyJ...` JWT.

### 6.4 Run database migrations

```bash
source .venv/bin/activate
alembic upgrade head
```

### 6.5 Smoke-test the API

```bash
source .venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

In another terminal:

```bash
curl http://localhost:8000/health
```

Expected:

```json
{"status":"ok","service":"lc-connect-api"}
```

API docs (local): [http://localhost:8000/docs](http://localhost:8000/docs)

---

## 7. Mobile setup (Flutter)

```bash
cd /path/to/LC-CONNECT/mobile
```

### 7.1 Install Flutter packages

```bash
flutter pub get
```

### 7.2 Create mobile `.env`

```bash
cp .env.example .env
```

Fill:

| Key | Value for local iOS Simulator |
|-----|-------------------------------|
| `API_BASE_URL` | `http://localhost:8000/api/v1` |
| `SUPABASE_URL` | Same project URL as backend |
| `SUPABASE_ANON_KEY` | Supabase → API → **anon public** key |
| `ENV` | `development` |

For local work, **comment out** the Render production URL:

```env
# API_BASE_URL=https://lc-connect-api.onrender.com/api/v1
API_BASE_URL=http://localhost:8000/api/v1
ENV=development
```

> `.env` is gitignored. Never commit real keys.

### 7.3 Confirm Flutter can see devices

```bash
open -a Simulator
flutter devices
```

You should see an **iPhone** simulator in the list.

### 7.4 First run

```bash
flutter run
```

First build can take several minutes. Success looks like:

```text
flutter: supabase.supabase_flutter: INFO: ***** Supabase init completed *****
Flutter run key commands.
r Hot reload.
R Hot restart.
```

---

## 8. How the local stack fits together

```text
iOS Simulator (Flutter)
   │
   ├─ Supabase Auth  →  cloud Supabase (signup / login / OTP / sessions)
   │
   └─ REST API       →  local FastAPI (localhost:8000)
                            │
                            └─ local PostgreSQL (app data)
```

| Concern | Service |
|---------|---------|
| Passwords, email confirm, sessions | Supabase Auth (cloud) |
| Bootstrap user, profiles, matches, messages | FastAPI + local Postgres |
| Profile images (later) | Supabase Storage |

---

## 9. Architecture docs (read before changing auth/chat)

Before changing authentication, messaging, Redis, or security:

1. Read Cursor rules in `.cursor/rules/`
2. Read `architecture_review/` (source of truth)

Locked direction:

- Supabase Auth for credentials/sessions
- FastAPI for authorization (REST + future WebSockets)
- Not Supabase Realtime for chat (target: FastAPI WebSockets)

---

## 10. Common first-setup problems

| Problem | Fix |
|---------|-----|
| `flutter: command not found` | Add Flutter to PATH and `source ~/.zshrc` |
| No iPhone in `flutter devices` | Download iOS runtime in Xcode Components, then `open -a Simulator` |
| `No module named 'asyncpg'` | Activate `.venv` before running uvicorn; `pip install -r requirements.txt` |
| `Address already in use` on port 8000 | Stop the other process: `lsof -i :8000` then kill that PID |
| CocoaPods install fails on Ruby 2.6 | Use pinned CocoaPods 1.11.3 or install via Homebrew |
| Signup `SocketException` | Restart Simulator + full `flutter run` (not only hot reload); check VPN |
| Auth works but API fails | Mobile `.env` must use `http://localhost:8000/api/v1` for Simulator |
| Token verify fails on backend | Fill `SUPABASE_JWT_SECRET` with Legacy JWT Secret and restart uvicorn |

---

## 11. Setup checklist

- [ ] Xcode installed and opened once
- [ ] iOS Simulator runtime downloaded (Components)
- [ ] Flutter on PATH (`flutter doctor`)
- [ ] CocoaPods available (`pod --version`)
- [ ] Local Postgres running with `lc_connect_db`
- [ ] Backend `.venv` + `pip install -r requirements.txt`
- [ ] Backend `.env` filled (especially `SUPABASE_JWT_SECRET`)
- [ ] `alembic upgrade head`
- [ ] `curl http://localhost:8000/health` works
- [ ] Mobile `.env` filled and pointing at localhost
- [ ] `flutter run` launches on iPhone Simulator

When all boxes are checked, use [`daily_dev_start.md`](./daily_dev_start.md) every day.
