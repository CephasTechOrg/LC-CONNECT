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

### `app/`

Contains Expo Router screens and navigation.

Important screens:

- `auth/login.tsx` — login screen
- `auth/register.tsx` — registration screen
- `auth/onboarding.tsx` — first profile setup
- `tabs/home.tsx` — recommended students and activities
- `tabs/connect.tsx` — discovery card screen
- `tabs/activities.tsx` — activity board
- `tabs/messages.tsx` — message threads
- `tabs/profile.tsx` — profile page

### `src/components/`

Reusable UI components.

Examples:

- `StudentCard.tsx` — card shown in discovery
- `ActivityCard.tsx` — campus activity card
- `MatchReasonPill.tsx` — small tag showing why two students match
- `Button.tsx` — reusable button
- `Input.tsx` — reusable input

### `src/services/`

Functions that communicate with the FastAPI backend.

Example:

```ts
profileService.updateProfile(data)
discoveryService.getCards()
connectionService.sendRequest(profileId)
```

### `src/hooks/`

Reusable React hooks for app logic.

Example:

- `useAuth()`
- `useDiscovery()`
- `useActivities()`

### `src/types/`

TypeScript types matching backend response schemas.

## 4. Backend Folder Structure

Technology: **FastAPI + PostgreSQL + SQLAlchemy + Alembic**

Recommended structure:

```text
backend/
  app/
    main.py
    api/
      __init__.py
      v1/
        __init__.py
        router.py
        routes/
          auth.py
          profiles.py
          discovery.py
          connections.py
          messages.py
          activities.py
          safety.py
          admin.py
    core/
      config.py
      security.py
      permissions.py
      errors.py
    db/
      session.py
      base.py
      init_db.py
    models/
      user.py
      profile.py
      interest.py
      language.py
      connection.py
      message.py
      activity.py
      report.py
      block.py
      verification.py
    schemas/
      auth.py
      user.py
      profile.py
      discovery.py
      connection.py
      message.py
      activity.py
      report.py
      block.py
    services/
      auth_service.py
      profile_service.py
      discovery_service.py
      connection_service.py
      message_service.py
      activity_service.py
      safety_service.py
      admin_service.py
    repositories/
      user_repository.py
      profile_repository.py
      discovery_repository.py
      connection_repository.py
      message_repository.py
      activity_repository.py
      safety_repository.py
    utils/
      dates.py
      validators.py
      pagination.py
    tests/
      test_auth.py
      test_profiles.py
      test_connections.py
      test_activities.py
      test_messages.py
  alembic/
    versions/
  alembic.ini
  requirements.txt
  .env.example
  README.md
```

## 5. Backend Folder Explanation

### `main.py`

FastAPI app entry point.

Responsibilities:

- Create FastAPI app
- Add middleware
- Include API routers
- Add health check

### `api/v1/routes/`

Contains API route files.

Routes should stay thin. They should call service functions instead of containing all business logic.

Example:

```python
@router.post('/request')
def send_connection_request(...):
    return connection_service.send_request(...)
```

### `core/`

Core configuration and security.

Files:

- `config.py` — environment variables
- `security.py` — password hashing, JWT tokens
- `permissions.py` — admin/user checks
- `errors.py` — custom exceptions

### `db/`

Database connection setup.

Files:

- `session.py` — SQLAlchemy session
- `base.py` — base model imports
- `init_db.py` — optional startup database setup

### `models/`

SQLAlchemy ORM models that represent database tables.

Example models:

- `User`
- `Profile`
- `ConnectionRequest`
- `Match`
- `Message`
- `Activity`

### `schemas/`

Pydantic request/response schemas.

Use schemas to control what the frontend sends and receives.

### `services/`

Business logic.

This is where important rules should live:

- Users cannot message without a match
- Blocked users cannot interact
- Discovery excludes suspended users
- Matches are created only after accepted requests

### `repositories/`

Database queries.

Repositories help keep SQL/database logic away from route files.

### `tests/`

Backend tests.

Start with tests for:

- Auth
- Profile creation
- Connection request flow
- Message permission rules
- Activity join/leave
- Blocking behavior

## 6. Docs Folder Structure

```text
docs/
  overview.md
  project_description.md
  architecture.md
  folder_structure.md
  database.md
  to-do.md
```

## 7. Recommended Development Order

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
