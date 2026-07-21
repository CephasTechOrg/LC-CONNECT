# LC Connect — MVP To-Do Roadmap

This roadmap is designed to build the LC Connect MVP in the correct order without making the app too complicated early.

**Current confirmed stack**

- **Mobile app:** Flutter + Riverpod + supabase_flutter
- **Backend:** FastAPI (hosted on Render)
- **Local development database:** Local PostgreSQL
- **Production database:** Supabase PostgreSQL
- **Realtime messaging:** Supabase Realtime (WebSocket, RLS-protected)
- **Profile image storage:** Supabase Storage bucket (`profile-images`)
- **MVP audience:** Livingstone College students

---

## Phase 0 — Product Setup

- [x] Confirm final app name: LC Connect
- [x] Confirm official school spelling and branding usage: Livingstone College
- [x] Define primary MVP audience: Livingstone College students
- [x] Confirm MVP feature list
- [x] Decide mobile-first approach
- [x] Confirm Flutter as the mobile app framework
- [x] Confirm FastAPI as the backend framework
- [x] Confirm local PostgreSQL for local development
- [x] Confirm Supabase PostgreSQL for production
- [x] Confirm Supabase Storage bucket for profile images
- [ ] Decide whether first launch is private beta or open campus pilot
- [ ] Decide student verification method for MVP
- [ ] Create GitHub repository
- [x] Add documentation folder
- [x] Add core documentation to the repository

---

## Phase 1 — Design Planning

- [x] Sketch main screens
- [x] Define mobile navigation tabs
- [x] Define color palette
- [x] Define profile card design
- [x] Define activity card design
- [x] Generate login screen mockup
- [x] Generate home/dashboard mockup
- [x] Generate connect/discovery mockup
- [x] Generate activities mockup
- [x] Generate messages/chat mockup
- [x] Generate profile mockup
- [x] Generate reusable visual assets:
  - [x] `students.png`
  - [x] `school.png`
  - [x] `headshots.png`
- [x] Define onboarding flow
- [x] Define empty states
- [x] Define safety/report screens
- [x] Convert mockups into Flutter UI screens

Required MVP screens:

- [x] Welcome screen mockup
- [x] Register screen
- [x] Login screen mockup
- [x] Onboarding/profile setup screen
- [x] Home screen mockup
- [x] Connect/discovery screen mockup
- [x] Activity board screen mockup
- [x] Activity detail screen
- [x] Create activity screen
- [x] Messages screen mockup
- [x] Chat thread screen mockup
- [x] Profile screen mockup
- [x] Edit profile screen
- [x] Report/block screen

---

## Phase 2 — Backend Setup

> Backend starter note: the current backend starter uses `scripts/init_db.py` for first-run table creation and seed data. Add Alembic migrations before production deployment.

- [x] Create FastAPI backend project
- [ ] Create local Python virtual environment on each developer machine
- [x] Install FastAPI, Uvicorn, SQLAlchemy, Pydantic, PostgreSQL driver
- [x] Create `.env.example`
- [x] Configure database connection through `DATABASE_URL`
- [x] Support local PostgreSQL for development
- [x] Support Supabase PostgreSQL for production through environment variables
- [x] Add health check endpoint
- [x] Set up API versioning: `/api/v1`
- [x] Set up CORS for mobile development
- [x] Set up password hashing
- [x] Set up JWT authentication
- [x] Add Supabase Storage configuration for profile image uploads
- [ ] Add Alembic migrations
- [ ] Add production logging configuration
- [ ] Add backend test suite

---

## Phase 3 — Database Setup

Local development:

- [ ] Install PostgreSQL locally or run PostgreSQL through Docker
- [ ] Create local database: `lc_connect_dev`
- [ ] Add local `DATABASE_URL` to `.env`
- [ ] Run `python scripts/init_db.py`
- [ ] Confirm seed data is created successfully

Production:

- [x] Create Supabase project
- [x] Copy Supabase PostgreSQL connection string
- [x] Configure production `DATABASE_URL`
- [x] Create Supabase Storage bucket: `profile-images`
- [x] Configure Supabase Storage policies or backend-only upload rules
- [x] Store Supabase service role key only in backend environment variables
- [x] Confirm mobile app never exposes Supabase service role key
- [x] Enable Supabase Realtime publication on messages table
- [x] Apply RLS migration (`supabase/migrations/20260510000000_messages_rls.sql`)
- [x] Configure Supabase JWT Secret to match backend `JWT_SECRET_KEY`

Schema:

- [x] Create `users` table
- [x] Create `profiles` table
- [x] Create `interests` table
- [x] Create `user_interests` table
- [x] Create `languages` table
- [x] Create `user_languages` table
- [x] Create `looking_for_options` table
- [x] Create `user_looking_for` table
- [x] Create `connection_requests` table
- [x] Create `matches` table
- [x] Create `messages` table
- [x] Create `activities` table
- [x] Create `activity_participants` table
- [x] Create `blocks` table
- [x] Create `reports` table
- [x] Create `verification_requests` table
- [x] Add indexes
- [x] Seed interests, languages, and looking-for options

---

## Phase 4 — Auth API

- [x] Register endpoint
- [x] Login endpoint
- [x] Current user endpoint
- [x] Password hashing
- [x] JWT token generation
- [x] JWT token validation
- [x] Basic user status check
- [x] Prevent suspended users from logging in or using core endpoints

Endpoints:

OTP email verification:

- [x] Add OTP columns to users table (`verify_otp_hash`, `verify_otp_expires_at`)
- [x] `POST /api/v1/auth/send-otp` — send verification email
- [x] `POST /api/v1/auth/verify-otp` — verify OTP and mark user as verified
- [x] Build verify email screen in Flutter (`verify_email_screen.dart`)

Password reset:

- [x] Add reset OTP columns (`reset_otp_hash`, `reset_otp_expires_at`)
- [x] `POST /api/v1/auth/forgot-password`
- [x] `POST /api/v1/auth/reset-password`
- [x] Build forgot password screen in Flutter (`forgot_password_screen.dart`)

Endpoints:

- [x] `POST /api/v1/auth/register`
- [x] `POST /api/v1/auth/login`
- [x] `GET /api/v1/auth/me`

---

## Phase 5 — Profile API

- [x] Create profile model
- [x] Create profile schemas
- [x] Create profile update endpoint
- [x] Create get my profile endpoint
- [x] Add interests to profile
- [x] Add languages to profile
- [x] Add looking-for preferences to profile
- [x] Add profile completion logic
- [x] Add hide profile setting
- [x] Add profile image upload using Supabase Storage
- [ ] Add profile image delete/replace cleanup

Endpoints:

- [x] `GET /api/v1/profiles/me`
- [x] `PATCH /api/v1/profiles/me`
- [x] `GET /api/v1/profiles/{profile_id}`
- [x] `POST /api/v1/profiles/me/avatar`

---

## Phase 6 — Flutter Mobile App Setup

- [x] Install Flutter SDK
- [x] Install Android Studio and Android SDK
- [x] Accept Android SDK licenses
- [x] Run `flutter doctor` and fix all required issues
- [x] Create Flutter app inside `lc_connect_mobile/`
- [x] Add clean Flutter folder structure
- [x] Add app assets:
  - [x] `assets/images/students.png`
  - [x] `assets/images/school.png`
  - [x] `assets/images/headshots.png`
- [x] Register image assets in `pubspec.yaml`
- [x] Add Flutter packages:
  - [x] `dio`
  - [x] `flutter_secure_storage`
  - [x] `go_router`
  - [x] `flutter_riverpod` + `riverpod`
  - [x] `image_picker`
  - [x] `intl`
  - [x] `font_awesome_flutter`
  - [x] `supabase_flutter` (for Realtime message delivery)
- [x] Add app theme/colors
- [x] Add reusable UI components
- [x] Add navigation shell with bottom tabs
- [x] Add API client
- [x] Add secure token storage
- [x] Add app environment config using `--dart-define`
- [x] Connect Flutter app to backend health check

---

## Phase 7 — Flutter Auth Screens

- [x] Welcome/login mockup created
- [x] Build Flutter Welcome/Login screen
- [x] Layer `school.png` behind `students.png` correctly on Login screen
- [x] Build Register screen
- [x] Add form validation
- [x] Connect login form to backend
- [x] Connect register form to backend
- [x] Store JWT securely with `flutter_secure_storage`
- [x] Load current user on app start
- [x] Redirect unauthenticated users to login
- [x] Redirect new users to onboarding

---

## Phase 8 — Flutter Onboarding/Profile Setup

- [x] Build profile setup form (3-step wizard: About You / Your Vibe / Connect)
- [x] Add display name input (pre-filled from email prefix)
- [x] Add major input
- [x] Add class year picker (dropdown 2022–2031)
- [x] Add country/state input
- [x] Add short bio input
- [x] Add interests selector (animated chip grid, loaded from `/lookups`)
- [x] Add languages spoken selector (chip grid)
- [x] Add languages learning selector (chip grid)
- [x] Add looking-for selector (chip grid, required — at least 1)
- [x] Add profile image picker
- [x] Upload profile image to backend (`POST /api/v1/profiles/me/avatar`) — Supabase bucket configured and working
- [x] Submit profile to backend (`PATCH /api/v1/profiles/me`)
- [x] Show profile completion success (router auto-redirects to `/home` after `refreshProfile()`)

---

## Phase 9 — Discovery and Matching

Backend:

- [x] Create backend discovery service
- [x] Exclude current user
- [x] Exclude hidden/suspended users
- [x] Exclude blocked users
- [x] Exclude existing matches
- [x] Calculate simple match reasons
- [x] Return discovery cards

Flutter:

- [x] Build `StudentCard` component
- [x] Use `headshots.png` for all MVP/mockup avatar locations
- [x] Load discovery cards from backend
- [x] Add Connect action
- [x] Add Study Together action
- [x] Add Maybe Later action
- [x] Add Report/Block action
- [x] Show loading state
- [x] Show empty state

Endpoint:

- [x] `GET /api/v1/discovery/cards`

---

## Phase 10 — Connection Requests

Backend:

- [x] Create connection request endpoint
- [x] Create incoming requests endpoint
- [x] Create outgoing requests endpoint
- [x] Create accept request endpoint
- [x] Create decline request endpoint
- [x] Create match after acceptance
- [x] Prevent duplicate requests
- [x] Prevent blocked user requests

Flutter:

- [x] Build mobile requests screen
- [x] Show incoming requests
- [x] Show outgoing requests
- [x] Add accept request action
- [x] Add decline request action
- [x] Show match confirmation after accept

Endpoints:

- [x] `POST /api/v1/connections/request`
- [x] `GET /api/v1/connections/incoming`
- [x] `GET /api/v1/connections/outgoing`
- [x] `POST /api/v1/connections/{request_id}/accept`
- [x] `POST /api/v1/connections/{request_id}/decline`
- [x] `GET /api/v1/connections/matches`

---

## Phase 11 — Messaging

Backend:

- [x] Create message thread endpoint
- [x] Create send message endpoint
- [x] Enforce match-only messaging
- [x] Enforce block restrictions

Flutter:

- [x] Messages/chat mockup created
- [x] Build messages list screen
- [x] Build chat thread screen
- [x] Use `headshots.png` for chat avatars in MVP/mockup
- [x] Add simple message bubbles
- [x] Add timestamps
- [x] Add send message form
- [x] Add empty state for no messages
- [x] Connect screens to backend endpoints

Supabase Realtime (live message delivery):

- [x] Initialize Supabase client in `main.dart` with `SUPABASE_URL` and `SUPABASE_ANON_KEY`
- [x] Add `role: authenticated` to FastAPI JWT payload so Supabase can resolve `auth.uid()`
- [x] Call `Supabase.instance.client.realtime.setAuth(token)` on login, register, and app startup
- [x] Call `setAuth(null)` on logout
- [x] Subscribe to `PostgresChanges` INSERT events filtered by `match_id` in `chat_screen.dart`
- [x] Unsubscribe from channel in `dispose()` to prevent resource leaks
- [x] Add `_seenIds` deduplication so sender's message does not appear twice
- [x] Receiver sees new messages appear live without polling or refresh

Endpoints:

- [x] `GET /api/v1/messages/threads`
- [x] `GET /api/v1/messages/threads/{match_id}`
- [x] `POST /api/v1/messages/threads/{match_id}`

---

## Phase 12 — Activities Board

Backend:

- [x] Create activity model
- [x] Create activity schemas
- [x] Create activity endpoint
- [x] Create list activities endpoint
- [x] Create activity detail endpoint
- [x] Create join activity endpoint
- [x] Create leave activity endpoint
- [x] Add max participant logic

Flutter:

- [x] Activities mockup created
- [x] Build activity board screen
- [x] Build activity detail screen
- [x] Build create activity screen
- [x] Show joined activities
- [x] Add category filters
- [x] Add join activity action
- [x] Add leave activity action
- [x] Add empty state for no activities

Endpoints:

- [x] `POST /api/v1/activities`
- [x] `GET /api/v1/activities`
- [x] `GET /api/v1/activities/{activity_id}`
- [x] `POST /api/v1/activities/{activity_id}/join`
- [x] `DELETE /api/v1/activities/{activity_id}/leave`

---

## Phase 13 — Safety Features

Backend:

- [x] Create block endpoint
- [x] Create unblock endpoint
- [x] Create report endpoint
- [x] Hide blocked users from discovery
- [x] Prevent blocked messaging

Flutter:

- [x] Add report button to profiles/cards
- [x] Add block button to profiles/cards
- [x] Add report reason picker
- [x] Add safety confirmation messages
- [x] Add safe empty/error states
- [x] Add student-only access messaging

Endpoints:

- [x] `POST /api/v1/blocks/{user_id}`
- [x] `DELETE /api/v1/blocks/{user_id}`
- [x] `POST /api/v1/reports`

---

## Phase 14 — Admin MVP

The admin panel can be simple at first. It can be web-based later.

Backend:

- [x] Create admin role
- [x] Create admin-only permission check
- [x] List users
- [x] View reports
- [x] Suspend user
- [x] Remove activity
- [ ] Review verification requests

Future admin UI:

- [ ] Decide admin UI framework
- [ ] Build admin login
- [ ] Build users table
- [ ] Build reports review screen
- [ ] Build verification review screen
- [ ] Build activity moderation screen

Endpoints:

- [x] `GET /api/v1/admin/users`
- [x] `GET /api/v1/admin/reports`
- [x] `POST /api/v1/admin/users/{user_id}/suspend`
- [x] `POST /api/v1/admin/activities/{activity_id}/remove`

---

## Phase 15 — Testing

Backend tests:

- [ ] User can register
- [ ] User can login
- [ ] User can create profile
- [ ] User can upload profile image
- [ ] Discovery excludes blocked users
- [ ] Connection request can be sent
- [ ] Connection request can be accepted
- [ ] Match is created after accept
- [ ] User cannot message without match
- [ ] User cannot message after block
- [ ] User can create activity
- [ ] User can join activity
- [ ] User cannot join full activity
- [ ] Report can be submitted

Flutter tests (39 tests passing):

- [x] Auth provider unit tests
- [x] Register screen — form validation, student email domain enforcement
- [x] Messages screen — thread list renders, null partner handled, timestamps displayed
- [x] Chat screen — message bubbles render, send flow works
- [x] Profile model — `isVerified` parsed correctly, defaults to false when absent
- [x] Profile screen — verified badge shown when `isVerified: true`, hidden when false
- [x] Public profile screen — verified icon conditional on `isVerified`
- [ ] Login flow end-to-end test
- [ ] JWT stored securely (integration)
- [ ] Discovery cards load
- [ ] Connection request flow
- [ ] Activity board works
- [ ] Report/block works

---

## Phase 16 — Deployment

Backend:

- [x] Choose hosting: Render
- [x] Create production Supabase project
- [x] Configure production `DATABASE_URL`
- [x] Configure Supabase Storage bucket
- [x] Configure environment variables on Render
- [x] Run migrations / initialization in production
- [x] Set allowed CORS origins
- [ ] Add production logging

Flutter mobile:

- [ ] Configure app package name / bundle ID
- [ ] Configure app icon
- [ ] Configure splash screen
- [x] Create Android development build
- [x] Test on Android phone — register, login, and core flows verified
- [ ] Test on iPhone if available
- [x] Configure production API URL
- [ ] Prepare internal testing build

---

## Phase 17 — Pilot Launch

- [ ] Invite small group of students first
- [ ] Collect feedback
- [ ] Track signup rate
- [ ] Track profile completion
- [ ] Track connection requests
- [ ] Track match rate
- [ ] Track activity joins
- [ ] Watch for safety issues
- [ ] Fix bugs quickly
- [ ] Improve onboarding based on feedback

---

## Phase 18 — Future Features After MVP

Only add these after students are actually using the MVP:

- [x] Real-time messaging (implemented via Supabase Realtime — no polling)
- [ ] Thread list live preview (messages screen does not yet update without refresh)
- [ ] Push notifications (Firebase Cloud Messaging)
- [ ] Typing indicators (Supabase Realtime Broadcast)
- [ ] Read receipts
- [ ] Offline message queue (sqflite)
- [ ] AI-generated icebreakers
- [ ] Better recommendation engine
- [ ] Club/organization pages
- [ ] Group chats for activities
- [ ] Event approval flow
- [ ] Campus map
- [ ] Admin dashboard UI
- [ ] Web landing page
- [ ] Analytics dashboard
- [ ] Photo moderation
- [ ] Better search filters
- [ ] In-app announcements
- [ ] Student organization pages

---

## Build Priority Summary

Build first:

1. Backend environment setup
2. Local PostgreSQL database setup
3. Flutter project initialization
4. Flutter theme, assets, and navigation
5. Auth screens
6. Profile setup
7. Discovery cards
8. Connection requests
9. Matches/messages
10. Activities
11. Report/block

Everything else can wait.
