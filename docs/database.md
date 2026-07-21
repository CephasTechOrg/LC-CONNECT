# LC Connect — Database Design

Database: **PostgreSQL**

The database should support student accounts, profiles, interests, languages, discovery, mutual connections, messaging, activities, reports, blocks, and admin moderation.

## 1. Design Principles

The database should enforce these product rules:

1. Every user has one main account.
2. Every user can have one student profile.
3. Students can select multiple interests.
4. Students can select multiple looking-for preferences.
5. Students can speak and learn multiple languages.
6. Messaging is only allowed after a mutual match.
7. Blocked users should not appear in discovery or messaging.
8. Reports should be reviewable by admins.
9. Activities can have multiple participants.
10. Suspended users should not be able to use core features.

## 2. Main Tables

| Table | Purpose |
|---|---|
| `users` | Login/account data |
| `profiles` | Student profile data |
| `interests` | List of available interests |
| `user_interests` | Many-to-many user interests |
| `languages` | List of languages |
| `user_languages` | Languages spoken or learning |
| `looking_for_options` | Friendship, study partner, language exchange, events, open connection |
| `user_looking_for` | User selected connection goals |
| `connection_requests` | Pending/accepted/declined requests |
| `matches` | Mutual accepted connections |
| `messages` | One-on-one messages between matched users |
| `activities` | Campus activities/meetups |
| `activity_participants` | Users who joined activities |
| `blocks` | User blocks |
| `reports` | User reports |
| `verification_requests` | Student verification records |

## 3. Entity Relationship Summary

```text
users 1 ─── 1 profiles
profiles M ─── M interests through user_interests
profiles M ─── M languages through user_languages
profiles M ─── M looking_for_options through user_looking_for
users 1 ─── M connection_requests as sender
users 1 ─── M connection_requests as receiver
users 1 ─── M matches as user_a/user_b
matches 1 ─── M messages
users 1 ─── M activities as creator
activities M ─── M users through activity_participants
users 1 ─── M reports as reporter
users 1 ─── M reports as reported_user
users 1 ─── M blocks as blocker
users 1 ─── M blocks as blocked
```

## 4. Recommended Enums

These can be PostgreSQL enums or app-level string constants.

### User Role

```text
student
admin
```

### User Status

```text
active
pending_verification
suspended
deleted
```

### Connection Request Status

```text
pending
accepted
declined
cancelled
```

### Connection Intent

```text
friendship
study_partner
language_exchange
events
open_connection
```

### Activity Category

```text
study
sports
food
language_exchange
social
club
faith
wellness
other
```

### Report Status

```text
open
reviewing
resolved
dismissed
```

## 5. Table Designs

### 5.1 `users`

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(30) NOT NULL DEFAULT 'student',
    status VARCHAR(30) NOT NULL DEFAULT 'active',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    verify_otp_hash VARCHAR(64),
    verify_otp_expires_at TIMESTAMPTZ,
    reset_otp_hash VARCHAR(64),
    reset_otp_expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

Notes:

- Passwords must never be stored as plain text — `password_hash` only.
- `is_verified` is set to `true` after the user confirms their OTP email.
- `verify_otp_hash` and `verify_otp_expires_at` hold the current verification OTP state.
- `reset_otp_hash` and `reset_otp_expires_at` hold the current password-reset OTP state.
- `status` controls whether the user can access the app (active, suspended, etc).

### 5.2 `profiles`

```sql
CREATE TABLE profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    display_name VARCHAR(120),
    pronouns VARCHAR(50),
    major VARCHAR(120),
    class_year INTEGER,
    country_state VARCHAR(120),
    campus VARCHAR(120) DEFAULT 'Livingstone Campus',
    bio TEXT,
    avatar_url TEXT,
    is_hidden BOOLEAN NOT NULL DEFAULT FALSE,
    allow_messages_from_matches_only BOOLEAN NOT NULL DEFAULT TRUE,
    show_profile_to_verified_only BOOLEAN NOT NULL DEFAULT TRUE,
    profile_completed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

Notes:

- `avatar_url` stores the URL to the profile photo.
- `profile_completed` is set to `true` once the user finishes onboarding.
- `show_profile_to_verified_only` hides the profile from unverified users in discovery.

### 5.3 `interests`

```sql
CREATE TABLE interests (
    id SERIAL PRIMARY KEY,
    name VARCHAR(80) NOT NULL UNIQUE,
    category VARCHAR(50)
);
```

### 5.4 `user_interests`

```sql
CREATE TABLE user_interests (
    profile_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    interest_id INTEGER NOT NULL REFERENCES interests(id) ON DELETE CASCADE,
    PRIMARY KEY (profile_id, interest_id)
);
```

Note: the join is on `profiles.id`, not `users.id`.

### 5.5 `languages`

```sql
CREATE TABLE languages (
    id SERIAL PRIMARY KEY,
    name VARCHAR(80) NOT NULL UNIQUE
);
```

### 5.6 `user_languages`

```sql
CREATE TABLE user_languages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    language_id INTEGER NOT NULL REFERENCES languages(id) ON DELETE CASCADE,
    kind VARCHAR(20) NOT NULL,   -- 'spoken' or 'learning'
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (profile_id, language_id, kind)
);
```

Note: `kind` replaces `type` to avoid clashing with the PostgreSQL reserved word.

### 5.7 `looking_for_options`

```sql
CREATE TABLE looking_for_options (
    id SERIAL PRIMARY KEY,
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(80) NOT NULL UNIQUE
);
```

Seed values:

```text
friendship        → Friendship
study_partner     → Study Partner
language_exchange → Language Exchange
events            → Events/Activities
open_connection   → Open Connection
```

### 5.8 `user_looking_for`

```sql
CREATE TABLE user_looking_for (
    profile_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    option_id INTEGER NOT NULL REFERENCES looking_for_options(id) ON DELETE CASCADE,
    PRIMARY KEY (profile_id, option_id)
);
```

Note: the join is on `profiles.id`, not `users.id`.

### 5.9 `connection_requests`

```sql
CREATE TABLE connection_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    intent VARCHAR(50),
    note TEXT,
    status VARCHAR(30) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at TIMESTAMPTZ,
    UNIQUE (sender_id, receiver_id)
);
```

### 5.10 `matches`

```sql
CREATE TABLE matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_a_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_b_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_a_id, user_b_id)
);
```

Important rule:

- Store lower UUID first (`user_a_id < user_b_id`) in backend logic so duplicate matches are not created in reverse order.
- The RLS SELECT policy on `messages` references `matches.user_a_id` and `matches.user_b_id` — any rename here must also update the migration in `supabase/migrations/20260510000000_messages_rls.sql`.

### 5.11 `messages`

```sql
CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id UUID NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    read_at TIMESTAMPTZ
);
```

Rules:

- Backend must verify that `sender_id` belongs to the match.
- Backend must verify that neither user has blocked the other.
- Real-time delivery uses Supabase Realtime (WebSocket). No polling needed. See `lc_connect_docs/realtime-messaging.md`.
- RLS is enabled on this table. Only match participants can read their messages. Direct client-side inserts are blocked. See `lc_connect_docs/security_rls_messages.md`.

### 5.12 `activities`

```sql
CREATE TABLE activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(120) NOT NULL,
    description TEXT,
    category VARCHAR(40) NOT NULL,
    location VARCHAR(160) NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    max_participants INTEGER,
    is_cancelled BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 5.13 `activity_participants`

```sql
CREATE TABLE activity_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(30) NOT NULL DEFAULT 'joined',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (activity_id, user_id)
);
```

### 5.14 `blocks`

```sql
CREATE TABLE blocks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (blocker_id, blocked_id)
);
```

Rules:

- Blocked users should not appear in discovery.
- Blocked users should not be able to message.
- Blocking should hide existing conversation from the blocker if needed.

### 5.15 `reports`

```sql
CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reported_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    activity_id UUID REFERENCES activities(id) ON DELETE SET NULL,
    reason VARCHAR(80) NOT NULL,
    details TEXT,
    status VARCHAR(30) NOT NULL DEFAULT 'open',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 5.16 `verification_requests`

```sql
CREATE TABLE verification_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    method VARCHAR(50) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'pending',
    evidence_url TEXT,
    reviewed_by_id UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ
);
```

## 6. Recommended Indexes

```sql
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_profiles_user_id ON profiles(user_id);
CREATE INDEX idx_profiles_major ON profiles(major);
CREATE INDEX idx_profiles_is_hidden ON profiles(is_hidden);

CREATE INDEX idx_connection_requests_receiver ON connection_requests(receiver_id, status);
CREATE INDEX idx_connection_requests_sender ON connection_requests(sender_id, status);

CREATE INDEX idx_matches_user_a ON matches(user_a_id);
CREATE INDEX idx_matches_user_b ON matches(user_b_id);

CREATE INDEX idx_messages_match_created ON messages(match_id, created_at);

CREATE INDEX idx_activities_start_time ON activities(start_time);
CREATE INDEX idx_activities_category ON activities(category);
CREATE INDEX idx_activities_creator ON activities(creator_id);

CREATE INDEX idx_blocks_blocker ON blocks(blocker_id);
CREATE INDEX idx_blocks_blocked ON blocks(blocked_id);

CREATE INDEX idx_reports_status ON reports(status);
```

## 7. Discovery Query Rules

When returning student cards, exclude:

- The current user
- Suspended users
- Hidden profiles
- Users already matched with current user
- Users blocked by current user
- Users who blocked current user
- Profiles without required onboarding fields

Recommended discovery inputs:

- Current user interests
- Current user looking-for preferences
- Current user major/year
- Current user spoken/learning languages

Recommended discovery output:

- Profile preview
- Shared interests
- Shared looking-for tags
- Language exchange reason
- Suggested action

## 8. Messaging Rules

A message can only be sent if:

1. A match exists.
2. Sender is part of the match.
3. Sender is active.
4. Receiver is active.
5. Neither user has blocked the other.

## 9. Activity Rules

A user can join an activity if:

1. User is active.
2. Activity is not cancelled.
3. Activity has not already ended.
4. Max participants has not been reached.
5. User has not already joined.

## 10. MVP Seed Data

Seed looking-for options:

```sql
INSERT INTO looking_for_options (key, label) VALUES
('friendship', 'Friendship'),
('study_partner', 'Study Partner'),
('language_exchange', 'Language Exchange'),
('events', 'Events/Activities'),
('open_connection', 'Open Connection');
```

Seed interests:

```sql
INSERT INTO interests (name) VALUES
('Basketball'),
('Football'),
('Coding'),
('Music'),
('Movies'),
('Gaming'),
('Fitness'),
('Cooking'),
('Volunteering'),
('Entrepreneurship'),
('Faith'),
('Art'),
('Photography'),
('Reading'),
('Travel');
```

Seed languages:

```sql
INSERT INTO languages (name) VALUES
('English'),
('Spanish'),
('French'),
('Twi'),
('Arabic'),
('Ukrainian'),
('Russian'),
('Portuguese'),
('German'),
('Chinese');
```

## 11. Future Database Improvements

After MVP, consider adding:

- Push notification tokens
- Message reactions
- Message attachments
- Group chats
- Activity comments
- Club/organization profiles
- User availability schedules
- AI-generated icebreaker suggestions
- More advanced recommendation logs
- Audit logs for admin actions
