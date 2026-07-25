# LC Connect — Documentation

All technical, product, and security documentation for LC Connect, grouped into folders by concern.

## What is LC Connect

A student-only mobile platform for Livingstone College students to safely find friends, study
partners, language-exchange partners, campus activities, groups, and open connections — through
profiles, matching cards, mutual connections, real-time messaging, campus groups, and an activity
board. It should feel like a **safe campus connection platform**, not a dating app.

## Technology stack (as built)

| Layer | Technology |
|---|---|
| Mobile app | Flutter (Dart) |
| Backend API | FastAPI (Python) |
| Database | PostgreSQL on Supabase |
| Image storage | Supabase Storage |
| Real-time | Custom FastAPI WebSocket gateway (+ Supabase Realtime for RLS-guarded direct reads) |
| Auth | **Supabase Auth** (JWT verified by FastAPI); legacy custom JWT retained behind a flag, unmounted |
| Push | Firebase Cloud Messaging / APNs |
| Deployment | Render (backend), Android APK |

---

## Documentation map

Everything lives in one of five folders (each has its own README index):

### 📦 [`getting-started/`](./getting-started/) — setup & ops
First-time Mac setup, daily workflow, Supabase, email, and Render deployment.

### 🏗️ [`architecture/`](./architecture/) — how the system is built
System architecture, database schema, real-time messaging, image storage, folder layout.

### ✨ [`features/`](./features/) — feature deep-dives
- [`groups/`](./features/groups/) — campus communities (behavior & policy reference, decision log, API, build log)
- [`notifications/`](./features/notifications/) — push, the in-app notification center, unread counts

### 🔒 [`security/`](./security/) — security, safety & compliance
- [`overview.md`](./security/overview.md) — auth, authorization (no IDOR), encryption posture (why not E2EE)
- [`rate_limiting.md`](./security/rate_limiting.md) — login vs abuse limits, env vars, 429 UX
- [`rls_messages.md`](./security/rls_messages.md) — Supabase RLS on messages
- [`audit_and_data_retention.md`](./security/audit_and_data_retention.md) — deletion, evidence snapshots, moderator playbook

### 🎯 [`product/`](./product/) — vision, scope, progress
Product overview, full project description, the to-do log, and an archived external review.

---

## Quick links

| I want to… | Go to |
|---|---|
| Set up my Mac for the first time | [`getting-started/local_dev_setup.md`](./getting-started/local_dev_setup.md) |
| Start work today | [`getting-started/daily_dev_start.md`](./getting-started/daily_dev_start.md) |
| Deploy the backend to Render | [`getting-started/deployment.md`](./getting-started/deployment.md) |
| Understand the database schema | [`architecture/database.md`](./architecture/database.md) |
| Understand real-time messaging | [`architecture/realtime-messaging.md`](./architecture/realtime-messaging.md) |
| Know how groups work (policies, roles, limits) | [`features/groups/groups_reference.md`](./features/groups/groups_reference.md) |
| Understand notifications (push + in-app) | [`features/notifications/`](./features/notifications/) |
| Review the security & access-control model | [`security/overview.md`](./security/overview.md) |
| Change a rate limit or the group size cap | [`security/rate_limiting.md`](./security/rate_limiting.md) |
| Answer a data-deletion / audit question | [`security/audit_and_data_retention.md`](./security/audit_and_data_retention.md) |
