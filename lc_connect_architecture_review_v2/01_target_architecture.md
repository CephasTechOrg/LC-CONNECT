# 01 — Target Architecture

## Final system

```text
                         Supabase Auth
              signup, confirmation, recovery,
              refresh-token sessions, MFA
                              │
                       Supabase JWT
                              │
                              ▼
Flutter Mobile ───── HTTPS / WSS ───── FastAPI
                                          │
                                          ├── token verification
                                          ├── authorization
                                          ├── REST APIs
                                          ├── WebSocket gateway
                                          ├── moderation
                                          └── rate limiting
                                                   │
                              ┌────────────────────┴──────────────────┐
                              ▼                                       ▼
                         PostgreSQL                                Redis
                  users, matches, messages,              Pub/Sub, TTL state,
                  blocks, reports, activities            distributed limits

Flutter also uses Supabase Storage for profile images and FCM/APNs for offline notifications.
```

## Responsibilities

### Flutter

- Supabase Auth user flows
- obtaining the current access token
- REST requests
- one authenticated WebSocket
- reconnect/backoff
- optimistic chat UI
- local merge/deduplication
- push-notification routing

Flutter is not the authority for membership, blocks, suspension, capacity, roles, or moderation.

### Supabase Auth

- password handling
- signup and confirmation
- recovery
- short-lived access tokens
- rotating refresh tokens
- sessions
- MFA
- Auth endpoint abuse controls

### FastAPI

- verify Supabase JWT through JWKS
- map the Auth subject to an LC Connect user
- enforce active/suspended/verified/role state
- authorize REST and WebSocket actions
- persist messages
- manage live subscriptions
- moderate and audit
- issue push-notification jobs

### PostgreSQL

The durable source of truth for application users, profiles, matches, messages, blocks, reports, activities, device tokens, and audit records.

### Redis

- cross-instance event fan-out
- typing TTLs
- coarse presence TTLs
- distributed rate limits
- optional distributed locks

Redis is not message history.

## Identity model

Keep existing application user IDs and add:

```text
users.auth_user_id UUID UNIQUE
```

```text
Supabase token sub -> users.auth_user_id -> users.id -> existing foreign keys
```

## HTTP authentication

1. Flutter signs in with Supabase Auth.
2. Flutter sends `Authorization: Bearer <access token>`.
3. FastAPI validates signature, issuer, audience, expiration, subject, and algorithm.
4. FastAPI finds `users.auth_user_id == sub`.
5. FastAPI enforces account and route policy.

## WebSocket authentication

Endpoint:

```text
wss://api.lcconnect.app/api/v1/ws
```

Recommended first-message authentication:

```json
{
  "type": "auth",
  "access_token": "<short-lived Supabase token>"
}
```

Only authentication frames are allowed before success. Never log or echo the token.

## Development

Recommended local services:

- local Supabase Auth/PostgreSQL/Storage through Supabase CLI
- local Redis through Docker
- local FastAPI
- Flutter emulator or device

A standalone local PostgreSQL database is still possible, but the local Supabase stack gives better Auth/Storage parity.

## Production

- Flutter iOS/Android
- FastAPI on Render
- Redis service
- Supabase Auth
- Supabase PostgreSQL
- Supabase Storage
- Firebase Cloud Messaging/APNs

Render accepts inbound WebSocket connections. Public clients must use `wss://`.

## Scaling

One process can start with an in-memory connection manager. Before multiple FastAPI workers or instances, add Redis Pub/Sub. Each instance delivers Redis events only to its own local sockets.
