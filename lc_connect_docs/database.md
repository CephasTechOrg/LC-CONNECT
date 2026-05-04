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
users M ─── M interests through user_interests
users M ─── M languages through user_languages
users M ─── M looking_for_options through user_looking_for
users 1 ─── M connection_requests as requester
users 1 ─── M connection_requests as receiver
users 1 ─── M matches as user_one/user_two
matches 1 ─── M messages
users 1 ─── M activities as creator
activities M ─── M users through activity_participants
users 1 ─── M reports as reporter
users 1 ─── M reports as reported_user
users 1 ─── M blocks as blocker
users 1 ─── M blocks as blocked_user
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
    password_hash TEXT NOT NULL,
    role VARCHAR(30) NOT NULL DEFAULT 'student',
    status VARCHAR(30) NOT NULL DEFAULT 'pending_verification',
    is_email_verified BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_login_at TIMESTAMPTZ
);
```

Notes:

- Passwords must never be stored as plain text.
- Use `password_hash` only.
- `status` controls whether the user can access the app.

### 5.2 `profiles`

```sql
CREATE TABLE profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    display_name VARCHAR(100) NOT NULL,
    profile_photo_url TEXT,
    major VARCHAR(120),
    class_year VARCHAR(50),
    country_or_state VARCHAR(120),
    bio TEXT,
    is_profile_complete BOOLEAN NOT NULL DEFAULT FALSE,
    is_hidden BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 5.3 `interests`

```sql
CREATE TABLE interests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(80) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 5.4 `user_interests`

```sql
CREATE TABLE user_interests (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    interest_id UUID NOT NULL REFERENCES interests(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, interest_id)
);
```

### 5.5 `languages`

```sql
CREATE TABLE languages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(80) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 5.6 `user_languages`

```sql
CREATE TABLE user_languages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    language_id UUID NOT NULL REFERENCES languages(id) ON DELETE CASCADE,
    type VARCHAR(30) NOT NULL, -- spoken or learning
    level VARCHAR(30), -- beginner, intermediate, advanced, fluent
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, language_id, type)
);
```

### 5.7 `looking_for_options`

```sql
CREATE TABLE looking_for_options (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key VARCHAR(60) NOT NULL UNIQUE,
    label VARCHAR(100) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
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
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    option_id UUID NOT NULL REFERENCES looking_for_options(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, option_id)
);
```

### 5.9 `connection_requests`

```sql
CREATE TABLE connection_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    intent VARCHAR(60) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'pending',
    message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (requester_id <> receiver_id),
    UNIQUE (requester_id, receiver_id, intent)
);
```

### 5.10 `matches`

```sql
CREATE TABLE matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_one_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_two_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    connection_request_id UUID REFERENCES connection_requests(id) ON DELETE SET NULL,
    intent VARCHAR(60),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (user_one_id <> user_two_id),
    UNIQUE (user_one_id, user_two_id)
);
```

Important rule:

- Store lower UUID first or enforce a consistent ordering in backend logic so duplicate matches are not created in reverse order.

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
- MVP can use REST polling before adding real-time WebSockets.

### 5.12 `activities`

```sql
CREATE TABLE activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(120) NOT NULL,
    description TEXT,
    category VARCHAR(60) NOT NULL DEFAULT 'other',
    location VARCHAR(160),
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ,
    max_participants INTEGER,
    is_cancelled BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 5.13 `activity_participants`

```sql
CREATE TABLE activity_participants (
    activity_id UUID NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (activity_id, user_id)
);
```

### 5.14 `blocks`

```sql
CREATE TABLE blocks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (blocker_id <> blocked_user_id),
    UNIQUE (blocker_id, blocked_user_id)
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
    reason VARCHAR(120) NOT NULL,
    details TEXT,
    status VARCHAR(30) NOT NULL DEFAULT 'open',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL
);
```

### 5.16 `verification_requests`

```sql
CREATE TABLE verification_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    method VARCHAR(60) NOT NULL, -- school_email, student_id_upload, manual
    status VARCHAR(30) NOT NULL DEFAULT 'pending',
    evidence_url TEXT,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL
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
CREATE INDEX idx_connection_requests_requester ON connection_requests(requester_id, status);

CREATE INDEX idx_matches_user_one ON matches(user_one_id);
CREATE INDEX idx_matches_user_two ON matches(user_two_id);

CREATE INDEX idx_messages_match_created ON messages(match_id, created_at);

CREATE INDEX idx_activities_starts_at ON activities(starts_at);
CREATE INDEX idx_activities_category ON activities(category);
CREATE INDEX idx_activities_creator ON activities(creator_id);

CREATE INDEX idx_blocks_blocker ON blocks(blocker_id);
CREATE INDEX idx_blocks_blocked ON blocks(blocked_user_id);

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
