# LC Connect — Local Development Setup

Everything a new developer needs to get the LC Connect MVP running locally from scratch.

LC Connect uses:

- **Flutter** for the Android/iOS mobile app
- **FastAPI** for the backend API
- **Local PostgreSQL** for local development
- **Supabase PostgreSQL** for production
- **Supabase Storage** for profile images

Follow each section in order.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Recommended Repository Structure](#2-recommended-repository-structure)
3. [Create or Clone the Repository](#3-create-or-clone-the-repository)
4. [Start Local PostgreSQL](#4-start-local-postgresql)
5. [Backend Setup](#5-backend-setup)
6. [Supabase Storage Setup](#6-supabase-storage-setup)
7. [Flutter Mobile Setup](#7-flutter-mobile-setup)
8. [Connect Flutter to FastAPI](#8-connect-flutter-to-fastapi)
9. [Running Tests](#9-running-tests)
10. [Code Quality](#10-code-quality)
11. [Environment Variable Reference](#11-environment-variable-reference)
12. [Troubleshooting](#12-troubleshooting)
13. [Daily Development Workflow](#13-daily-development-workflow)

---

## 1. Prerequisites

Install these before you start.

| Tool | Purpose | Download |
|------|---------|----------|
| **Python 3.12+** | FastAPI backend | https://www.python.org/downloads/ |
| **Flutter SDK** | Mobile app | https://docs.flutter.dev/get-started/install |
| **Git** | Version control | https://git-scm.com/ |
| **PostgreSQL** | Local database | https://www.postgresql.org/download/ |
| **Docker Desktop** | Optional local PostgreSQL alternative | https://www.docker.com/products/docker-desktop/ |
| **Android Studio** | Android SDK, emulator, ADB | https://developer.android.com/studio |
| **VS Code or Android Studio** | Editor | https://code.visualstudio.com/ |

Recommended editor extensions:

- Flutter
- Dart
- Python
- Pylance
- Ruff

### Windows note

After installing Flutter and Android Studio, open PowerShell and run:

```powershell
flutter doctor
```

Fix everything Flutter reports, especially:

- Android toolchain
- Android SDK
- Android SDK command-line tools
- Android licenses
- Connected device or emulator

Accept Android licenses:

```powershell
flutter doctor --android-licenses
```

Run `flutter doctor` again until the required items are green.

---

## 2. Recommended Repository Structure

Use this top-level structure:

```text
lc_connect/
├── backend/              # FastAPI backend
├── mobile/               # Flutter mobile app
├── docs/                 # Project documentation
├── assets/               # Optional shared design assets
├── infra/                # Optional Docker/deployment files
└── README.md
```

The backend should look like:

```text
backend/
├── app/
│   ├── main.py
│   ├── config.py
│   ├── database.py
│   ├── models.py
│   ├── schemas.py
│   ├── security.py
│   ├── dependencies.py
│   ├── services.py
│   ├── seed.py
│   └── routers/
├── scripts/
│   ├── init_db.py
│   └── create_admin.py
├── requirements.txt
├── .env.example
└── README.md
```

The Flutter app should look like:

```text
mobile/
├── android/
├── ios/
├── lib/
│   ├── app/
│   ├── core/
│   ├── features/
│   ├── shared/
│   └── main.dart
├── assets/
│   └── images/
│       ├── students.png
│       ├── school.png
│       └── headshots.png
├── test/
└── pubspec.yaml
```

Recommended Flutter `lib/` structure:

```text
lib/
├── main.dart
├── app/
│   ├── app.dart
│   ├── router.dart
│   └── theme.dart
├── core/
│   ├── config/
│   │   └── app_config.dart
│   ├── network/
│   │   └── api_client.dart
│   ├── storage/
│   │   └── token_storage.dart
│   └── constants/
│       ├── colors.dart
│       └── assets.dart
├── shared/
│   ├── widgets/
│   └── models/
└── features/
    ├── auth/
    ├── home/
    ├── discovery/
    ├── activities/
    ├── messages/
    └── profile/
```

---

## 3. Create or Clone the Repository

### Option A — Clone existing repo

```bash
git clone <repo-url>
cd lc_connect
```

### Option B — Create new local repo

```bash
mkdir lc_connect
cd lc_connect
git init
mkdir backend mobile docs infra
```

Add a root `.gitignore`:

```gitignore
# Python
__pycache__/
*.pyc
.venv/
.env
.env.local
.env.production

# Flutter/Dart
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
build/
mobile/.dart_tool/
mobile/build/

# IDE
.vscode/
.idea/

# OS
.DS_Store
Thumbs.db
```

---

## 4. Start Local PostgreSQL

For local development, use a local database named:

```text
lc_connect_dev
```

You have two good options.

### Option A — Local PostgreSQL installed on your machine

Create the database:

```bash
createdb lc_connect_dev
```

If `createdb` is not available, open the PostgreSQL shell:

```bash
psql -U postgres
```

Then run:

```sql
CREATE DATABASE lc_connect_dev;
```

Your local database URL will usually be:

```env
DATABASE_URL=postgresql+psycopg://postgres:postgres@localhost:5432/lc_connect_dev
```

Replace the password if your local PostgreSQL password is not `postgres`.

### Option B — Docker PostgreSQL

Create this file:

```text
infra/docker-compose.local.yml
```

Add:

```yaml
services:
  postgres:
    image: postgres:16
    container_name: lc_connect_postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: lc_connect_dev
    ports:
      - "5432:5432"
    volumes:
      - lc_connect_postgres_data:/var/lib/postgresql/data

volumes:
  lc_connect_postgres_data:
```

Start it:

```bash
docker compose -f infra/docker-compose.local.yml up -d
```

Verify:

```bash
docker compose -f infra/docker-compose.local.yml ps
```

Your local database URL is:

```env
DATABASE_URL=postgresql+psycopg://postgres:postgres@localhost:5432/lc_connect_dev
```

---

## 5. Backend Setup

All commands in this section run from the `backend/` directory.

### 5.1 Create Python virtual environment

**macOS / Linux:**

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
```

**Windows PowerShell:**

```powershell
cd backend
python -m venv .venv
.venv\Scripts\Activate.ps1
```

You should see `(.venv)` in your terminal.

If PowerShell blocks activation, run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Then activate again.

### 5.2 Install backend dependencies

```bash
pip install -r requirements.txt
```

If `requirements.txt` is not created yet, use this starter list:

```txt
fastapi
uvicorn[standard]
sqlalchemy
psycopg[binary]
pydantic
pydantic-settings
python-dotenv
passlib[bcrypt]
python-jose[cryptography]
python-multipart
supabase
```

### 5.3 Create backend `.env`

Copy the example file:

**macOS / Linux:**

```bash
cp .env.example .env
```

**Windows PowerShell:**

```powershell
Copy-Item .env.example .env
```

Use this local development config:

```env
APP_NAME=LC Connect API
ENVIRONMENT=development

DATABASE_URL=postgresql+psycopg://postgres:postgres@localhost:5432/lc_connect_dev

JWT_SECRET_KEY=replace_this_with_a_long_random_secret
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=10080

SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_SERVICE_ROLE_KEY=YOUR_SUPABASE_SERVICE_ROLE_KEY
SUPABASE_PROFILE_BUCKET=profile-images

CORS_ORIGINS=http://localhost:3000,http://localhost:5173,http://localhost:8080,http://127.0.0.1:8000
```

Generate a strong local JWT secret:

```bash
python -c "import secrets; print(secrets.token_urlsafe(64))"
```

Important:

- `DATABASE_URL` is local PostgreSQL during local development.
- `SUPABASE_URL` is not your database URL. It is your Supabase project API URL.
- `SUPABASE_SERVICE_ROLE_KEY` must stay only in the backend.
- Never put the service role key in the Flutter app.

### 5.4 Confirm `app/config.py` reads `.env`

Your config should include the `.env` file loading rule:

```python
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    APP_NAME: str = "LC Connect API"
    ENVIRONMENT: str = "development"

    DATABASE_URL: str

    JWT_SECRET_KEY: str
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 10080

    SUPABASE_URL: str | None = None
    SUPABASE_SERVICE_ROLE_KEY: str | None = None
    SUPABASE_PROFILE_BUCKET: str = "profile-images"

    CORS_ORIGINS: str = "http://localhost:3000,http://localhost:5173,http://localhost:8080"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
```

Quick test:

```bash
python -c "from app.config import settings; print(settings.APP_NAME); print(bool(settings.DATABASE_URL)); print(bool(settings.JWT_SECRET_KEY))"
```

Expected:

```text
LC Connect API
True
True
```

### 5.5 Initialize local database tables

```bash
python scripts/init_db.py
```

This should create tables and seed the default lookup data.

Later, before production, replace this workflow with Alembic migrations.

### 5.6 Start the backend

```bash
uvicorn app.main:app --reload
```

Open:

```text
http://127.0.0.1:8000/docs
```

Health check:

```text
http://127.0.0.1:8000/health
```

---

## 6. Supabase Storage Setup

LC Connect uses Supabase Storage for profile images.

### 6.1 Create Supabase project

Create a Supabase project and copy:

- Project URL
- Service role key
- Production PostgreSQL connection string

For local development, you only need the Project URL and Service Role Key for image uploads.

### 6.2 Create profile image bucket

In Supabase:

```text
Storage → New bucket
```

Create:

```text
profile-images
```

Recommended MVP setup:

```text
Flutter app → FastAPI backend → Supabase Storage
```

Do not do this:

```text
Flutter app → Supabase service role key
```

That is unsafe.

### 6.3 Production database setup

For production, your backend `DATABASE_URL` should point to Supabase PostgreSQL:

```env
DATABASE_URL=postgresql+psycopg://postgres:YOUR_SUPABASE_DB_PASSWORD@db.YOUR_PROJECT_REF.supabase.co:5432/postgres?sslmode=require
```

Use this only in production environment variables on your hosting provider, not in the mobile app.

---

## 7. Flutter Mobile Setup

All commands in this section run from the repository root unless stated otherwise.

### 7.1 Create the Flutter app

If `mobile/` does not exist yet:

```bash
flutter create mobile
cd mobile
```

If `mobile/` already exists:

```bash
cd mobile
```

### 7.2 Confirm Flutter runs

```bash
flutter pub get
flutter run
```

At this point, the default Flutter counter app should run.

### 7.3 Add packages

From `mobile/`:

```bash
flutter pub add dio
flutter pub add flutter_secure_storage
flutter pub add go_router
flutter pub add flutter_riverpod riverpod
flutter pub add flutter_dotenv
flutter pub add google_fonts
flutter pub add image_picker
flutter pub add intl
flutter pub add supabase_flutter
```

`supabase_flutter` is used for two things: subscribing to Realtime message events and (via the backend) profile image storage. See `supabase.md` for full setup details.

### 7.4 Add image assets

Create the images folder:

```bash
mkdir -p assets/images
```

On Windows PowerShell:

```powershell
New-Item -ItemType Directory -Force assets\images
```

Place these files inside `mobile/assets/images/`:

```text
students.png
school.png
headshots.png
```

Use them like this:

- `students.png` = group of four students on the login hero
- `school.png` = campus building behind students on the login hero
- `headshots.png` = reusable mock avatar everywhere a student profile/headshot is needed

### 7.5 Register assets in `pubspec.yaml`

Open `mobile/pubspec.yaml`.

Add:

```yaml
flutter:
  uses-material-design: true

  assets:
    - assets/images/students.png
    - assets/images/school.png
    - assets/images/headshots.png
```

Make sure the indentation is exactly correct. YAML is sensitive to spacing.

Then run:

```bash
flutter pub get
```

### 7.6 Flutter environment config

LC Connect uses `flutter_dotenv` to load a `.env` file at runtime (the same pattern as the backend). Create `mobile/.env`:

```env
API_BASE_URL=http://localhost:8000/api/v1
ENV=development

SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY=your_supabase_anon_key_here
```

Get the Supabase values from **Supabase → Settings → API**. See `supabase.md` for details on which key to use.

Register it in `mobile/pubspec.yaml` under `flutter: assets:`:

```yaml
  assets:
    - .env
    - assets/images/students.png
    - assets/images/school.png
    - assets/images/headshots.png
```

The complete `main.dart` startup sequence — load env, initialize Supabase, then run app:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();    // required before Supabase.initialize
  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  runApp(const ProviderScope(child: LcConnectApp()));
}
```

`WidgetsFlutterBinding.ensureInitialized()` must be called before any async work in `main()`. `Supabase.initialize()` must complete before `runApp` so the Realtime client is available when chat screens open.

For physical Android device over USB, use `adb reverse tcp:8000 tcp:8000` and keep `API_BASE_URL=http://localhost:8000/api/v1` — ADB reverse tunnels `localhost` on the phone to your PC's port 8000.

### 7.7 Recommended asset constants

Create:

```text
mobile/lib/core/constants/assets.dart
```

Add:

```dart
class AppAssets {
  static const String students = 'assets/images/students.png';
  static const String school = 'assets/images/school.png';
  static const String headshot = 'assets/images/headshots.png';
}
```

### 7.8 Recommended color constants

Create:

```text
mobile/lib/core/constants/colors.dart
```

Add:

```dart
import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF8CB0BF);
  static const Color primaryDark = Color(0xFF3F7FB5);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color background = Color(0xFFF6F9FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE5EAF0);
}
```

---

## 8. Connect Flutter to FastAPI

The correct URL depends on where the Flutter app is running.

### 8.1 Android emulator

Use:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` is the Android emulator alias for your computer's localhost.

### 8.2 Physical Android device over USB

Step 1 — Enable USB debugging:

```text
Settings → About Phone → tap Build Number 7 times → Developer Options → USB Debugging
```

Step 2 — Confirm ADB sees the phone:

```bash
adb devices
```

Step 3 — Forward phone port 8000 to laptop port 8000:

```bash
adb reverse tcp:8000 tcp:8000
```

Step 4 — Run Flutter:

```bash
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

### 8.3 Physical Android device over same Wi-Fi

Find your computer IP.

Windows:

```powershell
ipconfig
```

Then run:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.42:8000
```

Replace the IP with your actual computer IP.

### 8.4 iOS simulator

On macOS:

```bash
open -a Simulator
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

### 8.5 Production backend

```bash
flutter run --dart-define=API_BASE_URL=https://your-production-api.com
```

For release builds:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://your-production-api.com
```

For Android App Bundle:

```bash
flutter build appbundle --release --dart-define=API_BASE_URL=https://your-production-api.com
```

### 8.6 Chrome (Flutter web) against the production Render backend

Flutter web picks a random port each time you run it, which breaks CORS on the production backend. Pin the port so it never changes:

```bash
cd lc_connect_mobile
flutter run -d chrome --web-port 8080
```

Then add `http://localhost:8080` to the `CORS_ORIGINS` environment variable on Render (comma-separated alongside any existing origins):

```
CORS_ORIGINS=https://your-other-origin.com,http://localhost:8080
```

Save the variable on Render and redeploy (or wait for the next deploy). After that, `http://localhost:8080` will always be allowed by the backend and you can run the web app with the same command every time.

Your Flutter `.env` should point to the Render backend URL when doing this:

```env
API_BASE_URL=https://your-app.onrender.com/api/v1
```

If you also test on a physical phone at the same time, keep a second `.env` (or swap the value) pointing to the Render URL for mobile too — both will use the same production backend.

---

## 9. Running Tests

### Backend tests

From `backend/` with `.venv` active:

```bash
pytest -q
```

Recommended first tests:

- User can register
- User can login
- User can create profile
- Discovery excludes blocked users
- User can send connection request
- Match is created after accepted request
- User cannot message without match
- User can create and join activity
- User can submit report

### Flutter tests

From `mobile/`:

```bash
flutter test
```

Recommended first widget tests:

- Login screen renders
- Login hero layers `school.png` behind `students.png`
- Bottom navigation renders
- Home screen renders
- Connect screen renders
- Profile screen uses `headshots.png`

---

## 10. Code Quality

### Backend

From `backend/`:

```bash
ruff check app scripts
ruff format app scripts
```

If Ruff is not installed:

```bash
pip install ruff
```

### Flutter

From `mobile/`:

```bash
dart format lib test
flutter analyze
```

---

## 11. Environment Variable Reference

Backend variables:

| Variable | Required | Local Example | Description |
|----------|----------|---------------|-------------|
| `APP_NAME` | No | `LC Connect API` | API display name |
| `ENVIRONMENT` | No | `development` | `development`, `staging`, or `production` |
| `DATABASE_URL` | Yes | `postgresql+psycopg://postgres:postgres@localhost:5432/lc_connect_dev` | Database connection string |
| `JWT_SECRET_KEY` | Yes | generated secret | JWT signing key |
| `JWT_ALGORITHM` | No | `HS256` | JWT algorithm |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | No | `10080` | Access token lifetime |
| `SUPABASE_URL` | Yes for image upload | `https://xxxxx.supabase.co` | Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Yes for image upload | secret key | Backend-only Supabase key |
| `SUPABASE_PROFILE_BUCKET` | Yes for image upload | `profile-images` | Storage bucket name |
| `CORS_ORIGINS` | No | localhost values | Allowed origins |

Flutter compile-time variables:

| Variable | Required | Example | Description |
|----------|----------|---------|-------------|
| `API_BASE_URL` | Yes for real API calls | `http://10.0.2.2:8000` | FastAPI backend URL |

---

## 12. Troubleshooting

### Backend error: `DATABASE_URL Field required`

Your `.env` file is missing, in the wrong folder, or not being read.

Fix:

1. Make sure `.env` is inside `backend/`.
2. Make sure it is named `.env`, not `.env.txt`.
3. Make sure it includes:

```env
DATABASE_URL=postgresql+psycopg://postgres:postgres@localhost:5432/lc_connect_dev
```

4. Make sure `app/config.py` includes:

```python
model_config = SettingsConfigDict(env_file=".env")
```

### Backend error: `JWT_SECRET_KEY Field required`

Add this to `backend/.env`:

```env
JWT_SECRET_KEY=paste_generated_secret_here
```

Generate one:

```bash
python -c "import secrets; print(secrets.token_urlsafe(64))"
```

### Backend cannot connect to PostgreSQL

Check:

1. PostgreSQL is running.
2. Database exists.
3. Username/password are correct.
4. `DATABASE_URL` is correct.

If using Docker:

```bash
docker compose -f infra/docker-compose.local.yml ps
```

### `python scripts/init_db.py` fails with table errors

If the local database has broken partial state, reset it.

Inside PostgreSQL:

```sql
DROP DATABASE lc_connect_dev;
CREATE DATABASE lc_connect_dev;
```

Then rerun:

```bash
python scripts/init_db.py
```

### Flutter asset error

If Flutter says it cannot find `students.png`, `school.png`, or `headshots.png`:

1. Confirm files are inside `mobile/assets/images/`.
2. Confirm `pubspec.yaml` includes the asset paths.
3. Run:

```bash
flutter pub get
```

4. Fully restart the app.

### Flutter app cannot reach backend from Android emulator

Use:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

### Flutter app cannot reach backend from physical phone

Use USB reverse forwarding:

```bash
adb reverse tcp:8000 tcp:8000
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Or use your computer IP:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8000
```

### `adb` is not recognized

Add Android SDK platform-tools to your PATH.

Common Windows path:

```text
C:\Users\<YourName>\AppData\Local\Android\Sdk\platform-tools
```

### Flutter doctor shows Android license issues

Run:

```bash
flutter doctor --android-licenses
flutter doctor
```

### `--dart-define` changes are not updating

Dart defines are compile-time values.

Stop the app completely and run again.

### Flutter web (Chrome) gets CORS errors against the Render backend

The production backend only allows origins listed in `CORS_ORIGINS`. Chrome running on a random port (e.g. `localhost:63918`) is not in that list.

Fix:

1. Pin the Flutter web port so it never changes:

```bash
flutter run -d chrome --web-port 8080
```

2. Add `http://localhost:8080` to `CORS_ORIGINS` on Render (Environment → CORS_ORIGINS):

```
http://localhost:8080,https://any-other-origin-you-have
```

3. Redeploy on Render (or wait for the next deploy to pick up the new env var).

After this, Chrome at `localhost:8080` is always allowed and the error disappears.

### Supabase image upload fails

Check:

1. `SUPABASE_URL` is correct.
2. `SUPABASE_SERVICE_ROLE_KEY` is correct.
3. Bucket exists and is named exactly `profile-images`.
4. The backend is receiving multipart form data correctly.
5. The Flutter app is sending the image to FastAPI, not directly to Supabase with the service role key.

---

## 13. Daily Development Workflow

Once the project is fully set up, your daily workflow is usually three terminals.

### Terminal 1 — PostgreSQL

If using Docker:

```bash
docker compose -f infra/docker-compose.local.yml up -d
```

If using installed PostgreSQL, make sure the PostgreSQL service is running.

### Terminal 2 — FastAPI backend

Windows:

```powershell
cd backend
.venv\Scripts\Activate.ps1
uvicorn app.main:app --reload
```

macOS / Linux:

```bash
cd backend
source .venv/bin/activate
uvicorn app.main:app --reload
```

### Terminal 3 — Flutter app

Physical Android over USB (primary workflow):

```bash
adb reverse tcp:8000 tcp:8000
cd mobile
flutter run
```

Android emulator — update `.env` first:

```env
API_BASE_URL=http://10.0.2.2:8000/api/v1
```

Then:

```bash
cd mobile
flutter run
```

iOS simulator on macOS — `.env` stays as `localhost`:

```bash
cd mobile
flutter run
```

Chrome (Flutter web) against the production Render backend:

```bash
cd lc_connect_mobile
flutter run -d chrome --web-port 8080
```

Make sure `http://localhost:8080` is in `CORS_ORIGINS` on Render and `API_BASE_URL` in `.env` points to the Render backend URL. See section 8.6 for full setup.

---

## Quick-Start Summary

After the full setup is done once:

```powershell
# Terminal 1 — backend
cd lc_connect_backend
.venv\Scripts\Activate.ps1
uvicorn app.main:app --reload

# Terminal 2 — Flutter (physical Android over USB)
adb reverse tcp:8000 tcp:8000
cd lc_connect_mobile
flutter run
```

The `.env` file inside `lc_connect_mobile/` controls the API URL. Default is `http://localhost:8000/api/v1` which works with ADB reverse tunneling on a physical device.
