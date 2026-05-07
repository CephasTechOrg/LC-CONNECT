# LC Connect — Documentation

This folder contains all technical and product documentation for the LC Connect MVP.

## What is LC Connect

LC Connect is a student-only mobile platform for Livingstone College students to safely find friends, study partners, language exchange partners, campus activities, and open connections through profiles, matching cards, mutual connections, real-time messaging, and an activity board.

The app should **not** feel like a dating app. It should feel like a safe campus connection platform that helps students break social barriers.

## Actual Technology Stack (as built)

| Layer | Technology |
|---|---|
| Mobile app | Flutter (Dart) |
| Backend API | FastAPI (Python) |
| Database | PostgreSQL on Supabase |
| Image storage | Supabase Storage |
| Real-time messaging | Supabase Realtime |
| Deployment | Render (backend), physical APK (Android) |
| Auth | Custom FastAPI JWT (not Supabase Auth) |

## Documentation Files

| File | Purpose |
|---|---|
| `overview.md` | High-level product vision, users, goals, and MVP scope |
| `project_description.md` | Full project description, problem, solution, features, and user flows |
| `architecture.md` | Technical architecture, system components, API areas, and data flows |
| `folder_structure.md` | Frontend and backend folder structure |
| `database.md` | PostgreSQL database design, tables, relationships, and schema |
| `setup.md` | Full local development setup guide |
| `supabase.md` | **Supabase setup** — storage, connection strings, Realtime, RLS policies |
| `realtime-messaging.md` | **Real-time messaging** — how it works end-to-end, Flutter code, Supabase config, deduplication |
| `deployment.md` | **Render deployment** — render.yaml, env vars, every failure we hit and how we fixed it |
| `todo.md` | Feature development progress and remaining tasks |

## Quick Links for Common Tasks

### Setting up Supabase for the first time
→ Read `supabase.md`

### Enabling real-time messages (Supabase Replication + RLS)
→ Read `supabase.md` sections 6 and 7, then `realtime-messaging.md`

### Deploying the backend to Render
→ Read `deployment.md`

### Setting up local development from scratch
→ Read `setup.md`

### Understanding the database schema
→ Read `database.md`

## Feature Status

| Feature | Status |
|---|---|
| Auth — login, register, logout | Done |
| Onboarding — 3-step profile setup | Done |
| Discovery — match cards with real data | Done |
| Connections — incoming/outgoing, accept/decline | Done |
| Messages + Chat — threads and chat screen | Done |
| Real-time messaging — Supabase Realtime | Done |
| Activities — list, detail, create, join/leave | Done |
| Profile screen — my profile with stats | Done |
| Public profile — view other users | Done |
| Edit profile | Done |
| Safety — report and block | Done |
| Avatar upload — Supabase Storage | Done |
| Home screen — real data (discovery, activities, matches) | Done |
| Backend deployed to Render | Done |
| Android APK built and tested | Done |
| Forgot password — reset flow | Pending |
| Email verification — .edu check | Pending |
| Push notifications | Pending |
| iOS build + TestFlight | Pending |
| Google Play Store submission | Pending |
