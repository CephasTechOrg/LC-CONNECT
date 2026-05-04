# LC Connect — MVP To-Do Roadmap

This roadmap is designed to build the MVP in the correct order without making the app too complicated early.

## Phase 0 — Product Setup

- [x] Confirm final app name: LC Connect, BlueBridge, CampusBridge, or another name
- [x] Confirm official school spelling and branding usage
- [x] Define primary MVP audience: Livingstone College students
- [x] Confirm MVP feature list
- [ ] Decide whether first launch is private beta or open campus pilot
- [ ] Decide student verification method for MVP
- [ ] Create GitHub repository
- [x] Add documentation folder
- [x] Add this documentation to the repository

## Phase 1 — Design Planning

- [x] Sketch main screens
- [x] Define mobile navigation tabs
- [x] Define color palette
- [x] Define profile card design
- [x] Define activity card design
- [ ] Define onboarding flow
- [ ] Define empty states
- [ ] Define safety/report screens

Required MVP screens:

- [x] Welcome screen
- [ ] Register screen
- [x] Login screen
- [ ] Onboarding/profile setup screen
- [x] Home screen
- [x] Connect/discovery screen
- [x] Activity board screen
- [ ] Activity detail screen
- [ ] Create activity screen
- [x] Messages screen
- [x] Chat thread screen
- [x] Profile screen
- [ ] Edit profile screen
- [ ] Report/block screen

## Phase 2 — Backend Setup

> Backend starter note: this package uses `scripts/init_db.py` for first-run table creation and seed data. Add Alembic migrations before production deployment.


- [x] Create FastAPI backend project
- [ ] Create virtual environment
- [x] Install FastAPI, Uvicorn, SQLAlchemy, Pydantic, PostgreSQL driver
- [x] Create `.env.example`
- [x] Configure database connection
- [x] Add health check endpoint
- [x] Set up API versioning: `/api/v1`
- [x] Set up CORS for mobile development
- [x] Set up password hashing
- [x] Set up JWT authentication

## Phase 3 — Database Setup

- [ ] Create PostgreSQL database
- [ ] Configure Alembic migrations
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

- [x] `POST /api/v1/auth/register`
- [x] `POST /api/v1/auth/login`
- [x] `GET /api/v1/auth/me`

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

Endpoints:

- [x] `GET /api/v1/profiles/me`
- [x] `PATCH /api/v1/profiles/me`
- [x] `GET /api/v1/profiles/{profile_id}`

## Phase 6 — Mobile App Setup

- [ ] Create Expo React Native app
- [ ] Add TypeScript
- [ ] Add Expo Router
- [ ] Add API client
- [ ] Add secure token storage
- [ ] Add basic UI components
- [ ] Add app theme/colors
- [ ] Add navigation tabs
- [ ] Connect app to backend health check

## Phase 7 — Mobile Auth Screens

- [x] Welcome screen
- [ ] Register screen
- [x] Login screen
- [ ] Store token securely
- [ ] Load current user on app start
- [ ] Redirect unauthenticated users to login
- [ ] Redirect new users to onboarding

## Phase 8 — Onboarding/Profile Setup

- [ ] Build profile setup form
- [ ] Add display name input
- [ ] Add major input
- [ ] Add class year picker
- [ ] Add country/state input
- [ ] Add short bio input
- [ ] Add interests selector
- [ ] Add languages spoken selector
- [ ] Add languages learning selector
- [ ] Add looking-for selector
- [ ] Submit profile to backend
- [ ] Show profile completion success

## Phase 9 — Discovery and Matching

- [x] Create backend discovery service
- [x] Exclude current user
- [x] Exclude hidden/suspended users
- [x] Exclude blocked users
- [x] Exclude existing matches
- [x] Calculate simple match reasons
- [x] Return discovery cards
- [ ] Build mobile StudentCard component
- [ ] Add Connect action
- [ ] Add Study Together action
- [ ] Add Maybe Later action
- [ ] Add Report/Block action

Endpoint:

- [x] `GET /api/v1/discovery/cards`

## Phase 10 — Connection Requests

- [x] Create connection request endpoint
- [x] Create incoming requests endpoint
- [x] Create outgoing requests endpoint
- [x] Create accept request endpoint
- [x] Create decline request endpoint
- [x] Create match after acceptance
- [x] Prevent duplicate requests
- [x] Prevent blocked user requests
- [ ] Build mobile requests screen
- [ ] Show match confirmation after accept

Endpoints:

- [x] `POST /api/v1/connections/request`
- [x] `GET /api/v1/connections/incoming`
- [x] `GET /api/v1/connections/outgoing`
- [x] `POST /api/v1/connections/{request_id}/accept`
- [x] `POST /api/v1/connections/{request_id}/decline`
- [x] `GET /api/v1/connections/matches`

## Phase 11 — Messaging

- [x] Create message thread endpoint
- [x] Create send message endpoint
- [x] Enforce match-only messaging
- [x] Enforce block restrictions
- [ ] Build messages list screen
- [ ] Build chat thread screen
- [ ] Add simple message bubbles
- [ ] Add timestamps
- [ ] Add empty state for no messages

Endpoints:

- [x] `GET /api/v1/messages/threads`
- [x] `GET /api/v1/messages/threads/{match_id}`
- [x] `POST /api/v1/messages/threads/{match_id}`

## Phase 12 — Activities Board

- [x] Create activity model
- [x] Create activity schemas
- [x] Create activity endpoint
- [x] Create list activities endpoint
- [x] Create activity detail endpoint
- [x] Create join activity endpoint
- [x] Create leave activity endpoint
- [x] Add max participant logic
- [ ] Build activity board screen
- [ ] Build activity detail screen
- [ ] Build create activity screen
- [ ] Show joined activities

Endpoints:

- [x] `POST /api/v1/activities`
- [x] `GET /api/v1/activities`
- [x] `GET /api/v1/activities/{activity_id}`
- [x] `POST /api/v1/activities/{activity_id}/join`
- [x] `DELETE /api/v1/activities/{activity_id}/leave`

## Phase 13 — Safety Features

- [x] Create block endpoint
- [x] Create unblock endpoint
- [x] Create report endpoint
- [x] Hide blocked users from discovery
- [x] Prevent blocked messaging
- [ ] Add report button to profiles/cards
- [ ] Add block button to profiles/cards
- [ ] Add report reason picker
- [ ] Add safety confirmation messages

Endpoints:

- [x] `POST /api/v1/blocks/{user_id}`
- [x] `DELETE /api/v1/blocks/{user_id}`
- [x] `POST /api/v1/reports`

## Phase 14 — Admin MVP

The admin panel can be simple at first. It can be web-based later.

- [x] Create admin role
- [x] Create admin-only permission check
- [x] List users
- [x] View reports
- [x] Suspend user
- [x] Remove activity
- [ ] Review verification requests

Endpoints:

- [x] `GET /api/v1/admin/users`
- [x] `GET /api/v1/admin/reports`
- [x] `POST /api/v1/admin/users/{user_id}/suspend`
- [x] `POST /api/v1/admin/activities/{activity_id}/remove`

## Phase 15 — Testing

Backend tests:

- [ ] User can register
- [ ] User can login
- [ ] User can create profile
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

Mobile testing:

- [ ] Register flow works
- [ ] Login flow works
- [ ] Profile setup works
- [ ] Discovery cards load
- [ ] Connection request works
- [x] Messages screen works
- [ ] Activity board works
- [ ] Report/block works

## Phase 16 — Deployment

Backend:

- [ ] Deploy FastAPI backend to Render, Railway, Fly.io, or similar
- [ ] Deploy PostgreSQL database
- [ ] Configure environment variables
- [ ] Run migrations in production
- [ ] Set allowed CORS origins
- [ ] Add production logging

Mobile:

- [ ] Configure Expo app settings
- [ ] Create development build
- [ ] Test on Android phone
- [ ] Test on iPhone if available
- [ ] Prepare app icon and splash screen
- [ ] Prepare internal testing build

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

## Phase 18 — Future Features After MVP

Only add these after students are actually using the MVP:

- [ ] Push notifications
- [ ] Real-time messaging with WebSockets
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

## Build Priority Summary

Build first:

1. Auth
2. Profile setup
3. Discovery cards
4. Connection requests
5. Matches/messages
6. Activities
7. Report/block

Everything else can wait.
