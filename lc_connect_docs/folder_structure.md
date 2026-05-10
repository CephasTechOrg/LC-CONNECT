# LC Connect — Folder Structure

This document defines the recommended folder structure for the MVP.

The project should be separated into a mobile app and backend API.

```text
lc-connect/
  mobile/
  backend/
  docs/
  README.md
```

## 1. Root Folder

```text
lc-connect/
  lc_connect_mobile/   # Flutter app
  lc_connect_backend/  # FastAPI backend
  supabase/            # Supabase migrations
  lc_connect_docs/     # Project documentation
  README.md            # Main project README
  .gitignore
```

## 2. Mobile App Folder Structure

Technology: **Flutter + Dart + Riverpod + supabase_flutter**

Actual structure:

```text
lc_connect_mobile/
  lib/
    main.dart                        # app entry point — Supabase.initialize, ProviderScope
    core/
      api/
        api_client.dart              # Dio HTTP client with JWT interceptor
        health_provider.dart         # backend connectivity check
      constants/
        app_constants.dart           # shared constants
      router/
        app_router.dart              # GoRouter navigation and auth guards
      storage/
        secure_storage.dart          # flutter_secure_storage JWT persistence
      theme/
        app_theme.dart               # ThemeData, AppColors
      widgets/
        avatar_widget.dart           # reusable avatar with fallback initials
    features/
      auth/
        providers/
          auth_provider.dart         # AuthNotifier — login, register, logout, setAuth
        screens/
          login_screen.dart
          register_screen.dart
          verify_email_screen.dart
          forgot_password_screen.dart
      onboarding/
        providers/
          onboarding_provider.dart
        screens/
          onboarding_screen.dart
      discovery/
        providers/
          discovery_provider.dart
        screens/
          discovery_screen.dart
      connections/
        providers/
          connections_provider.dart
        screens/
          connections_screen.dart
      messages/
        providers/
          messages_provider.dart     # thread list state
        screens/
          messages_screen.dart       # conversation list
          chat_screen.dart           # individual chat with Realtime subscription
      activities/
        providers/
          activities_provider.dart
        screens/
          activities_screen.dart
          activity_detail_screen.dart
          create_activity_screen.dart
      profile/
        providers/
          profile_provider.dart      # MyProfile, PublicProfile models
        screens/
          profile_screen.dart
          public_profile_screen.dart
          edit_profile_screen.dart
      home/
        screens/
          home_screen.dart
      safety/
        providers/
          safety_provider.dart
        widgets/
          safety_sheet.dart
    shared/
      widgets/
        nav_shell.dart               # bottom navigation wrapper
  test/
    features/
      auth/
      messages/
      profile/
  assets/
  pubspec.yaml
  .env                               # SUPABASE_URL, SUPABASE_ANON_KEY, API_BASE_URL
```

## 3. Mobile App Folder Explanation

### `lib/main.dart`

App entry point. Calls `WidgetsFlutterBinding.ensureInitialized()`, loads `.env`, initialises Supabase, then starts the app inside a `ProviderScope`.

### `lib/core/`

Cross-feature infrastructure shared by all features.

- `api_client.dart` — Dio client with a JWT interceptor that attaches `Authorization: Bearer <token>` to every request
- `app_router.dart` — GoRouter with redirect guards for unauthenticated and unverified users
- `secure_storage.dart` — read/write/delete the JWT token from device secure storage
- `app_theme.dart` — `ThemeData` and `AppColors` used everywhere

### `lib/features/`

One sub-folder per feature. Each feature contains:

- `providers/` — Riverpod `AsyncNotifierProvider` or `FutureProvider` for state
- `screens/` — `ConsumerWidget` or `ConsumerStatefulWidget` screens

Key provider notes:

- `auth_provider.dart` — manages `AuthUser?` state; calls `Supabase.instance.client.realtime.setAuth(token)` after every login/register/startup and `setAuth(null)` on logout
- `chat_screen.dart` — manages a Supabase Realtime channel subscription per conversation; subscribes in `initState()`, unsubscribes in `dispose()`

### `lib/shared/`

Widgets used across multiple features (e.g., `nav_shell.dart` — bottom navigation bar with tab routing).

## 4. Backend Folder Structure

Technology: **FastAPI + PostgreSQL (Supabase) + SQLAlchemy + Alembic**

Actual structure:

```text
lc_connect_backend/
  app/
    main.py              # FastAPI app, CORS, router includes
    config.py            # Settings from .env via pydantic-settings
    database.py          # async SQLAlchemy engine and session
    dependencies.py      # get_current_user dependency (JWT → User)
    models.py            # all SQLAlchemy ORM models in one file
    schemas.py           # all Pydantic request/response schemas
    security.py          # password hashing, JWT create/decode
    services.py          # business logic (messaging rules, discovery filters)
    email.py             # OTP email sending
    seed.py              # seed interests, languages, looking-for options
    routers/
      auth.py            # register, login, verify-email, forgot-password
      profiles.py        # profile setup and retrieval
      discovery.py       # discovery cards
      connections.py     # connection requests and match creation
      messages.py        # message threads and send
      activities.py      # activity CRUD and join/leave
      safety.py          # block and report
      admin.py           # admin moderation endpoints
      lookups.py         # interests, languages, looking-for options
  alembic/
    versions/
      3ffad56200ff_initial_schema.py
  alembic.ini
  requirements.txt
  .env
  .env.example
```

## 5. Backend Folder Explanation

### `main.py`

FastAPI app entry point. Creates the FastAPI app, adds CORS middleware, and includes all routers.

### `routers/`

Thin route files. Business logic lives in `services.py`, not here.

### `models.py`

All SQLAlchemy ORM models in a single file: `User`, `Profile`, `Interest`, `Language`, `LookingForOption`, `UserLanguage`, `ConnectionRequest`, `Match`, `Message`, `Activity`, `ActivityParticipant`, `Block`, `Report`, `VerificationRequest`.

### `schemas.py`

All Pydantic request/response schemas. Controls what the frontend sends and receives.

### `services.py`

Business logic. This is where important rules live:

- Users cannot message without a match
- Blocked users cannot interact
- Discovery excludes blocked and hidden users
- Matches are created only after an accepted connection request

### `security.py`

Password hashing (bcrypt) and JWT token creation/decoding. The JWT payload includes `role: authenticated` so that Supabase can verify the token and resolve `auth.uid()` in RLS policies.

### `dependencies.py`

FastAPI dependency `get_current_user` — decodes the Bearer JWT and returns the authenticated `User`.

## 6. Supabase Folder

```text
supabase/
  migrations/
    20260510000000_messages_rls.sql   # RLS policies for the messages table
```

The `supabase/migrations/` folder holds versioned SQL files for database-level changes that Alembic does not manage (RLS policies, publications). Run these in **Supabase Dashboard → SQL Editor** or via `supabase db push` when setting up a new environment. See `lc_connect_docs/security_rls_messages.md` for details.

## 7. Docs Folder Structure

```text
lc_connect_docs/
  project_description.md    # app vision, MVP features, user stories
  architecture.md           # system diagram, tech stack, data flows
  folder_structure.md       # this file — folder layout and explanations
  database.md               # table schemas, column names, RLS notes
  realtime-messaging.md     # Supabase Realtime implementation end-to-end
  security_rls_messages.md  # RLS setup, JWT wiring, policy documentation
```

## 8. Recommended Development Order

Build in this order:

1. Backend project setup
2. Database models/migrations
3. Auth/register/login
4. Profile setup
5. Mobile app setup
6. Mobile auth screens
7. Profile onboarding screens
8. Discovery cards
9. Connection requests
10. Matches and messaging
11. Activities board
12. Report/block
13. Testing and campus pilot
