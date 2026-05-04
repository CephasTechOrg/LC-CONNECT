# LC Connect — Architecture

## 1. Architecture Summary

LC Connect will use a mobile-first client-server architecture.

```text
React Native Expo Mobile App
        ↓ HTTPS / JSON API
FastAPI Backend API
        ↓ SQLAlchemy / async database access
PostgreSQL Database
```

Future optional services:

```text
Cloudinary/S3      → profile image storage
Redis              → caching, rate limits, future realtime support
Push Notifications → Expo Notifications or Firebase Cloud Messaging
Next.js Admin      → admin dashboard for reports/users/activities
```

## 2. Main Technology Choices

### Mobile Frontend

**React Native + Expo**

Reason:

- Builds real mobile apps for Android and iOS
- Faster MVP development
- Easy phone testing with Expo Go/dev builds
- Strong fit for cards, profiles, activities, chat, and mobile-first interaction
- Works well with a future React/Next.js admin dashboard

### Backend

**FastAPI**

Reason:

- Great for building APIs
- Works well with Python type hints and Pydantic schemas
- Easy to structure cleanly
- Good fit for custom matching logic, safety rules, and future AI features
- Strong learning/resume value

### Database

**PostgreSQL**

Reason:

- Reliable relational database
- Good for users, profiles, messages, activities, matches, reports, and relationships
- Supports indexes, constraints, enums, and future search features

## 3. System Components

## 3.1 Mobile App

The mobile app handles:

- Signup/login screens
- Onboarding/profile setup
- Home recommendations
- Student discovery cards
- Connection requests
- Activity board
- Messages
- Profile/settings
- Block/report actions

The mobile app should not contain sensitive business logic. It should call the backend for all important actions.

## 3.2 FastAPI Backend

The backend handles:

- Authentication
- User profile management
- Discovery/matching logic
- Connection request rules
- Match creation
- Messaging rules
- Activity creation/joining
- Reports and blocks
- Admin moderation endpoints
- Database access

Backend responsibilities:

- Enforce who can message whom
- Prevent blocked users from seeing/interacting
- Validate all user input
- Protect private data
- Maintain clean business rules

## 3.3 PostgreSQL Database

The database stores:

- Accounts
- Profiles
- Interests
- Languages
- User preferences
- Connection requests
- Matches
- Messages
- Activities
- Activity participants
- Reports
- Blocks
- Verification records

## 3.4 File/Image Storage

For MVP, profile images can be handled in one of two ways:

### Option A: Cloudinary

Good for quick MVP image upload and transformation.

### Option B: S3-compatible storage

Good if you want more control and production-style architecture.

Recommended MVP choice:

- Start with Cloudinary or Supabase Storage
- Store only image URLs in PostgreSQL

## 3.5 Admin Dashboard

Admin dashboard can be built after the first mobile MVP.

Admin functions:

- View users
- Review reports
- Suspend/reactivate users
- Review activities
- Remove inappropriate activities
- Review verification requests

Recommended frontend for admin later:

- Next.js or React

## 4. High-Level Data Flows

## 4.1 Signup Flow

```text
Student opens app
→ creates account
→ backend validates email/password
→ backend creates user record
→ student completes profile
→ backend stores profile details
→ user becomes discoverable if profile is complete
```

## 4.2 Profile Setup Flow

```text
Student enters profile details
→ mobile app sends data to FastAPI
→ FastAPI validates data
→ FastAPI saves profile, interests, languages, and looking-for preferences
→ backend marks profile as complete
```

## 4.3 Discovery Flow

```text
Student opens Connect screen
→ mobile app requests recommended profiles
→ backend excludes blocked users, self, hidden profiles, and existing matches
→ backend calculates simple match reasons
→ backend returns profile cards
→ mobile app displays interactive cards
```

## 4.4 Connection Request Flow

```text
Student taps Connect / Study Together / Language Exchange
→ mobile app sends request to backend
→ backend checks block/report restrictions
→ backend creates connection request
→ receiver sees request
→ receiver accepts
→ backend creates match
→ messaging becomes available
```

## 4.5 Messaging Flow

```text
Student opens message thread
→ backend checks that both users are matched
→ backend returns messages
→ student sends message
→ backend validates match and block status
→ backend stores message
→ receiver sees message
```

For MVP, messages can use normal REST endpoints. WebSockets can be added later for real-time delivery.

## 4.6 Activity Flow

```text
Student creates activity
→ backend validates activity details
→ activity appears on activity board
→ other students join
→ backend stores participants
→ activity creator can see participants
```

## 4.7 Report/Block Flow

```text
Student reports or blocks another user
→ backend stores report/block record
→ blocked user can no longer message or appear in discovery
→ admin can review report
```

## 5. Backend Module Architecture

Recommended FastAPI structure:

```text
app/
  api/
    v1/
      routes/
  core/
  db/
  models/
  schemas/
  services/
  repositories/
  utils/
  tests/
```

### Routes

Routes receive HTTP requests and return responses.

Example:

- `auth.py`
- `profiles.py`
- `discovery.py`
- `connections.py`
- `messages.py`
- `activities.py`
- `reports.py`
- `admin.py`

### Schemas

Pydantic models for request/response validation.

Example:

- `ProfileCreate`
- `ProfileResponse`
- `ConnectionRequestCreate`
- `MessageCreate`

### Services

Business logic lives here.

Example:

- Can this user message that user?
- Should this profile appear in discovery?
- What are the match reasons?
- Is the user blocked?

### Repositories

Database query logic lives here.

Example:

- Find user by email
- Create message
- Fetch activity participants
- Get recommended profiles

### Models

SQLAlchemy ORM database tables.

## 6. API Areas

## 6.1 Auth API

Example endpoints:

```text
POST /api/v1/auth/register
POST /api/v1/auth/login
POST /api/v1/auth/logout
GET  /api/v1/auth/me
```

## 6.2 Profile API

```text
GET    /api/v1/profiles/me
PATCH  /api/v1/profiles/me
GET    /api/v1/profiles/{profile_id}
```

## 6.3 Discovery API

```text
GET /api/v1/discovery/cards
GET /api/v1/discovery/study-partners
GET /api/v1/discovery/language-exchange
```

## 6.4 Connection API

```text
POST /api/v1/connections/request
GET  /api/v1/connections/incoming
GET  /api/v1/connections/outgoing
POST /api/v1/connections/{request_id}/accept
POST /api/v1/connections/{request_id}/decline
GET  /api/v1/connections/matches
```

## 6.5 Message API

```text
GET  /api/v1/messages/threads
GET  /api/v1/messages/threads/{match_id}
POST /api/v1/messages/threads/{match_id}
```

## 6.6 Activity API

```text
POST   /api/v1/activities
GET    /api/v1/activities
GET    /api/v1/activities/{activity_id}
POST   /api/v1/activities/{activity_id}/join
DELETE /api/v1/activities/{activity_id}/leave
```

## 6.7 Safety API

```text
POST /api/v1/blocks/{user_id}
DELETE /api/v1/blocks/{user_id}
POST /api/v1/reports
```

## 6.8 Admin API

```text
GET  /api/v1/admin/users
GET  /api/v1/admin/reports
POST /api/v1/admin/users/{user_id}/suspend
POST /api/v1/admin/activities/{activity_id}/remove
```

## 7. Matching Logic for MVP

Do not build complicated AI matching first.

Start with simple matching based on:

- Shared interests
- Same major
- Same looking-for category
- Language exchange compatibility
- Same class year
- Recent activity
- Not blocked
- Not already matched

Example match score:

```text
+3 same looking-for category
+2 shared interest
+2 language exchange compatibility
+2 same major
+1 same year
-100 if blocked
-100 if already connected
```

Return match reasons, not just scores.

Example:

```json
{
  "profile_id": "...",
  "display_name": "Maya",
  "match_reasons": [
    "You both want a study partner",
    "You both like basketball",
    "You are both Computer Science students"
  ]
}
```

## 8. Security Requirements

MVP security requirements:

- Passwords must be hashed
- JWT tokens should be used for API authentication
- Backend must validate user permissions
- Users cannot message without a match
- Blocked users cannot interact
- Suspended users cannot use the app
- User input must be validated
- Admin endpoints must require admin role
- Sensitive information should not be exposed in discovery cards

## 9. Future Improvements

After the MVP works, add:

- Push notifications
- Real-time messaging with WebSockets
- Better search/filtering
- AI-generated icebreakers
- Admin dashboard
- Event approval flow
- Club/organization profiles
- Group chats for activities
- Campus map integration
- Recommendation engine
