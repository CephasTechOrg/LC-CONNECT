# 04 — Security, Privacy, Safety, and Compliance

## Position

LC Connect is a campus social application. It should not claim automatic FERPA compliance merely because students use it.

For MVP:

- collect minimal user-provided social information
- avoid official education records
- enforce verified campus identity
- protect private conversations
- provide block, report, export, and deletion controls
- document moderator access and retention

This is engineering and product guidance, not legal advice.

## Authentication

- Supabase Auth
- confirmed campus email
- short-lived access tokens and refresh-token sessions
- mandatory administrator MFA
- optional student MFA
- session management and all-device sign-out
- reauthentication for sensitive changes

## WebSocket security

- production `wss://`
- authenticate immediately
- allow only auth before success
- validate every event schema
- cap event size
- apply per-user/IP/device rates
- heartbeat and idle timeout
- handle token expiry
- never log tokens or message bodies
- authorize every conversation action
- revoke active access on block/suspension
- use generic errors
- measure connection and authorization outcomes

## Data classes

### Secrets

Tokens, service keys, Redis credentials, database credentials, and signing keys must never be committed, logged, or shipped to Flutter.

### Highly private content

Direct messages, reports, moderation evidence, blocks, and support requests require narrow access and defined retention.

### Profile/social data

Profile fields require user visibility controls and data minimization.

### Operational metadata

Collect IP/device/app/request metadata only for reliability and security, retain briefly, and avoid unrelated profiling.

## Profile visibility

Centralize `can_view_profile(viewer, target)` and apply it to direct reads and discovery. Consider hidden state, blocks, verification, suspension, and relationship context.

## Images

Production pipeline:

```text
authorized upload -> size/signature checks -> safe decode -> pixel cap -> EXIF removal -> resize -> re-encode -> generated name -> Storage
```

Prefer private Storage and signed URLs. If avatars are public, disclose the consequences.

## Messaging privacy

- text-only MVP
- no arbitrary files
- no live precise location
- no disappearing messages initially
- no end-to-end encryption claim
- no message body in logs
- notification previews disabled by default

## Blocking

Blocking should immediately:

- deny sends
- revoke WebSocket subscriptions
- stop typing/presence
- remove discovery exposure
- deny future requests
- hide the normal conversation

Define whether history remains visible and whether unblocking restores the match.

## Reports and moderation

Support target type/ID, selected message IDs, reason, details, priority, assignment, status, resolution, appeal, and timestamps.

Moderator access should require MFA, least privilege, reason, and audit records.

## Admin audit log

Store actor, action, target, reason, request ID, metadata, and timestamp for suspensions, report access/resolution, role changes, activity removal, exports, and deletions.

## Rate limiting

Use Supabase Auth limits for authentication and Redis-backed FastAPI limits for WebSocket connections, subscriptions, messages, typing, reports, uploads, requests, activities, and admin operations.

## Notifications

Default:

```text
You received a new message on LC Connect.
```

Message previews should be opt-in.

## Age/open connection

College users may include minors. Omit romantic matching for the first pilot or require an explicit 18+ policy and legal review. Do not infer age from class year.

## Location

Use named public campus locations, not continuous GPS or dorm/home addresses. Do not present LC Connect as an emergency service.

## Retention

Define and publish retention for profiles, messages, reports, security logs, admin audits, deleted accounts, and backups. Typing and presence should not be persistently stored.

## User rights

Provide profile editing/hiding, block/report, avatar deletion, session management, export, deletion, suspension appeal, and support.

## Account deletion

Reauthenticate, revoke sessions/sockets, hide the account, delete/anonymize data according to policy, remove Storage objects, delete the Auth identity, preserve only documented holds, and disclose backup expiry.

## FERPA boundary

Risk increases if Livingstone College adopts the app for an institutional function or supplies official education records. Before accepting such records, obtain legal review and a written agreement covering use, control, access, redisclosure, retention, subcontractors, incidents, and audit rights.

Avoid collecting grades, transcripts, student ID numbers, disciplinary records, government IDs, and precise location in the MVP.

## Prohibited claims

Do not claim “FERPA compliant,” “end-to-end encrypted,” “anonymous,” “immediately permanently deleted,” or “100% secure” unless the exact technical and legal conditions are actually satisfied.
