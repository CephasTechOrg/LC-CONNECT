# LC Connect Backend Starter

This is the copy-ready FastAPI backend starter for **LC Connect**, the mobile-first campus connection app for Livingstone College students.

## What this backend includes

- Student registration and login
- JWT authentication
- Student profiles
- Interests, languages, and looking-for preferences
- Discovery cards with explainable matching logic
- Mutual connection requests and matches
- Match-only messaging
- Activities board
- Join/leave activities
- Supabase Storage bucket upload for profile images
- Block/report safety tools
- Basic admin endpoints
- Database seed data

## Stack

- FastAPI
- PostgreSQL, including Supabase Postgres
- SQLAlchemy async ORM
- Supabase Storage for profile images
- JWT auth

## Setup

```bash
cd backend
python -m venv .venv

# Windows PowerShell
.venv\Scripts\Activate.ps1

# macOS/Linux
source .venv/bin/activate

pip install -r requirements.txt
cp .env.example .env
```

Fill `.env` with your real values.

```env
DATABASE_URL=postgresql+asyncpg://postgres:YOUR_PASSWORD@YOUR_SUPABASE_HOST:5432/postgres
JWT_SECRET_KEY=replace-this-with-a-long-random-secret
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
SUPABASE_PROFILE_BUCKET=profile-images
```

Important: keep `SUPABASE_SERVICE_ROLE_KEY` only on the backend. Never put it inside the mobile app.

## Create Supabase Storage bucket

In Supabase dashboard:

1. Go to Storage.
2. Create a bucket named `profile-images`.
3. For MVP, you can make it public so profile images display easily.
4. Later, move to signed URLs/private buckets if needed.

## Initialize database tables and seed lookup data

```bash
python scripts/init_db.py
```

## Start backend

```bash
uvicorn app.main:app --reload
```

Open:

```text
http://127.0.0.1:8000/docs
```

## Main endpoints

```text
GET    /health
POST   /api/v1/auth/register
POST   /api/v1/auth/login
GET    /api/v1/auth/me
GET    /api/v1/lookups
GET    /api/v1/profiles/me
PATCH  /api/v1/profiles/me
POST   /api/v1/profiles/me/avatar
GET    /api/v1/profiles/{profile_id}
GET    /api/v1/discovery/cards
POST   /api/v1/connections/request
GET    /api/v1/connections/incoming
GET    /api/v1/connections/outgoing
POST   /api/v1/connections/{request_id}/accept
POST   /api/v1/connections/{request_id}/decline
GET    /api/v1/connections/matches
GET    /api/v1/messages/threads
GET    /api/v1/messages/threads/{match_id}
POST   /api/v1/messages/threads/{match_id}
POST   /api/v1/activities
GET    /api/v1/activities
GET    /api/v1/activities/{activity_id}
POST   /api/v1/activities/{activity_id}/join
DELETE /api/v1/activities/{activity_id}/leave
POST   /api/v1/blocks/{user_id}
DELETE /api/v1/blocks/{user_id}
POST   /api/v1/reports
GET    /api/v1/admin/users
GET    /api/v1/admin/reports
POST   /api/v1/admin/users/{user_id}/suspend
POST   /api/v1/admin/activities/{activity_id}/remove
```

## Mobile app note

The React Native Expo app should send the JWT like this:

```http
Authorization: Bearer <access_token>
```

For profile images, upload to:

```text
POST /api/v1/profiles/me/avatar
```

FastAPI uploads the image to Supabase Storage and saves the public URL in PostgreSQL.
