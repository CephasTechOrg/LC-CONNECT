# Dual-Email Signup & Campus Verification

**Status:** Phase 2 implemented (pending manual pilot)  
**Last updated:** 2026-09-01  
**Related:** `architecture_review/DECISION_LOG.md` (ADR-008), `02_supabase_auth_migration.md`

---

## Problem

Student `@students.livingstone.edu` inboxes often block or quarantine LC Connect auth mail even when Resend shows **delivered** and DKIM/SPF are correct. Personal Gmail/iCloud addresses receive the same mail reliably. This is typically **campus IT mail filtering**, not a misconfiguration on our sender domain.

## Solution (two separate concepts)

| Concept | Meaning | Who controls it | User-facing label |
|---------|---------|-----------------|-------------------|
| **Account activation** | User proved they control a personal inbox (OTP) | Automatic (Supabase + hook) | “Confirm your account” |
| **Campus verified** | Staff confirmed this person is a real LC student/staff | Admin manual action | Profile checkmark badge |

Do **not** overload `users.is_verified` for both. Today `is_verified` means **email confirmed** (Supabase OTP). The public checkmark badge will move to a new `campus_verified` flag in Phase 2.

---

## Signup UX (recommended)

### One screen, two sections

Use a **single register screen** with two clearly grouped fields (less friction than a multi-step wizard; both values are required before submit).

```
┌─────────────────────────────────────┐
│  Create your account                │
│                                     │
│  OFFICIAL CAMPUS EMAIL              │
│  [ you@students.livingstone.edu ]   │
│  Used for login and to confirm you  │
│  are part of the LC community.      │
│                                     │
│  PERSONAL EMAIL (for your code)     │
│  [ you@gmail.com ]                  │
│  We send your 8-digit confirmation  │
│  code here — student inboxes often  │
│  block app mail.                    │
│                                     │
│  Password / Confirm password        │
│  [ Create account ]                 │
└─────────────────────────────────────┘
```

Then **Verify email** screen copy references the **personal** address (“We sent a code to `you@gmail.com`”). OTP verification still uses the **campus email** as the Supabase auth identity (`verifyOTP(email: campusEmail)`).

**Login (unchanged):** campus email + password.

---

## Technical model

| Field | Storage | Purpose |
|-------|---------|---------|
| Campus email | `users.email` + Supabase `auth.users.email` | Identity, role inference, login |
| Personal email | `users.contact_email` + Supabase `user_metadata.contact_email` | OTP / recovery delivery target |
| Email confirmed | `users.is_verified` | Account activated (OTP done) |
| Campus verified | `users.campus_verified` (Phase 2) | Admin-granted badge |

**Email hook routing:** On signup/recovery, if `user_metadata.contact_email` is set, send the OTP to that address instead of `user.email`.

---

## Phase 1 — Dual-email signup (delivery fix)

**Goal:** New students can complete signup; confirmation codes arrive at a personal inbox.

### Checklist

#### Backend
- [x] Migration: `users.contact_email` (nullable, indexed)
- [x] `normalize_personal_contact_email()` — valid email, must **not** be a campus domain
- [x] `bootstrap_user()` — persist `contact_email` from JWT `user_metadata.contact_email`
- [x] Send Email hook — route signup (+ recovery) OTP to `contact_email` when present
- [x] Signup email template — mention campus email being registered (optional copy tweak)
- [x] Unit tests: contact email normalization, hook routing, bootstrap persistence
- [x] DB tests: bootstrap stores `contact_email` from claims metadata

#### Mobile
- [x] Register screen: campus + personal email fields (one screen, two sections)
- [x] `signUp(data: {'contact_email': ...})` via Supabase metadata
- [x] Verify screen: copy shows personal email; resend message updated
- [x] `AuthNotifier`: track `pendingContactEmail` for verify UI
- [x] `flutter analyze` (auth feature clean)

#### Ops / Supabase
- [ ] Confirm Send Email hook remains enabled in Supabase dashboard
- [ ] Smoke test: signup with real `@students.livingstone.edu` + personal Gmail
- [ ] (Parallel) Open IT ticket to allowlist `noreply@lcconnect.app` / Resend for student mail

#### Hardening (Phase 1)
- [x] Reject personal email that equals campus email (campus-domain validator on personal field)
- [x] Reject personal email on campus domains
- [x] Hook falls back to campus email if metadata missing (backward compatible)
- [x] Run full backend unit suite
- [ ] `flutter test` auth/messages smoke (run before release)

---

## Phase 2 — Campus verification badge (admin)

**Goal:** Checkmark means “verified LC community member,” not “completed OTP.”

### Checklist

#### Backend
- [x] Migration: `users.campus_verified` (bool, default `false`), `campus_verified_at`, `campus_verified_by_id`
- [x] `ProfilePublic.is_verified` / serializers read `campus_verified` for badge (not `is_verified`)
- [x] Admin API: `POST /admin/users/{id}/campus-verify`, `POST .../revoke-campus-verify`
- [x] Audit log entries for verify/revoke (`user.campus_verify`, `user.campus_verify_revoke`)
- [x] DB + API tests; OpenAPI snapshot update (intentional)

#### Admin portal
- [x] Users table: campus email, personal email, email confirmed, campus badge columns
- [x] Actions: **Verify campus** / **Revoke badge** (distinct from Suspend)
- [x] Filter: “Pending campus verification” (active + OTP done + not campus verified)

#### Mobile
- [x] Badge reads `is_verified` from API — backend now maps that field to `campus_verified` (no app change)
- [x] No app gate on badge (full access after OTP); badge is trust signal only

#### Hardening (Phase 2)
- [x] Backfill: migration defaults `campus_verified=false` for all existing users (no auto-badge)
- [x] Admin SOP documented below
- [ ] Manual pilot: verify 5 real students, revoke 1 test account

---

## Admin SOP — campus verification vs suspend

| Action | When to use | Effect |
|--------|-------------|--------|
| **Verify campus** | Student completed OTP, you confirmed they are a real LC student/staff member | Profile checkmark appears; trust signal only — full app access was already granted after OTP |
| **Revoke badge** | Verification was mistaken, or person is no longer affiliated | Checkmark removed; account stays active unless you also suspend |
| **Suspend** | Policy violation, harassment, fraud — enforcement | User signed out and blocked from the app entirely |

**Pending campus verification** filter shows: `status=active` + email confirmed + no campus badge yet. Work this queue after new signups.

**Do not** use campus verification to gate app access — that is what email OTP (`is_verified`) is for.

---

## Phase 3 — Password reset & IT (optional polish)

- [ ] Password reset OTP routes to `contact_email` when set (hook already partially shares path)
- [ ] Forgot-password mobile copy references personal email if on file
- [ ] Admin export: users missing `contact_email` (pre-migration accounts)
- [ ] IT allowlist confirmed or documented as accepted risk

---

## Test matrix (summary)

| Area | Phase 1 | Phase 2 |
|------|---------|---------|
| `test_email_hook.py` | OTP sent to `contact_email` on signup | — |
| `test_email_roles.py` | Personal email rejects campus domains | — |
| `tests/db/test_auth_bootstrap_roles.py` | Bootstrap persists metadata | — |
| `tests/db/test_campus_verification.py` | — | Admin verify/revoke, badge field |
| `mobile/test/features/auth/` | Register validation, verify copy | Badge from API |
| Manual | End-to-end signup on device | Admin verify flow |

---

## Execution order

1. **Phase 1** (this sprint) — unblocks student signups  
2. **Phase 2** — trust badge + admin workflow  
3. **Phase 3** — reset polish + IT follow-up  

Phase 1 must ship before Phase 2 so new accounts already carry `contact_email`.
