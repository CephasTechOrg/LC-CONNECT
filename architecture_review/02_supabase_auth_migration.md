# 02 — Supabase Auth Migration

## Goal

Replace custom FastAPI credential/session management while preserving FastAPI authorization and the existing application data model.

## Supabase Auth replaces

- password hashing and verification
- custom signup/login tokens
- verification/reset OTP generation
- seven-day custom access token
- manual custom token installation into Supabase Realtime

## FastAPI keeps

- application users
- roles and suspension
- profile onboarding
- API and WebSocket authorization
- moderation and audits

## Database migration

### Add identity link

```sql
alter table users add column auth_user_id uuid null;
create unique index uq_users_auth_user_id
on users(auth_user_id)
where auth_user_id is not null;
```

### Add bootstrap endpoint

```http
POST /api/v1/auth/bootstrap
Authorization: Bearer <Supabase access token>
```

The endpoint verifies the token, maps or creates the LC Connect user, creates a profile when needed, and returns application state. It must be idempotent and transaction-safe.

### Link existing test users

Create or sign up matching Supabase Auth users, then link `auth_user_id`. Do not manually write passwords into Supabase Auth tables.

### Require the link

After backfill:

```sql
alter table users alter column auth_user_id set not null;
```

### Remove old credential columns

After linking gate OK (see `AUTH_USER_LINKING_RUNBOOK.md`):

```sql
-- Applied by Alembic a0b1c2d3e4f5_drop_legacy_credential_columns
alter table users drop column password_hash;
alter table users drop column verify_otp_hash;
alter table users drop column verify_otp_expires_at;
alter table users drop column reset_otp_hash;
alter table users drop column reset_otp_expires_at;
```

`auth_user_id` stays nullable so soft-deleted tombstones can remain unlinked.

## Token verification

FastAPI must validate:

- approved algorithm
- signature and key ID
- issuer
- audience
- expiration
- subject
- expected authenticated role

Use Supabase JWKS. Cache public keys for a bounded period and refresh when an unknown key ID appears.

Never decode without signature verification or log tokens.

## Campus-domain restriction

Enforce these domains server-side:

```text
students.livingstone.edu
livingstone.edu
```

Use local/staging-only test users instead of production Gmail exceptions.

## Flutter migration

Use Supabase Auth directly for signup, sign-in, recovery, and auth-state changes. Dio should use the access token from the current Supabase session. Do not maintain a second custom application access token.

## WebSocket token lifecycle

Because access tokens are short-lived:

- track expiry
- let Supabase refresh the session
- reconnect or reauthenticate the socket after refresh
- close the socket when the token is invalid or the account is suspended
- ensure a refreshed token belongs to the same user/session context

The simplest safe first implementation is to reconnect the WebSocket whenever the access token changes.

## Administrator MFA

FastAPI must require both the admin role and a high-assurance token state such as `aal2` for sensitive admin endpoints.

## Rollout order

1. Backup and migration baseline.
2. Add `auth_user_id`.
3. Configure local/staging Supabase Auth.
4. Implement FastAPI JWKS verification.
5. Add bootstrap.
6. Update Flutter Auth and Dio.
7. Authenticate WebSockets using the Supabase token.
8. Test existing user linking.
9. Private pilot.
10. Disable custom auth.
11. Remove old credential columns and rotate the old secret.
