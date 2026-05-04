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
  mobile/              # React Native Expo app
  backend/             # FastAPI backend
  docs/                # Project documentation
  README.md            # Main project README
  .gitignore
```

## 2. Mobile App Folder Structure

Technology: **React Native + Expo + TypeScript**

Recommended structure:

```text
mobile/
  app/
    _layout.tsx
    index.tsx
    auth/
      login.tsx
      register.tsx
      onboarding.tsx
    tabs/
      _layout.tsx
      home.tsx
      connect.tsx
      activities.tsx
      messages.tsx
      profile.tsx
    profile/
      edit.tsx
      settings.tsx
    activities/
      create.tsx
      [activityId].tsx
    messages/
      [matchId].tsx
    connections/
      requests.tsx
  src/
    components/
      cards/
        StudentCard.tsx
        ActivityCard.tsx
        MatchReasonPill.tsx
      forms/
        ProfileForm.tsx
        ActivityForm.tsx
      ui/
        Button.tsx
        Input.tsx
        Tag.tsx
        Avatar.tsx
        EmptyState.tsx
    constants/
      colors.ts
      lookingFor.ts
      interests.ts
      languages.ts
    hooks/
      useAuth.ts
      useProfile.ts
      useDiscovery.ts
      useActivities.ts
      useMessages.ts
    lib/
      api.ts
      authStorage.ts
      queryClient.ts
    services/
      authService.ts
      profileService.ts
      discoveryService.ts
      connectionService.ts
      activityService.ts
      messageService.ts
      safetyService.ts
    types/
      auth.ts
      profile.ts
      discovery.ts
      connections.ts
      activities.ts
      messages.ts
    utils/
      formatDate.ts
      validators.ts
  assets/
    images/
    icons/
  app.json
  package.json
  tsconfig.json
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
