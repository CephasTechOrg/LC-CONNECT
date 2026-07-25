# Resend Migration Guide (Backend Email)

This document describes the backend email integration using **Resend**.

It is intentionally scoped to what this codebase needs today:
- verification code emails
- resend verification code emails
- password reset code emails

---

## 1) Current System Snapshot

Current backend email behavior is in `backend/app/core/email.py`.

Active paths now:
1. Use Resend API when `EMAIL_PROVIDER=resend` (or `auto` with Resend configured).
2. Else use SMTP when configured (`EMAIL_PROVIDER=smtp` or `auto` fallback).
3. Else log email content to console (`EMAIL_PROVIDER=console` or `auto` fallback).

This means migration should preserve fallback behavior and avoid auth-flow regressions.

---

## 2) Migration Target

Target priority after migration:
1. Resend API (primary provider)
2. SMTP (optional fallback)
3. Console logging fallback (dev safety)

Provider strategy:
- Use explicit provider switch: `EMAIL_PROVIDER=auto|resend|smtp|console`

---

## 3) Required Resend Setup

Before coding changes, complete these in Resend dashboard:
1. Create a Resend account/team.
2. Verify a sending domain (recommended) or a verified sender.
3. Create an API key with mail send permission.
4. Decide sender identity (ex: `noreply@yourdomain.com`).

---

## 4) Environment Variables Needed

### Required for Resend
- `RESEND_API_KEY`
- `RESEND_FROM_EMAIL`

### Recommended
- `EMAIL_PROVIDER` (set to `resend` during cutover)
- `RESEND_REPLY_TO` (optional)
- `FRONTEND_URL` (already in config; useful if email content includes links later)

### SMTP fallback vars
- `SMTP_HOST`
- `SMTP_PORT`
- `SMTP_USERNAME`
- `SMTP_PASSWORD`
- `SMTP_FROM`
- `SMTP_TLS`

---

## 5) `.env` / `.env.example` Template

Use this block in `backend/.env` (values are placeholders):

```env
# Email provider selection
EMAIL_PROVIDER=resend

# Resend (primary)
RESEND_API_KEY=re_xxxxxxxxxxxxxxxxx
RESEND_FROM_EMAIL=InterviewPrep <noreply@yourdomain.com>
RESEND_REPLY_TO=support@yourdomain.com


---

## 6) Resend API Contract (What Backend Needs)

Endpoint:
- `POST https://api.resend.com/emails`

Headers:
- `Authorization: Bearer <RESEND_API_KEY>`
- `Content-Type: application/json`

Minimum payload for current backend flow:

```json
{
  "from": "noreply@yourdomain.com",
  "to": ["user@example.com"],
  "subject": "Verify your email",
  "text": "Use this 6-digit code ..."
}
```

Notes:
- Auth flows send both plain-text and HTML versions for verification and password reset emails.
- No pagination, batch send, or email retrieval endpoints are required for this migration scope.
- `RESEND_FROM_EMAIL` can be plain email or friendly format (`Brand <email@domain>`).

---

## 7) Pre-Implementation Checklist

Complete all before code changes:
1. Resend domain/sender verified.
2. API key created and stored in secrets manager or local `.env`.
3. `backend/.env.example` updated with new keys.
4. Fallback path defined (`EMAIL_PROVIDER=smtp` or `console`).
5. Test mailbox selected for QA.

---

## 8) QA Checklist After Integration

1. Signup sends verification code successfully.
2. Resend verification endpoint sends a new code.
3. Password reset request sends reset code.
4. Invalid/missing API key fails gracefully and logs useful error.
5. Switching provider (`resend` <-> `smtp` <-> `console`) works without code edits.
6. No auth endpoint behavior regression.

---

## 9) Manual Smoke Test

Run:

```bash
cd backend
python scripts/email_smoke_test.py --to your-email@example.com
```

What it does:
1. Prints active provider.
2. Checks Resend domain status (when using `auto`/`resend`).
3. Sends a real transactional test email.

---

## 10) Out of Scope (For This Migration Step)

- Marketing/broadcast emails
- Resend pagination/list APIs
- Batch email sending
- Rich template engine redesign

These can be added later once transactional flow is stable.
