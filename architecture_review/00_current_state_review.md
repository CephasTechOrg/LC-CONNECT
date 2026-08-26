# 00 — Current-State Review

> **Historical snapshot** from the pre–FastAPI-WebSocket review. For **current** readiness,
> scores, and sprint order use [`06_enterprise_system_review.md`](./06_enterprise_system_review.md)
> and [`PHASE_0_1_STATUS.md`](./PHASE_0_1_STATUS.md). Chat is no longer Supabase Realtime;
> auth is Supabase Auth only.

## Executive verdict

LC Connect is already a substantial early MVP. It contains Flutter screens and routing, custom authentication, email verification and password recovery, profiles, discovery, matching, activities, blocks, reports, admin endpoints, persistent messages, live Supabase message delivery, and typing indicators.

The foundation should be retained. The principal weakness is the number of security systems currently coupled together for authentication and realtime delivery.

## Approximate assessment

| Area | Assessment | Rating |
|---|---|---:|
| MVP product completeness | Strong | 8/10 |
| Flutter implementation | Strong early MVP | 7.5/10 |
| FastAPI domain model | Good foundation | 7/10 |
| Current authentication | Functional, not production-grade | 4/10 |
| Current realtime implementation | Fragile and difficult to debug | 5/10 |
| Safety/privacy enforcement | Good intent, incomplete enforcement | 5/10 |
| Tests/migrations/operations | Early-stage | 3.5/10 |
| Campus-wide launch readiness | Not ready yet | 5/10 |

## What is strong

- The data model separates users, profiles, matches, messages, activities, blocks, reports, and connection requests.
- FastAPI already enforces match membership, block status, suspended accounts, admin roles, and duplicate/self connection protections.
- Flutter uses secure device storage for the current token.
- The chat UI already implements history loading, optimistic rendering, deduplication, automatic scroll, typing debounce, and subscription cleanup.
- The matching algorithm is simple and explainable, which is appropriate for an MVP.

## Main findings

### 1. Replace custom authentication

The backend currently owns password hashing, OTPs, and a seven-day stateless JWT without refresh-token rotation or a server-side application session. Use Supabase Auth for credentials, confirmation, recovery, MFA, short-lived access tokens, refresh tokens, and sessions.

FastAPI must continue enforcing application authorization.

### 2. Replace Supabase Realtime chat with FastAPI WebSockets

The current realtime path requires custom JWT claims, shared signing configuration, database/RLS correctness, Broadcast authorization, matching environments, and Flutter subscription state. Failures are largely hidden. Moving chat to FastAPI produces one clear authorization boundary.

### 3. Enforce verification server-side

Flutter routing is not security. Add dependencies such as:

```text
get_current_user
require_verified_student
require_admin_aal2
```

### 4. Centralize profile privacy

Create reusable policies such as:

```text
can_view_profile(viewer, target)
can_connect(sender, receiver)
can_message(sender, conversation)
```

These must account for hidden profiles, verification, blocks, suspension, and relationship context.

### 5. Add message idempotency

Add:

```text
client_message_id UUID NOT NULL
UNIQUE(sender_id, client_message_id)
```

This prevents duplicate messages after mobile retries.

### 6. Add cursor pagination

Do not return a complete message history. Page using `(created_at, id)` and synchronize missed messages after reconnect.

### 7. Harden uploads

Do not trust MIME type or filename extension. Decode, validate, cap pixels, strip EXIF, re-encode, and generate the object name server-side.

### 8. Add distributed rate limits

Limit authentication attempts, WebSocket connections, subscriptions, message sends, typing events, reports, uploads, connection requests, and admin actions.

### 9. Establish migrations and tests

Every schema, index, RLS policy, Storage rule, and operational change must be versioned. Critical HTTP and WebSocket authorization paths require automated tests.

### 10. Revoke live access on block or suspension

A block or suspension must remove active WebSocket subscriptions immediately, not only reject the next REST request.

### 11. Add admin audit records

Store actor, action, target, reason, request ID, metadata, and timestamp for sensitive moderation actions.

## Keep

- Flutter and Riverpod
- FastAPI
- PostgreSQL and async SQLAlchemy
- Current domain models and matching logic
- Supabase Storage
- Existing chat UI components

## Replace or harden

- Custom password/session implementation
- Custom JWT sharing with Supabase
- Supabase Realtime chat subscriptions
- Unpaginated message history
- Non-idempotent sends
- Weak upload validation
- Missing rate limits, tests, and audit records
