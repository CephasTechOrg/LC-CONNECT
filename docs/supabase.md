# LC Connect — Supabase Setup Guide

This document covers every Supabase configuration decision made for LC Connect: project setup, storage, database connection strings, Realtime publications, and RLS policies. Read this before touching any Supabase setting.

---

## Table of Contents

1. [Why Supabase](#1-why-supabase)
2. [Project Creation](#2-project-creation)
3. [Important Key Distinction](#3-important-key-distinction)
4. [Database Connection Strings](#4-database-connection-strings)
5. [Profile Image Storage Bucket](#5-profile-image-storage-bucket)
6. [Supabase Realtime — Messages Table](#6-supabase-realtime--messages-table)
7. [Row-Level Security (RLS) for Realtime](#7-row-level-security-rls-for-realtime)
8. [Why We Do Not Use Supabase Auth](#8-why-we-do-not-use-supabase-auth)
9. [Environment Variable Reference](#9-environment-variable-reference)
10. [Common Mistakes](#10-common-mistakes)

---

## 1. Why Supabase

LC Connect uses Supabase for two specific things only:

| Purpose | Why Supabase |
|---|---|
| **Profile image storage** | Supabase Storage is free, has a simple SDK, and generates public URLs automatically |
| **Realtime message delivery** | Supabase Realtime broadcasts Postgres row inserts to connected Flutter clients without building WebSocket infrastructure |

LC Connect does **not** use Supabase Auth. Authentication is handled by the custom FastAPI JWT system. This is intentional — see [Section 8](#8-why-we-do-not-use-supabase-auth).

The Supabase Postgres database IS the production database. The FastAPI backend connects to it directly via the connection pooler.

---

## 2. Project Creation

1. Go to [supabase.com](https://supabase.com) and sign in.
2. Click **New Project**.
3. Choose a name (e.g., `lc-connect`).
4. Set a strong database password — save it somewhere safe.
5. Choose a region close to your users (e.g., **East US** for North Carolina).
6. Click **Create new project** and wait for it to provision.

After the project is created, you will need three things from the Supabase dashboard:

| Item | Where to find it | Used by |
|---|---|---|
| **Project URL** | Settings → API → Project URL | Backend + Flutter |
| **Anon key** | Settings → API → Project API keys → anon public | Flutter only |
| **Service role key** | Settings → API → Project API keys → service_role | Backend only — never in Flutter |
| **Database password** | Settings → Database → Database password | Connection string |
| **Transaction pooler URL** | Settings → Database → Connection string → Transaction | Backend DATABASE_URL |

---

## 3. Important Key Distinction

| Key | Who holds it | What it can do |
|---|---|---|
| `anon` (public) | Flutter app `.env` | Read public data, subscribe to Realtime, limited by RLS |
| `service_role` | Backend `.env` only | Bypass RLS, full admin access to all data and storage |

**Never put the `service_role` key in the Flutter app.** If someone decompiles the APK, they get full database access. The service role key lives only in the backend environment variables.

---

## 4. Database Connection Strings

Supabase provides two pooler options. LC Connect uses the **Transaction pooler**.

### Session pooler vs Transaction pooler

| | Session pooler | Transaction pooler |
|---|---|---|
| Port | 5432 | **6543** |
| Prepared statements | Supported | **Not supported** |
| Long-lived connections | Yes | No |
| `asyncpg` compatible | Needs extra config | Yes, with `statement_cache_size: 0` |
| Render/cloud deploy | Can time out | **Recommended for serverless/cloud** |

### Why Transaction pooler

LC Connect's Render deployment is serverless-adjacent (free tier spins down). The session pooler at port 5432 was timing out during tests. Transaction pooler at port 6543 is the correct choice for cloud/serverless deployments.

### Getting the connection string

In Supabase:

```
Settings → Database → Connection string → Transaction
```

The URL looks like:

```
postgresql://postgres.PROJECTREF:PASSWORD@aws-0-us-east-1.pooler.supabase.com:6543/postgres
```

### What the backend needs

The backend `database.py` automatically converts the URL to the `asyncpg` format:

```python
# postgresql:// → postgresql+asyncpg://
# Also strips trailing whitespace/newlines from copy-paste
def _async_url(url: str) -> str:
    url = url.strip()
    for prefix in ('postgresql://', 'postgres://'):
        if url.startswith(prefix):
            return 'postgresql+asyncpg://' + url[len(prefix):]
    return url
```

The backend also detects non-local connections and adds the required asyncpg settings:

```python
_connect_args = (
    {}
    if _is_local(_db_url)
    else {'ssl': 'require', 'statement_cache_size': 0}
)
```

`statement_cache_size: 0` disables asyncpg's prepared statement cache, which is required when using Transaction pooler (it does not maintain per-connection state between transactions).

### Set DATABASE_URL in production

Copy the Transaction pooler URL from Supabase, then set it in your Render dashboard:

```
Settings → Environment → DATABASE_URL = <paste URL>
```

Do not copy-paste trailing newlines — the `_async_url()` function strips them but it is better to be clean.

### Local development

For local development, use a local PostgreSQL database:

```env
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/lc_connect_db
```

The `_is_local()` check in `database.py` detects `localhost` or `127.0.0.1` and skips SSL/statement_cache settings.

---

## 5. Profile Image Storage Bucket

LC Connect stores user avatar images in a Supabase Storage bucket.

### Create the bucket

1. In Supabase: **Storage → New bucket**
2. Name: `profile-images`
3. Public: **Yes** (images need public URLs for Flutter's `Image.network`)
4. File size limit: set to `5 MB` or leave default

### How image upload works

```
Flutter picks image → sends to FastAPI (multipart form)
FastAPI backend → deletes old avatar files (all extensions)
FastAPI backend → uploads new file to Supabase Storage
FastAPI backend → returns cache-busted public URL
Flutter receives URL → stores in profile, Image.network renders it
```

The backend — not the Flutter app — calls Supabase Storage. This keeps the service role key off the device.

### Delete-before-upload pattern

Supabase Storage does not reliably overwrite files when uploading to the same path. To avoid conflicts on re-upload, the backend explicitly deletes all possible avatar files before uploading:

```python
for ext in ('jpg', 'jpeg', 'png', 'webp'):
    try:
        self.client.storage.from_(settings.supabase_profile_bucket).remove(
            [f'profiles/{user_id}/avatar.{ext}']
        )
    except Exception:
        pass  # file may not exist — that's fine
```

### Cache-busting

Flutter's `Image.network` caches images by URL. After a re-upload, the URL is the same so Flutter would show the old image. The backend appends a timestamp to force a fresh fetch:

```python
public_url = str(self.client.storage.from_(...).get_public_url(path))
return f'{public_url}?v={int(time.time())}'
```

### File path structure

```text
profile-images/
└── profiles/
    └── {user_id}/
        └── avatar.{ext}   # e.g., avatar.jpg
```

One avatar per user. The extension matches whatever the user uploaded.

---

## 6. Supabase Realtime — Messages Table

Supabase Realtime broadcasts Postgres changes (INSERT, UPDATE, DELETE) to subscribed clients over WebSocket. LC Connect uses it to deliver new chat messages to the Flutter app instantly.

### How Supabase Realtime works

1. Postgres writes a row to the `messages` table.
2. The `supabase_realtime` Postgres **publication** captures that change.
3. Supabase's Realtime server reads the WAL (Write-Ahead Log) and forwards the event.
4. The Flutter client receives the INSERT event through its channel subscription.
5. Flutter adds the new message to the chat list and scrolls to the bottom.

### Enabling Realtime on the messages table

This must be done once in the Supabase dashboard:

```
Supabase Dashboard
→ Database
→ Replication
→ supabase_realtime  (the default publication)
→ Tables section
→ Find "messages" (schema: public)
→ Toggle the switch ON
```

You will see two entries named "messages" in the table list:
- `messages` with schema `public` — **this is the one to enable**
- `messages` with schema `realtime` — this is Supabase's internal table, do not touch it

After toggling, the publication is active. No backend code changes are needed — Supabase handles the WAL replication automatically.

### Verifying it is enabled

In Supabase SQL Editor, run:

```sql
SELECT schemaname, tablename
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime';
```

You should see `public | messages` in the results.

---

## 7. Row-Level Security (RLS) for Realtime

Supabase Realtime respects RLS policies. When a Flutter client subscribes using the `anon` key (not a Supabase JWT), Supabase evaluates `SELECT` permissions for the `anon` role.

LC Connect uses a custom JWT (issued by FastAPI), not Supabase Auth tokens. This means the Supabase client in Flutter always authenticates as `anon`.

For the realtime subscription to receive INSERT events, you must add a SELECT policy for the anon role on the `messages` table.

### SQL to run (one-time setup)

Open **Supabase → SQL Editor** and run:

```sql
-- Allow the anon role to receive realtime events for messages.
-- Actual write security is enforced by the backend API (JWT required to POST a message).
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anon_can_read_messages"
  ON public.messages
  FOR SELECT
  TO anon
  USING (true);
```

**Why this is safe:**
- The `anon` key is read-only for this policy — only SELECT is granted.
- Write operations (INSERT) go through the FastAPI backend which requires a valid JWT. Nobody can post a message without logging in through the app.
- Realtime does not expose messages from other conversations — the Flutter client only subscribes to a specific `match_id`, and the Supabase Realtime server filters events server-side.

### If RLS is already enabled with no policies

If the table already has `ENABLE ROW LEVEL SECURITY` set but no policies, add only the policy:

```sql
CREATE POLICY "anon_can_read_messages"
  ON public.messages
  FOR SELECT
  TO anon
  USING (true);
```

The `ALTER TABLE` statement is idempotent — it is safe to run even if RLS is already enabled.

---

## 8. Why We Do Not Use Supabase Auth

Supabase has a built-in auth system. LC Connect deliberately does not use it.

**Reason:** LC Connect uses a custom FastAPI JWT auth system that was already built, tested, and deployed before Supabase was introduced. Migrating to Supabase Auth would require:

- Replacing all backend JWT logic
- Migrating existing user accounts
- Rewiring all Flutter auth flows

**Trade-off this creates for Realtime:**
- Supabase Auth users get a Supabase JWT that Realtime uses for RLS evaluation
- LC Connect users authenticate with a custom JWT that Supabase does not understand
- Therefore the Flutter Supabase client always acts as `anon`
- This is why the permissive `anon` SELECT policy is required

**This is acceptable for LC Connect** because:
- The security boundary for writes is the FastAPI backend (requires LC Connect JWT)
- Realtime is read-only (subscribes to events, does not write)
- The data in messages is not sensitive to the point where anon-read is a real risk

If LC Connect ever migrates to Supabase Auth, the `anon` RLS policy can be replaced with a proper user-specific policy.

---

## 9. Environment Variable Reference

### Backend `.env`

```env
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
SUPABASE_PROFILE_BUCKET=profile-images
DATABASE_URL=postgresql://postgres.YOUR_PROJECT_REF:PASSWORD@aws-0-us-east-1.pooler.supabase.com:6543/postgres
```

### Flutter `.env`

```env
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

Note: `SUPABASE_URL` appears in both. The backend uses it with the service role key for storage operations. Flutter uses it with the anon key for Realtime subscriptions.

---

## 10. Common Mistakes

### Wrong port in DATABASE_URL

Using port `5432` (Session pooler) instead of `6543` (Transaction pooler) causes connection timeouts on Render. Always use `6543` for production.

### Enabling the wrong "messages" table

The Supabase Replication UI shows two entries named "messages":
- `public.messages` — your app's table ✅
- `realtime.messages` — Supabase's internal subscription tracking table ❌

Enable only `public.messages`.

### Forgetting the RLS policy

Without the anon SELECT policy, the realtime subscription connects successfully but receives zero events. The channel reports as subscribed but nothing arrives. Add the policy from Section 7.

### Putting service_role key in Flutter

The service role key bypasses all RLS and has full database admin access. It must never be in the Flutter app or any client-side code.

### Copy-pasting DATABASE_URL with trailing newline

Copying the URL from the Supabase dashboard sometimes includes a trailing newline. Postgres will throw `database "postgres\n" does not exist`. The `_async_url()` function in `database.py` handles this with `.strip()`, but always clean the value in the Render dashboard too.
