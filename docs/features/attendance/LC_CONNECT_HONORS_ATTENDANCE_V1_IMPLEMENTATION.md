# LC Connect — Honors Attendance V1 Implementation Specification

**Project:** LC Connect  
**Feature:** Honors Attendance  
**Version:** V1 Prototype  
**Status:** Approved — aligned with existing LC Connect Honors infrastructure  
**Primary verification method:** Rotating QR code  
**Bluetooth proximity:** Deferred / inactive in V1  

> **Naming note:** Early drafts used “Ernest” throughout; that was a spelling mistake. This feature is **Honors attendance** for **Honors students** (the same roster managed as Presidential Scholars in the admin portal).

---

## 1. Purpose

LC Connect already provides a campus-wide mobile experience for Livingstone College students, including authenticated student accounts, staff/admin roles, campus content, messaging, activities, and push notifications.

The Honors Attendance feature adds a focused academic utility for **Honors students only**.

The goal is to replace manual roll call for large classes with a fast, clean attendance workflow where:

- the instructor starts one attendance session from the existing admin portal;
- a large rotating QR code is displayed in the classroom;
- only eligible Honors students are notified;
- students tap the notification, scan the current QR code, and are automatically checked in;
- the instructor sees the attendance roster and counts update in real time;
- attendance can later be reviewed, exported, or manually corrected;
- Bluetooth or other proximity technologies can be added later without changing the core attendance model.

The V1 priority is **reliability, speed, simplicity, and clean user experience**.

## 1.1 LC Connect integration (reuse — do not duplicate)

Attendance is a new workflow on top of infrastructure that already exists in this repository. **Do not** add parallel enrollment or instructor tables.

| Concern | Existing LC Connect surface | How attendance uses it |
|--------|------------------------------|---------------------------|
| Honors student roster | `Program` + `ProgramMembership` (`programs.slug = 'presidential_scholars'`) | Check-in eligibility = active membership on that program; same list as **Presidential Scholars** in admin (`/dashboard/scholars`) |
| Honors instructor access | `AdminMembership` scope `honors_admin` (+ `super_admin` override) | Instructor/admin APIs use `require_admin_aal2` + `require_admin_scope('honors_admin')` — same gate as Scholars and Employers |
| Inviting Honors admins | `super_admin` / `school_admin` invite matrix | No new invite flow; main admins can already invite `honors_admin` |
| Admin portal placement | `honorsOnly` nav section in `admin/app/(dashboard)/layout.tsx` | Add **Attendance** alongside Presidential Scholars and Employer Partners |
| Student auth | Supabase JWT → `require_verified_connect_student` | Check-in requires verified `student` role + active program membership |
| Push | `app/features/notifications/push.py` (FCM) | New `honors_attendance_open` type; bulk send on session start (background task) |
| Audit | `record_audit()` / `AdminAuditLog` or `AttendanceAuditLog` | Manual corrections must be auditable |
| Models layout | `backend/app/models/` (split by domain) | New `attendance.py`; re-export from `app/models/__init__.py` |

**Locked V1 decisions (integration):**

1. **One open Honors attendance session at a time** — partial unique index on `status = 'open'` for the Honors program; students never pick a session.
2. **QR challenges in Redis** — ephemeral TTL keys (`ATTENDANCE_QR_TTL_SECONDS`); Postgres stores durable sessions and records only.
3. **Admin live UI uses polling in V1** — poll QR (~8s) and roster (~2–3s); extend WebSocket protocol later if needed (current `/ws` is chat-only).
4. **Absent rows materialized on close** — when a session closes, insert `AttendanceRecord(status=absent)` for active Honors members who never checked in.
5. **Export** — V1 ships an export-ready data model; CSV/export API/UI can follow after pilot.


---

# 2. Product Scope

## 2.1 In Scope

V1 includes:

- Honors program membership gating (existing `ProgramMembership` on `presidential_scholars`)
- `honors_admin`-scoped instructor access (existing `AdminMembership`)
- instructor attendance dashboard in the existing admin portal
- start attendance session
- rotating short-lived QR codes
- push notification to eligible Honors students
- notification deep-link into the attendance scanner
- student camera-based QR scanning
- server-side QR validation
- automatic attendance marking
- duplicate check-in prevention
- Present / Late / Absent / Excused statuses
- optional late attendance window
- automatic session closure
- instructor manual closure
- live attendance count
- real-time roster updates
- manual instructor attendance correction
- audit trail for manual changes
- attendance history
- attendance session detail view
- export-ready backend data model
- security protections against replaying expired QR codes
- role and membership authorization

## 2.2 Explicitly Out of Scope for V1

The following are intentionally not part of the first working prototype:

- Bluetooth verification
- BLE classroom beacons
- instructor Bluetooth broadcasting
- GPS attendance verification
- continuous student location tracking
- Wi-Fi classroom verification
- NFC attendance
- facial recognition
- selfie verification
- biometric attendance
- automatic course schedule import
- general attendance for every Livingstone College student
- student class search
- student selection of attendance session
- manual attendance codes entered by students

The system should be structured so Bluetooth can later become an additional verification method, but **no attendance decision in V1 depends on Bluetooth**.

---

# 3. Core Product Rules

The following rules are fixed for V1.

## 3.1 Honors-only attendance

LC Connect remains a campus-wide platform, but the attendance feature is available only to students with **active `ProgramMembership`** on the Honors program (`presidential_scholars`).

The backend must own this membership via the existing program tables — not profile fields or client state.

Do not infer Honors program membership from:

- major
- class year
- email
- profile text
- student self-selection
- mobile client state

Use an explicit Honors program membership record.

---

## 3.2 No student class search

Students must never search for or select a class before checking in.

When attendance is active, the backend already knows:

- who the authenticated student is;
- whether the student is an active Honors program member;
- which Honors attendance session is active;
- whether the student is eligible to check in.

The student flow must remain:

```text
Notification
    ↓
Tap
    ↓
Attendance scanner opens
    ↓
Scan QR
    ↓
Validated by backend
    ↓
Present / Late
```

No additional form should be required.

---

## 3.3 Instructor starts attendance

Authorized Honors instructors manage attendance from the existing LC Connect admin portal.

An instructor should need only one primary action:

```text
Start Attendance
```

Starting attendance creates the server-side session and immediately begins QR rotation.

---

## 3.4 QR is the attendance proof in V1

The QR code shown in the classroom is the V1 proof that the student has access to the current in-room attendance challenge.

The QR must:

- be generated from server-owned session data;
- expire quickly;
- rotate automatically;
- be validated server-side;
- never permanently identify a classroom;
- never contain a reusable permanent attendance secret.

Recommended default:

```text
QR validity: 10 seconds
```

This value should be configuration-driven.

---

## 3.5 Push notification does not mark attendance

The notification is only an entry point into the attendance flow.

Receiving or tapping a notification must never count as attendance.

The push notification should say approximately:

> **Honors attendance is open**  
> Tap to scan the classroom QR.

A remote student may receive the same notification, but cannot complete attendance without successfully scanning a currently valid classroom QR.

---

# 4. User Roles

LC Connect already distinguishes user roles server-side.

Attendance introduces an additional authorization layer.

## 4.1 Student

A student may check in only when all conditions are true:

- authenticated;
- active LC Connect account;
- verified account;
- role is `student`;
- active Honors program membership exists;
- attendance session is open;
- session belongs to the Honors program;
- QR challenge is current and valid;
- student has not already checked in.

---

## 4.2 Honors instructor (`honors_admin`)

Not every admin account may run Honors attendance — only users with the `honors_admin` scope (or `super_admin`).

Honors instructors are **admin-portal users**, not generic `staff` accounts. They are invited through Admins & Roles like other Honors administrators.

An Honors instructor may:

- view Honors attendance dashboard;
- start attendance;
- view active session;
- view live check-ins;
- close attendance;
- review past sessions;
- manually update attendance status;
- add correction notes;
- export attendance when export support is enabled.

---

## 4.3 Other admin scopes

`super_admin` may always run Honors attendance (scope override).

`content_admin`, `auditor`, and other non-Honors scopes must **not** start sessions or view live rosters unless explicitly granted `honors_admin`.

---

# 5. High-Level Architecture

The feature should follow the existing LC Connect feature-first architecture.

## Backend

```text
backend/
└── app/
    └── features/
        └── attendance/
            ├── __init__.py
            ├── router.py
            ├── service.py
            ├── schema.py
            ├── qr.py
            ├── permissions.py     # is_honors_member, require_honors_attendance_admin
            └── admin_router.py      # /admin/attendance/honors/* (optional split from router.py)
```

New attendance models live in `backend/app/models/attendance.py` and are re-exported from `app/models/__init__.py` (one metadata, split by domain — see `CONVENTIONS.md`).

---

## Mobile

```text
mobile/
└── lib/
    └── features/
        └── attendance/
            ├── providers/
            │   ├── attendance_provider.dart
            │   └── attendance_scanner_provider.dart
            ├── screens/
            │   ├── attendance_scanner_screen.dart
            │   ├── attendance_success_screen.dart
            │   └── attendance_status_screen.dart
            └── widgets/
                ├── attendance_open_card.dart
                ├── scanner_overlay.dart
                └── attendance_result.dart
```

Data access stays in providers rather than directly inside screens.

---

## Admin Portal

```text
admin/
└── app/
    └── (dashboard)/
        └── dashboard/
            └── attendance/          # honorsOnly nav — same section as Scholars
                ├── page.tsx
                ├── [sessionId]/
                │   └── page.tsx
                └── history/
                    └── page.tsx
```

Supporting components may live under:

```text
admin/components/attendance/
```

---

# 6. Data Model

The exact model files should follow the current repository conventions.

Recommended entities are below.

---

## 6.1 Honors student eligibility — reuse `ProgramMembership`

**Do not create a new enrollment table.** Honors attendance eligibility is the same roster already managed for Blueprint Bond / Presidential Scholars.

Use the existing models in `backend/app/models/programs.py`:

- `Program` with `slug = 'presidential_scholars'` (seeded by migration `5f045e1e9b50`)
- `ProgramMembership` with `status = 'active'` for the student

Gate check-in with `is_active_program_member(db, user_id, PRESIDENTIAL_SCHOLARS_SLUG)` from `app/shared/programs.py` (same helper used by Scholars and campus content gating).

Admin verify/revoke UI already exists at `GET/POST /api/v1/admin/programs/presidential_scholars/members` (`require_admin_scope('honors_admin')`).

Only students with **active** Honors program membership receive attendance push, the Campus Hub card, and check-in permission.

---

## 6.2 Honors instructor access — reuse `honors_admin`

**Do not create a new instructor table.** Honors instructors are admin-portal users with the existing `honors_admin` scope on `AdminMembership`.

Requirements (already enforced for Scholars / Employers admin):

- `User.role == 'admin'`
- Supabase MFA session (`require_admin_aal2`)
- Active `AdminMembership` with `role = 'honors_admin'` (or `super_admin`, which passes all scope checks)

`super_admin` and `school_admin` can invite `honors_admin` through the existing Admins & Roles flow — no new invite matrix entry.

Attendance admin routes: `Depends(require_admin_scope('honors_admin'))`.

Not every admin scope may run attendance — e.g. `content_admin` and `auditor` must not.

---

## 6.3 AttendanceSession

Represents one live or historical attendance event.

```text
AttendanceSession
-----------------
id
program_id
title
started_by
opened_at
present_until
late_until
closed_at
status
created_at
updated_at
```

Recommended status values:

```text
scheduled
open
closed
cancelled
```

For V1, the system can begin directly with `open` sessions without requiring schedule creation.

Recommended fields:

- `id: UUID`
- `program_id: UUID → programs.id` (Honors program; `presidential_scholars` at seed time)
- `title: string`
- `started_by: UUID → users.id`
- `opened_at`
- `present_until`
- `late_until` nullable
- `closed_at` nullable
- `status`
- `created_at`
- `updated_at`

**Constraints / indexes:**

- Partial unique index: at most one `open` session per Honors `program_id` in V1.
- Index on `(program_id, status)` for dashboard queries.

Default timing recommendation:

```text
Present window: 3 minutes
Late window: optional 2 additional minutes
QR rotation: every 10 seconds
```

All values should be configurable.

---

## 6.4 AttendanceRecord

One student's attendance result for one session.

```text
AttendanceRecord
----------------
id
session_id
student_id
status
verification_method
checked_in_at
original_checked_in_at
manually_modified
modified_by
modified_at
modification_reason
created_at
updated_at
```

Recommended status values:

```text
present
late
absent
excused
```

Recommended verification methods:

```text
qr
manual
```

Future values may include:

```text
qr_ble
ble
```

Do not activate future methods in V1.

Critical database constraint:

```text
UNIQUE(session_id, student_id)
```

This guarantees one attendance record per student per session, even under simultaneous or repeated requests.

---

## 6.5 AttendanceAuditLog

Records instructor/admin corrections.

```text
AttendanceAuditLog
------------------
id
attendance_record_id
changed_by
previous_status
new_status
reason
created_at
```

Manual attendance edits must always be auditable.

---

# 7. Attendance Session Lifecycle

## 7.1 Starting Attendance

Instructor opens:

```text
Admin Portal
→ Honors Attendance
→ Start Attendance
```

The backend:

1. authenticates the caller;
2. verifies Honors instructor permission;
3. confirms there is no conflicting active Honors session if V1 allows only one;
4. creates `AttendanceSession`;
5. calculates `present_until`;
6. calculates optional `late_until`;
7. marks session `open`;
8. creates the first QR challenge;
9. sends push notifications to eligible Honors students;
10. publishes a real-time session-open event.

---

## 7.2 Open Session

While the session is open:

- QR code rotates automatically;
- admin portal displays current QR;
- students may scan;
- successful check-ins appear immediately in the portal;
- live total increments;
- QR expiration is independent from attendance-session expiration.

Example:

```text
Attendance Session
09:00:00 ───────────────────────── 09:05:00

QR A
09:00:00–09:00:10

QR B
09:00:10–09:00:20

QR C
09:00:20–09:00:30
```

A QR expiring does not close attendance. It only means a new QR challenge is required.

---

## 7.3 Present Window

During:

```text
opened_at <= now <= present_until
```

a valid first check-in receives:

```text
status = present
```

---

## 7.4 Late Window

If late attendance is enabled:

```text
present_until < now <= late_until
```

a valid first check-in receives:

```text
status = late
```

No additional student interaction is required.

---

## 7.5 Closed Session

The session closes when:

- instructor manually ends attendance; or
- `late_until` expires; or
- `present_until` expires when no late window is enabled.

Once closed:

- QR challenges are invalid;
- no student check-in is accepted;
- the backend **materializes** `AttendanceRecord(status=absent)` for every active Honors program member who did not check in (part of the close-session transaction);
- instructor may still perform manual corrections.

---

# 8. QR Security Design

The QR must not contain a permanent or reusable secret.

Recommended QR payload:

```json
{
  "v": 1,
  "session_id": "<uuid>",
  "challenge_id": "<uuid>",
  "expires_at": "<timestamp>",
  "token": "<signed server token>"
}
```

The token must be generated and validated by the backend.

Possible implementation:

```text
token = HMAC(
    attendance_server_secret,
    session_id + challenge_id + expires_at
)
```

Alternative signed-token approaches are acceptable if already consistent with project security practices.

The student app must never be trusted to determine whether the QR is valid.

---

## 8.1 Server Validation

On scan, the backend checks:

1. authenticated user;
2. role is student;
3. verified account;
4. active Honors program membership;
5. session exists;
6. session is open;
7. session belongs to the Honors program;
8. challenge belongs to that session;
9. challenge has not expired;
10. token signature is valid;
11. student does not already have attendance for the session.

Only after all checks succeed may attendance be written.

---

## 8.2 Replay Protection

A QR screenshot older than its validity window must fail.

Server response:

```text
QR expired. Scan the current classroom code.
```

The client should immediately return to scanning.

Repeated scanning by the same successfully checked-in student must not create another record.

Recommended response:

```text
You're already checked in.
```

with the existing attendance result.


## 8.3 QR challenge storage (Redis)

Active QR challenges are **ephemeral** — store them in Redis, not PostgreSQL.

Recommended key pattern:

```text
attendance:challenge:{session_id}:{challenge_id}
```

- TTL = `ATTENDANCE_QR_TTL_SECONDS` (default 10).
- Value may hold `expires_at` and a consumed flag, or the key may be deleted on successful validation for one-time use within the TTL window.
- On session close, delete or let all challenge keys for that session expire.

This matches the architecture direction: Redis for TTL/ephemeral state; Postgres for durable attendance truth.

---

# 9. Recommended API

Exact route naming may be adjusted to match existing API conventions.

---

## 9.1 Student APIs

### Get active Honors attendance

```http
GET /api/v1/attendance/honors/active
```

Returns:

- whether attendance is open;
- session id;
- title;
- timing;
- student's existing attendance status if already checked in.

---

### Validate and check in

```http
POST /api/v1/attendance/sessions/{session_id}/check-in
```

Request:

```json
{
  "challenge_id": "...",
  "expires_at": "...",
  "token": "..."
}
```

Response:

```json
{
  "status": "present",
  "checked_in_at": "...",
  "session_id": "...",
  "message": "You're checked in."
}
```

Possible status:

```text
present
late
```

---

## 9.2 Instructor/Admin APIs

### Get attendance dashboard

```http
GET /api/v1/admin/attendance/honors
```

---

### Start attendance

```http
POST /api/v1/admin/attendance/honors/sessions
```

Request example:

```json
{
  "title": "Honors Class",
  "present_window_seconds": 180,
  "late_window_seconds": 120
}
```

---

### Get current QR challenge

```http
GET /api/v1/admin/attendance/sessions/{session_id}/qr
```

Response contains only the current short-lived QR payload.

---

### Get active roster

```http
GET /api/v1/admin/attendance/sessions/{session_id}/roster
```

---

### Close attendance

```http
POST /api/v1/admin/attendance/sessions/{session_id}/close
```

---

### Manual attendance correction

```http
PATCH /api/v1/admin/attendance/records/{record_id}
```

Request:

```json
{
  "status": "excused",
  "reason": "Approved absence"
}
```

---

### Attendance history

```http
GET /api/v1/admin/attendance/honors/history
```

---

# 10. Notification Integration

Reuse LC Connect's existing notification infrastructure.

Do not build a separate push system.

When attendance begins:

1. backend finds all active Honors students;
2. backend finds registered device tokens for those users;
3. backend creates an in-app notification record;
4. backend sends FCM/APNs push where available;
5. notification payload deep-links into the attendance scanner.

Recommended push:

**Title**

```text
Honors attendance is open
```

**Body**

```text
Tap to scan the classroom QR.
```

Recommended data payload:

```json
{
  "type": "honors_attendance_open",
  "session_id": "<uuid>"
}
```

Do not place secret QR data inside the notification.

---

# 11. Mobile Student UX

## 11.1 Entry Points

Attendance may be entered from:

- push notification;
- foreground in-app notification/banner;
- active-attendance card on the Campus screen.

The push notification is the primary entry point during class.

---

## 11.2 Campus Home Card

Only active Honors students should see the attendance card.

When no session is active:

```text
No attendance card is necessary.
```

When active:

```text
┌─────────────────────────────────────┐
│ Attendance is open                  │
│ Honors Class                        │
│ Closes in 02:14                     │
│                                     │
│ [ Scan to Check In ]                │
└─────────────────────────────────────┘
```

Students without active Honors program membership must not see the card.

---

## 11.3 Scanner Flow

```text
Tap notification
    ↓
Attendance scanner
    ↓
Camera permission if required
    ↓
Camera opens
    ↓
QR detected
    ↓
App submits payload to backend
    ↓
Loading state
    ↓
Success
```

No extra confirmation.

---

## 11.4 Success State

Example:

```text
✓ You're present

Honors Class
Checked in at 9:02 AM
```

For late attendance:

```text
✓ Check-in recorded

Status: Late
Checked in at 9:04 AM
```

The student should not have to scan again.

---

## 11.5 Error States

### Expired QR

```text
That QR has expired.
Scan the current classroom code.
```

Return directly to scanner.

### Attendance Closed

```text
Attendance is closed.
```

### Not Honors Student

```text
This attendance session is not available for your account.
```

### Already Checked In

```text
You're already checked in.
```

Show existing status and timestamp.

### Camera Permission Denied

Explain clearly:

```text
Camera access is required to scan the attendance QR.
```

Provide:

```text
Open Settings
```

No Bluetooth permission should be requested in V1.

---

# 12. Admin / Instructor Portal UX

Attendance should be a first-class dashboard section within the existing admin portal.

Place **Attendance** in the existing **Honors** (`honorsOnly`) nav section — alongside Presidential Scholars and Employer Partners — visible only to `honors_admin` and `super_admin`.

```text
Dashboard
Campus Hub
Users
…
── Honors section ──
Presidential Scholars
Employer Partners
Attendance          ← new
── … ──
Admins & Roles
```

---

## 12.1 Attendance Landing Page

Example:

```text
Honors Attendance

Today
──────────────────────────────────

Honors Class
No active attendance session

[ Start Attendance ]

Recent Sessions
──────────────────────────────────
Aug 24     196 / 203 present
Aug 22     191 / 203 present
Aug 20     198 / 203 present
```

---

## 12.2 Start Attendance

Click:

```text
Start Attendance
```

Recommended simple dialog:

```text
Start Honors Attendance

Present window
3 minutes

Late check-in
2 minutes

[ Cancel ]        [ Start Attendance ]
```

Defaults should be prefilled.

Do not burden instructors with technical QR settings.

---

## 12.3 Active Attendance View

The most important live screen:

```text
Honors Class
Attendance open • 01:42 remaining

143 / 203 checked in
━━━━━━━━━━━━━━━━━━━━━━━━━━ 70%

Present    139
Late         4
Remaining   60

┌──────────────────────────────┐
│                              │
│         ROTATING QR          │
│                              │
│    Refreshes automatically   │
│                              │
└──────────────────────────────┘

Recent check-ins
──────────────────────────────
✓ Student Name          9:02 AM
✓ Student Name          9:02 AM
✓ Student Name          9:03 AM

[ End Attendance ]
```

The QR should be large enough for projection.

---

## 12.4 Live Updates

Instructor should not manually refresh.

When a student checks in:

```text
143 / 203
      ↓
144 / 203
```

The roster updates automatically.

**V1: polling is the primary mechanism.** The admin portal does not use the chat WebSocket today.

While a session is open:

- poll `GET .../sessions/{id}/qr` about every 8 seconds for the rotating QR payload;
- poll `GET .../sessions/{id}/roster` about every 2–3 seconds for counts and recent check-ins.

**V2 (optional):** extend `app/features/realtime/protocol.py` with `attendance.subscribe` events (`attendance.checked_in`, etc.) and/or Redis pub/sub fan-out.

---

## 12.5 Session Review

After closing:

```text
Honors Class
August 24, 2026

Present       191
Late            5
Absent          6
Excused         1

Search students...

Student               Status        Time
──────────────────────────────────────────
Student A             Present       9:02
Student B             Late          9:04
Student C             Absent        —
Student D             Excused       —
```

---

## 12.6 Manual Correction

Instructor may select a student and modify:

```text
Present
Late
Absent
Excused
```

Any change requires:

```text
Reason
```

Example:

```text
Changed: Absent → Excused
Reason: Approved absence
```

Every change must produce an audit log entry.

---

# 13. Live updates architecture

## V1 (shipping)

Admin portal polling (see §12.4). No WebSocket changes required for pilot.

## V2 (optional) — WebSocket events

Recommended event:

```text
attendance.checked_in
```

Payload:

```json
{
  "session_id": "...",
  "student_id": "...",
  "status": "present",
  "checked_in_at": "..."
}
```

Honors admin client would subscribe to the active session (not implemented in V1).

Recommended additional events:

```text
attendance.session_started
attendance.session_closed
attendance.record_updated
```

Do not broadcast unnecessary student-private information outside the authorized instructor view.

---

# 14. Concurrency and Scale

The expected classroom size may exceed 200 students checking in over a short period.

The backend must safely handle many simultaneous requests.

Important protections:

- unique database constraint on `(session_id, student_id)`;
- transactional check-in logic;
- idempotent result when student retries;
- no per-student QR generation;
- one rotating classroom QR shared by the session;
- indexes on session and student foreign keys;
- avoid N+1 queries on instructor roster views.

A burst of 200 check-ins should not create 200 independent push or QR-generation jobs.

Push happens once when the session opens.

---

# 15. Authorization

Never rely only on hidden UI.

## Student check-in endpoint

Require:

```text
require_verified_connect_student
AND is_active_program_member(user_id, 'presidential_scholars')
AND HONORS_ATTENDANCE_ENABLED
AND session open + valid QR
```

Suspended or inactive accounts are rejected by existing auth dependencies.

## Instructor / admin endpoint

Require:

```text
require_admin_aal2
AND require_admin_scope('honors_admin')   # super_admin passes implicitly
AND HONORS_ATTENDANCE_ENABLED
```

Never hard-code instructor emails in route logic.

---

# 16. Privacy

V1 must not continuously track students.

Do not collect:

- GPS history;
- Bluetooth history;
- background location;
- classroom movement;
- camera images.

The camera is only used locally to decode the QR.

The backend should receive the decoded QR payload, not a photo of the classroom.

Store only attendance-relevant data:

```text
student
session
status
verification method
timestamp
manual modifications
```

---

# 17. Configuration

Recommended environment settings:

```text
ATTENDANCE_ENABLED=true
HONORS_ATTENDANCE_ENABLED=true

ATTENDANCE_QR_TTL_SECONDS=10
ATTENDANCE_PRESENT_WINDOW_SECONDS=180
ATTENDANCE_LATE_WINDOW_SECONDS=120

ATTENDANCE_QR_SIGNING_SECRET=<server secret>
```

Optional future feature flag:

```text
ATTENDANCE_BLE_ENABLED=false
```

This may be reserved for later, but no Bluetooth implementation is required in V1.

---

# 18. Feature Flags

Attendance should be independently controllable.

Recommended:

```text
HONORS_ATTENDANCE_ENABLED
```

If false:

- attendance APIs reject or hide feature appropriately;
- student attendance UI is hidden;
- admin attendance UI is hidden;
- normal LC Connect remains unaffected.

This reduces rollout risk.

---

# 19. Testing Plan

## 19.1 Backend Unit Tests

Test:

- Honors program membership authorization
- instructor authorization
- session creation
- only one active session if that rule is enabled
- QR signing
- QR expiration
- invalid signature
- wrong session
- closed session
- present-window status
- late-window status
- duplicate check-in
- inactive Honors student
- non-Honors student
- staff attempting student check-in
- student attempting instructor endpoint
- manual correction
- audit log generation

---

## 19.2 Database Tests

Test:

```text
UNIQUE(session_id, student_id)
```

under concurrent requests.

Test roster generation.

Test automatic absent calculation after session closure.

---

## 19.3 Mobile Tests

Test:

- notification deep-link
- scanner opens
- camera permission flow
- valid scan
- expired scan
- already checked in
- closed attendance
- non-Honors user
- success state
- late state
- no Bluetooth permission requested

---

## 19.4 Admin Portal Tests

Test:

- admins without `honors_admin` cannot access
- authorized instructor can access
- session start
- QR refresh
- live roster update
- close session
- historical session view
- manual correction
- audit note
- responsive layout
- projector-size QR visibility

---

## 19.5 Load Test

Simulate approximately:

```text
250 students
checking in within 60–120 seconds
```

Verify:

- no duplicate rows;
- predictable latency;
- no dropped successful check-ins;
- admin live count remains accurate;
- database connection pool remains healthy.

---

# 20. Suggested Implementation Order

## Phase 1 — Data and Permissions

Build:

- `backend/app/models/attendance.py` — `AttendanceSession`, `AttendanceRecord`, `AttendanceAuditLog`
- Alembic migration (partial unique index for one open session per program)
- `app/features/attendance/permissions.py` — program membership + `honors_admin` helpers
- Confirm Honors roster via existing `presidential_scholars` seed (no new program table)
- Feature flag `HONORS_ATTENDANCE_ENABLED` in `app/config.py`

---

## Phase 2 — Session and QR Backend

Build:

- start session
- close session
- QR challenge creation
- QR signing
- QR validation
- present/late time calculation
- student check-in endpoint
- duplicate protection

---

## Phase 3 — Admin Portal

Build:

- Attendance navigation item
- attendance landing page
- start attendance dialog
- large live QR
- live counts
- live roster
- close session
- history
- session review
- manual corrections

---

## Phase 4 — Mobile Student Flow

Build:

- attendance provider
- notification deep-link
- scanner route
- camera scanning
- server validation
- success state
- attendance active card
- Honors program membership visibility

---

## Phase 5 — Notifications

Integrate:

- targeted push to active Honors students
- in-app notification entry
- attendance deep-link
- notification content
- no attendance secret in push payload

---

## Phase 6 — Live admin UX (polling)

Integrate:

- admin QR polling loop
- admin roster/count polling loop
- stable loading/error states when polls fail

(Optional follow-up: WebSocket attendance events — not required for V1 acceptance.)

---

## Phase 7 — Testing and Pilot Hardening

Run:

- backend tests
- Flutter analyze/tests
- admin lint/build/tests
- concurrency test
- 200+ simulated student check-ins
- real-device QR scanning
- projector QR test
- expired QR screenshot test
- duplicate scan test
- notification-open test

---

# 21. Acceptance Criteria

V1 is complete when all of the following are true.

## Instructor

- authorized Honors instructor can open Attendance in admin portal;
- instructor can start attendance in one action;
- rotating QR appears immediately;
- QR updates automatically without page refresh;
- instructor sees live check-in count;
- instructor sees student roster update in real time;
- instructor can manually close attendance;
- instructor can review historical attendance;
- instructor can correct attendance with an audit reason.

## Student

- only active Honors students receive attendance functionality;
- eligible students receive attendance push;
- tapping push opens attendance scanner directly;
- student does not search for a class;
- student does not type a code;
- valid current QR marks attendance automatically;
- student receives clear Present or Late success state;
- duplicate scan does not duplicate attendance;
- expired QR is rejected;
- non-Honors student cannot check in.

## Security

- QR expires approximately every 10 seconds;
- expired screenshot cannot be reused;
- QR validation is server-side;
- client cannot self-declare attendance;
- one record exists per student per session;
- admins without `honors_admin` cannot start or modify Honors attendance;
- no Bluetooth requirement exists;
- no GPS tracking exists;
- no continuous location data is stored.

---

# 22. V2 Extension Path

The V1 data model should preserve:

```text
verification_method
```

so future verification can be added without redesigning attendance records.

Possible future methods:

```text
qr
qr_ble
ble
```

When Bluetooth is eventually introduced:

- it should be feature-flagged;
- it should initially act as an additional confidence signal;
- basic QR attendance must remain functional if Bluetooth is unavailable;
- Bluetooth failure must not destroy the student UX.

For now:

```text
ATTENDANCE_BLE_ENABLED=false
```

Bluetooth is intentionally inactive.

---

# 23. Final V1 Flow

## Instructor

```text
Admin Portal
    ↓
Attendance
    ↓
Start Attendance
    ↓
Rotating QR displayed
    ↓
Push sent to Honors students
    ↓
Live count + roster updates
    ↓
End Attendance
    ↓
Review / Correct / Export
```

## Student

```text
Push notification
    ↓
Tap
    ↓
Attendance scanner opens
    ↓
Scan current classroom QR
    ↓
Backend validates:
    authenticated
    + Honors program member
    + active session
    + fresh signed QR
    + not already checked in
    ↓
Present / Late
    ↓
Instructor dashboard updates
```

---

# 24. Final Product Principle

The implementation may be technically sophisticated behind the scenes, but the visible user experience should remain extremely simple.

**Instructor:**

```text
Start Attendance
```

**Student:**

```text
Scan
```

Everything else belongs to the system.

That is the standard V1 should preserve as the feature grows.
