# 03 — FastAPI WebSocket Messaging

## Purpose

This document replaces the previous Supabase Realtime chat design.

## Architecture

```text
Flutter Sender
      │ WSS
      ▼
FastAPI WebSocket Gateway
      ├── authenticate
      ├── authorize conversation
      ├── validate and rate-limit
      ├── persist message
      └── publish live event
              │
        ┌─────┴──────┐
        ▼            ▼
   PostgreSQL     Redis Pub/Sub
   durable truth  cross-instance fan-out
                       │
                       ▼
             FastAPI instance holding
             recipient's local socket
                       │
                       ▼
                Flutter Receiver
```

## Core rules

1. PostgreSQL is the source of truth.
2. Redis Pub/Sub is live delivery only.
3. Authentication is required before any other event.
4. Every conversation subscription is authorized.
5. Every send is reauthorized.
6. Blocks and suspension affect live connections immediately.
7. Missed events are recovered through REST synchronization.

## Endpoint

```text
Production: wss://api.lcconnect.app/api/v1/ws
Local:      ws://127.0.0.1:8000/api/v1/ws
```

## Connection lifecycle

```text
CONNECTING -> AUTHENTICATING -> READY -> RECONNECTING -> CLOSED
```

## Authentication

Client:

```json
{
  "type": "auth",
  "access_token": "<Supabase token>",
  "device_id": "installation-uuid",
  "app_version": "1.0.0"
}
```

Server:

```json
{
  "type": "auth.ok",
  "user_id": "application-user-uuid",
  "heartbeat_interval_seconds": 25
}
```

Never log or echo the token.

## Heartbeats

Use WebSocket ping/pong or application frames. Close stale connections after a documented timeout.

## Subscribe to conversation

```json
{
  "type": "conversation.subscribe",
  "request_id": "uuid",
  "conversation_id": "match-uuid"
}
```

FastAPI checks:

- authenticated user
- active account
- verified student
- match exists
- user is a participant
- no block in either direction
- conversation is enabled

Return a generic forbidden error without revealing whether an inaccessible conversation exists.

## Send message

```json
{
  "type": "message.send",
  "request_id": "uuid",
  "conversation_id": "match-uuid",
  "client_message_id": "uuid",
  "body": "Are you free to study?"
}
```

Server steps:

1. validate event schema
2. enforce payload/message limits
3. enforce Redis-backed rate limits
4. recheck account and conversation authorization
5. insert idempotently
6. commit PostgreSQL transaction
7. publish canonical event through Redis
8. return acknowledgement

Acknowledgement:

```json
{
  "type": "message.ack",
  "request_id": "uuid",
  "client_message_id": "uuid",
  "message": {
    "id": "server-uuid",
    "conversation_id": "match-uuid",
    "sender_id": "user-uuid",
    "body": "Are you free to study?",
    "created_at": "2026-07-18T12:00:00Z",
    "read_at": null
  }
}
```

## Database changes

```text
client_message_id UUID NOT NULL
UNIQUE(sender_id, client_message_id)
```

Indexes:

```sql
create index ix_messages_match_created_id
on messages(match_id, created_at desc, id desc);

create unique index uq_messages_sender_client
on messages(sender_id, client_message_id);
```

## History and reconnect synchronization

Use REST:

```http
GET /api/v1/messages/threads/{match_id}?limit=50
GET /api/v1/messages/threads/{match_id}?before=<cursor>&limit=50
GET /api/v1/messages/threads/{match_id}/sync?after=<cursor>
```

After reconnect:

1. authenticate
2. restore subscriptions
3. request messages after the newest known cursor
4. merge by server ID and client message ID
5. resume live delivery

## Typing

```json
{"type":"typing.start","conversation_id":"match-uuid"}
```

```json
{"type":"typing.stop","conversation_id":"match-uuid"}
```

Redis key:

```text
typing:<environment>:<conversation_id>:<user_id>
TTL: 4 seconds
```

Rules:

- authorize conversation first
- throttle starts
- expire automatically
- ignore self events
- never store typing in PostgreSQL

## Presence

Optional for MVP.

```text
presence:<environment>:<user_id>
TTL: 60–90 seconds
```

Expose only online, recently active, or offline, and provide a privacy setting.

## Read receipts

```json
{
  "type": "messages.read",
  "conversation_id": "match-uuid",
  "through_message_id": "message-uuid"
}
```

FastAPI verifies membership, persists read state, and publishes a canonical receipt event.

## Redis channels

Environment-prefix all channels:

```text
lcconnect:dev:conversation:<match_id>
lcconnect:staging:conversation:<match_id>
lcconnect:prod:conversation:<match_id>
lcconnect:prod:user:<user_id>
lcconnect:prod:control
```

Redis Pub/Sub is at-most-once. Persist before publish and recover missed messages from PostgreSQL.

## Connection manager

Each FastAPI instance tracks:

```text
user_id -> local sockets
conversation_id -> local subscribed sockets
socket -> authenticated context and subscriptions
```

Support add/remove, subscribe/unsubscribe, local delivery, user-wide close, conversation revocation, and heartbeat tracking.

## Block/suspension events

Publish control events through Redis, such as:

```json
{"event":"user.suspended","user_id":"..."}
```

```json
{"event":"conversation.revoked","conversation_id":"..."}
```

Every instance removes affected subscriptions immediately.

## Rate limits

Bound:

- authentication attempts
- sockets per user/device/IP
- subscriptions per socket
- message frequency per user and conversation
- typing events
- event size
- malformed events
- idle duration

## Flutter client

The Flutter WebSocket service should:

- own one authenticated socket
- expose connection states
- reconnect with exponential backoff and jitter
- restore subscriptions
- reuse `client_message_id` for retries
- synchronize after reconnect
- clear all state on logout

## Offline notifications

When no recipient socket is active:

```text
message committed -> background job -> FCM/APNs
```

Default notification text should not include the message body.

## Mobile background behavior

```text
Foreground -> WebSocket
Background/terminated -> push notification
Reopen -> REST sync + WebSocket reconnect
```

## Render deployment

- use a Render Web Service
- always use `wss://` publicly
- expect reconnects during deployments/restarts
- use Redis for multiple workers/instances
- perform graceful shutdown

## Required tests

- valid/invalid/expired/wrong-project token
- unverified/suspended account
- authorized/unauthorized subscription
- block during active chat
- token refresh/reconnect
- duplicate retry
- Redis outage
- database outage
- multiple instances
- malformed/oversized/rate-limited events
- server restart
