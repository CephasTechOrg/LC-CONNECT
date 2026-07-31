# LC Connect — The Blueprint Bond Integration Specification

**Presidential Scholars & Employer Partnership Integration**  
**Implementation baseline:** `feat/supabase-auth-phase1`  
**Prepared:** July 31, 2026

> **Core decision:** Blueprint Bond is a specialized program module inside LC Connect, not a separate student platform.

## 1. Purpose

This specification defines how LC Connect will integrate The Blueprint Bond into the existing Flutter, FastAPI, Supabase, Campus Hub, Opportunities, notifications, and admin architecture.

The integration is reuse-first:

- one LC Connect student account;
- one existing profile with a restricted professional extension;
- one existing Opportunities system;
- one existing admin portal with permission-scoped Honors pages;
- one separate employer-facing web portal using the same backend.

## 2. Final product decisions

- Students never self-identify as Presidential Scholars.
- Honors administrators verify membership from an official roster.
- Verified scholars receive a notification and unlock a Blueprint Bond section in Profile and Campus Hub.
- Professional fields are visible only to approved employers and authorized Honors administrators.
- Regular students never see scholar-only profile controls or the Blueprint Bond opportunity filter.
- Employers register and remain pending until approved.
- Employer opportunities are reviewed before publication.
- Approved employer opportunities publish into the existing `CampusPost(kind = opportunity)` system.
- Honors administrators use the existing admin portal with scoped permissions.
- Every administrator uses an individual account; no passwords are shared.
- The platform maintainer supports the system but does not routinely make school-owned program decisions.

## 3. Student experience

### Scholar activation

1. The student uses LC Connect normally.
2. An Honors administrator verifies `ProgramMembership`.
3. The student receives a notification.
4. A Blueprint Bond completion card appears in Profile and Campus Hub.
5. The student completes professional fields.
6. The student grants employer visibility consent.
7. The profile becomes discoverable to approved employers.

### Professional extension fields

- professional headshot;
- résumé;
- LinkedIn;
- Handshake;
- professional summary;
- skills;
- career interests;
- employer visibility consent.

The normal social avatar remains unchanged. The professional headshot is used only in employer-facing views.

## 4. Opportunities

The mobile app keeps one Opportunities system:

- **All**
- **Campus**
- **Blueprint Bond** — visible only to Presidential Scholars

Every opportunity shows a source badge such as **Campus Opportunity** or **Employer Partner**.

Employer submissions use a separate review workflow and publish into the existing Campus Post opportunity model only after approval.

## 5. Administration

Use the existing admin portal:

- Super Admin
- School Admin
- Honors Admin
- Content Admin
- Read-only Auditor

Honors Admin access includes:

- verify Presidential Scholars;
- manage professional-profile status;
- approve employer organizations;
- review employer opportunities;
- manage Honors resources;
- view approved program analytics.

Admin accounts are created through invitations. Every person creates their own password through Supabase Auth and enrolls in MFA.

## 6. Recommended models

- `Program`
- `ProgramMembership`
- `ScholarProfessionalProfile`
- `ScholarAcademicRecord`
- `StudentDisclosureConsent`
- `EmployerOrganization`
- `EmployerAccount`
- `EmployerOpportunitySubmission`
- `OpportunityEligibility`
- `EmployerProfileView`
- `AdminMembership` / `AdminPermission`

Reuse:

- `User`
- `Profile`
- `CampusPost`
- `CampusResource`
- `Notification`
- `DeviceToken`
- `AdminAuditLog`

## 7. Implementation phases

1. Program and membership foundation.
2. Scholar mobile experience and professional profile.
3. Honors module in the existing admin portal.
4. Employer organization registration and approval.
5. Employer opportunity submission and existing-feed publication.
6. Approved employer scholar discovery.
7. Controlled enhancements after governance and stability review.

## 8. Security rules

- default-deny access to professional and academic data;
- backend authorization, not UI-only hiding;
- explicit consent;
- private file storage and signed URLs;
- MFA for administrators;
- individual accounts;
- immutable audit events;
- immediate revocation;
- no employer access to social profiles, activities, or messages;
- no GPA disclosure before policy and legal review.

## 9. First-release exclusions

- no separate student app;
- no separate Honors admin app;
- no shared admin password;
- no student self-verification;
- no unreviewed employers;
- no automatic opportunity publishing;
- no employer-to-student chat;
- no public GPA;
- no full applicant-tracking system;
- no transcript ingestion.

## 10. Acceptance summary

The release is complete when a school-authorized Honors administrator can verify a scholar, the scholar can complete a restricted professional extension, an approved employer can submit a reviewed opportunity, eligible scholars can see it in the existing opportunity experience, and every privileged action is individually attributable and audited.

## 11. Implementation checklist (by phase)

### 11.0 Verified against the current codebase (2026-07-31)

Before trusting any "reuse the existing X" line below, here is what was actually confirmed present
vs. absent by reading the code, not assumed from the spec:

**Already in place — safe to reuse as-is:**
- `require_admin_aal2` (`app/dependencies.py`) already enforces `role == 'admin'` **and** Supabase
  MFA (aal2) on every admin route. MFA-for-admins is real today, not aspirational.
- `record_audit()` (`app/shared/audit.py`) writing to `AdminAuditLog` is already wired into
  `campus_hub/publishing.py`, `admin/campus_positions.py`, `admin/campus_resources.py`, and
  `admin/service.py`. Every new privileged action should call this same helper — don't invent a
  second audit path.
- `UserRateLimit` (`app/shared/rate_limit.py`) is an existing per-user rate-limit dependency used
  elsewhere — reuse it on résumé/headshot upload and employer submission endpoints rather than
  writing new throttling.
- `app/shared/supabase_admin.py` already holds a guarded, failure-isolated service-role Supabase
  client (`delete_auth_user`) — the right place to add an `invite_auth_user(email)` function,
  following its exact pattern (return `bool`/`None` on failure, log, never raise).
- `PushSender`/`DeviceToken` (notifications feature) are real and already used for push on publish —
  fine to reuse for the "scholar verified" notification.

**Not in place — this is new build, not a reuse-and-extend:**
- **No scoped admin permission system exists.** `User.role` is a single flat string
  (`student`/`staff`/`admin`); there is no `AdminMembership`/`AdminPermission` table, no Super/School/
  Content/Honors/Auditor distinction anywhere in code. §6/§5's role list has to be built from
  scratch, not "extended."
- **No admin invitation flow exists.** The only way an admin account is created today is
  `backend/scripts/create_admin.py` — a manual CLI script that sets a legacy `password_hash`
  directly and never touches Supabase Auth or MFA enrollment. It directly contradicts §5's "created
  through invitations… creates their own password through Supabase Auth and enrolls in MFA." This
  script cannot be the mechanism for Honors Admin (or any scoped admin) accounts — a real
  invite-by-email flow (Supabase Auth `auth.admin.invite_user_by_email`, wrapped the same
  failure-isolated way as `delete_auth_user`) has to be built in Phase 3, and the legacy script
  either retired or clearly scoped to "break-glass only."
- **No private-bucket / signed-URL storage pattern exists.** `SupabaseStorageService`
  (`app/shared/storage.py`) only ever calls `get_public_url` — every existing upload (avatar, group
  image, activity banner) is public-by-design. There is no precedent in this codebase for a private
  bucket or a signed URL. Résumé/headshot storage in Phase 2 is genuinely new infrastructure, not a
  copy-paste of an existing helper — build it following the same guarded-client shape
  (`if self.client is None: raise/return`) but as a new method, not by relaxing the existing public
  one.
- **No employer identity type exists.** Auth today is one `User` table with `role` in
  `student`/`staff`/`admin`, all Supabase-Auth-backed. Whether `EmployerAccount` becomes
  `User.role = 'employer'` (reusing the existing auth plumbing) or a fully separate identity/table
  is an **open design decision** — resolve it explicitly before Phase 4 starts, don't default into
  it mid-implementation.

### Cross-cutting bar for every phase below — not a one-time step, a standing requirement

- [ ] Feature-first structure honored: each new domain gets its own `app/features/<domain>/{router,service,schema}.py`; routers thin, logic in `service.py`; no feature imports another feature's `service.py` (shared DTOs go in `app/shared/`).
- [ ] File-length discipline: split before the 400-line soft target where it makes sense, never cross the 600-line hard cap.
- [ ] Backend authorization is default-deny and enforced server-side on every new endpoint — never rely on the UI hiding a control.
- [ ] Every privileged/admin action (verify, approve, reject, revoke, invite) calls the existing `record_audit()` (`app.shared.audit`) — don't build a parallel logging path.
- [ ] Error-handling contract, matching existing conventions in this codebase:
  - hard validation failures (bad file type/size, missing required field, duplicate membership) → typed `HTTPException` with a clear `detail`, same shape as `sanitize_avatar`'s (`app/shared/image_processing.py`) 422s;
  - permission failures → `403` via a dependency (like `require_admin_aal2`), never a silent empty response;
  - best-effort side effects (push notification, audit-log-adjacent cleanup) → guarded, logged, never block or roll back the primary action, same shape as `push_published_post`/`delete_auth_user`'s "never raises" pattern;
  - unconfigured infrastructure (storage bucket, Supabase admin client) → `503`, same shape as `SupabaseStorageService`'s `client is None` check — never a raw 500.
- [ ] OpenAPI snapshot regenerated only for the additive changes actually made that phase; `pytest` + `ruff` (backend) and `flutter analyze` + tests (mobile) green before a phase is marked done.
- [ ] Functions stay small, single-purpose, and named for intent — no premature abstraction, no dead scaffolding for future phases.

### Phase 1 — Program and membership foundation ✅ (2026-07-31)
- [x] `Program` model (slug, name, description, active flag).
- [x] `ProgramMembership` model (user_id FK, program_id FK, status: active/revoked, verified_by admin id, verified_at, revoked_at). Unique constraint on (user_id, program_id) — verifying twice on an active membership is a 409; a revoke-then-reverify reactivates the same row instead of inserting a duplicate.
- [x] Alembic migration (`5f045e1e9b50`), seeds the single `presidential_scholars` row; models registered in `app/models.py`'s single metadata.
- [x] New `app/features/programs/` slice (student-facing `GET /programs/me` — active memberships only) + `app/features/admin/programs.py` (verify/revoke/list, mirroring the existing `admin/campus_positions.py` shape) wired into `admin/router.py` under `/admin/programs/{slug}/members`.
- [x] Error handling: `409` on verifying an already-active membership or revoking an already-revoked one; `404` on unknown email or a membership that doesn't exist; `422` if the target account isn't a student. Permission is `403` via the existing `require_admin_aal2` (flat admin + MFA) — **deliberately not Honors-scoped yet**, since that scope doesn't exist until Phase 3 lands (documented dependency, not an oversight).
- [x] Notification (+ push — added `program_membership_verified` to `PUSHABLE_NOTIFICATION_TYPES` and `_notification_copy`) sent to the student on verification via the same `emit_notification` used by connections/groups, called from the router after the service call (matching that exact convention) — best-effort, never fails the verify request.
- [x] Audit log entry on every verify/revoke via `record_audit()`.
- [x] Tests (`tests/db/test_admin_programs.py`, 12 tests): verify/revoke/reactivate/list, duplicate-verify 409, revoke-not-found 404, non-student 422, unique-constraint-at-DB-level, student-only-sees-active-memberships; plus updated the existing `PUSHABLE_NOTIFICATION_TYPES` lock test and `_notification_copy` parametrized test. Snapshot regenerated (additive-only, 416 insertions / 0 deletions). Full suite: 299 passed, ruff clean, line limits clean (no new file over the soft target).

### Phase 2 — Scholar mobile experience and professional profile ✅ (2026-07-31)
- [x] `ScholarProfessionalProfile` model: `headshot_path`/`resume_path` (private-bucket object paths, never public URLs), LinkedIn, Handshake, summary, `skills`/`career_interests` (Postgres arrays — free-text, not a controlled vocabulary), `employer_visibility_consent` + `consent_given_at` + `consent_version` (this **is** the `StudentDisclosureConsent` concept, captured as fields rather than a separate table — a bump to `CURRENT_CONSENT_VERSION` in `service.py` can force re-consent later). Migration `7675b2828747`. Fully separate from `Profile`/social avatar.
- [x] **Résumé and headshot storage** — new private bucket (`SUPABASE_SCHOLAR_BUCKET`, distinct from the public `SUPABASE_PROFILE_BUCKET`) added to `app/shared/storage.py`. Uploads return only the object path; every read goes through `scholar_signed_url` (short-lived, generated fresh each call — nothing cached client-side). Headshot reuses `sanitize_avatar` (real-image decode, EXIF/GPS strip, downscale). Résumé validated by **real file-signature sniffing** (PDF magic bytes / a real ZIP containing `word/document.xml` for `.docx`) — never the client's content-type header. **Refinement from the original checklist wording**: consent revocation does **not** delete files (a student's résumé is theirs to keep regardless of who can see it) — only account deletion does, wired into `app/features/account/service.py` (`storage_service.delete_scholar_file`, best-effort, matches the existing avatar-cleanup shape).
- [x] Rate-limited with a new `scholar_upload_limit` (`app/shared/rate_limit.py`, same `UserRateLimit` shape as `avatar_upload_limit`).
- [x] Backend endpoints (`app/features/scholars/`: `GET/PATCH /scholars/me`, `POST /scholars/me/consent`, `POST /scholars/me/headshot`, `POST /scholars/me/resume`, `GET /scholars/me/headshot-url`, `GET /scholars/me/resume-url`) gated behind "is verified scholar" **enforced in `service.py`'s `_get_or_create` choke point** (every public function routes through it) — not just the router's `require_verified_scholar` dependency, so a future direct-service caller can't bypass it. Authorization is checked *before* any file validation work.
- [x] Error handling, matching real codebase precedent rather than the checklist's original blanket "422": `400` for a file that fails real-content validation (not a decodable image / not a real PDF or docx — mirrors `sanitize_avatar`'s own 400s), `413` for oversized (`HTTP_413_CONTENT_TOO_LARGE`, matching the avatar-upload precedent), `503` if the storage client is unconfigured, `403` for a non-scholar on every endpoint.
- [x] Mobile: `BlueprintBondCard` (`lib/features/scholars/widgets/`) in both Profile and Campus Hub, backed by a new `lib/features/programs/providers/programs_provider.dart` (`GET /programs/me`) — renders nothing unless the user has an active `presidential_scholars` membership.
- [x] Mobile: `BlueprintBondScreen` (`lib/features/scholars/screens/`) — LinkedIn/Handshake/summary fields, skills/career-interest tag inputs, headshot upload (`image_picker`, already a dependency) and résumé upload (added `file_picker` as a new pub dependency — the standard Flutter package for picking an arbitrary file type; none of the existing deps cover PDF/docx selection), consent switch. Upload/save failures surface a real snackbar error, not a silent no-op.
- [x] Tests: 18 in `tests/db/test_scholars.py` (403 on every endpoint for a non-scholar including via a loop over every public function, membership active/revoked, get-or-create, field update + skill-length validation, consent stamps timestamp/version without touching files, wrong-type/oversized upload rejected before storage is ever touched, 503 when storage unconfigured, successful upload with `storage_service` mocked) + 1 in `test_account_deletion.py` (profile row removed on deletion) + 4 mobile widget tests (`blueprint_bond_test.dart`). Full suite: backend 318 passed/ruff clean/snapshot additive-only; mobile 166 passed/analyze clean; line limits clean.

### Phase 3 — Honors module in the existing admin portal

**Decided (2026-07-31), not open anymore:**
- **Bootstrap:** the very first admin — the platform builder, Super Admin — is created once by
  running a script directly against whichever Supabase project the backend is actually pointed at
  (the one real database; there is no separate "script DB" vs "app DB" — it's the same
  `DATABASE_URL`/Supabase project either way, dev or prod). `backend/scripts/create_admin.py` is
  rewritten (not retired) for this: instead of its current legacy `password_hash` write, it must
  create the user through **Supabase Auth** (e.g. `auth.admin.create_user` or an invite-to-self) so
  the builder gets a real Supabase-Auth identity and enrolls in MFA like everyone else, seeded with
  the Super Admin scope. This is the *only* admin ever created outside the in-app invite flow.
- **Invite matrix**, enforced server-side wherever an invite is issued (not just in the UI):
  | Inviter role | Can invite |
  |---|---|
  | Super Admin | anyone — School Admin, Honors Admin, Content Admin, Auditor, another Super Admin |
  | School Admin | Honors Admin, Content Admin, Auditor |
  | Honors Admin / Content Admin / Auditor | nobody |

  A School Admin attempting to invite a School Admin or Super Admin gets a `403`, not a silently
  downgraded invite. This rule table should be one small, explicit function (e.g.
  `can_invite(inviter_role, target_role) -> bool`) that both the endpoint and its tests exercise
  directly — not scattered `if` checks.

**Checklist:**
- [ ] Build the scoped permission system (`AdminMembership`/`AdminPermission` or equivalent) from scratch — today `User.role` is a single flat string with no scoping (see §11.0). Super/School/Content/Honors Admin and the read-only Auditor all need to be real, distinct scopes, not just naming conventions.
- [ ] Rewrite `backend/scripts/create_admin.py` as the one-time Super Admin bootstrap per the decision above (Supabase Auth, not legacy password hash), and document that it is never run again after the first Super Admin exists.
- [ ] Build the admin invitation flow: extend `app/shared/supabase_admin.py` with an `invite_auth_user(email)` function using Supabase Auth's `auth.admin.invite_user_by_email`, following the exact guarded/failure-isolated shape of the existing `delete_auth_user`. The invite endpoint takes email + target role, enforces the invite matrix above, then creates a `pending`/unconfirmed local admin membership row tied to the Supabase invite. The invitee sets their own password and enrolls in MFA through Supabase Auth (never a shared or admin-set password).
- [ ] Admin UI: an "Invite admin" screen (email + role picker, filtered to only the roles the current admin is allowed to grant), an admin roster list, and — for Honors specifically — verify scholars from a roster, manage professional-profile status, manage Honors resources, view approved program analytics (aggregate only).
- [ ] Endpoints scoped by role, reusing `require_admin_aal2`'s MFA enforcement as the base, layered with the new scope + invite-matrix checks — no new parallel MFA/auth system, just the missing scoping on top of what's already enforced.
- [ ] Error handling: `403` (not 401) for a correctly-authenticated admin missing the required scope, or attempting an invite outside their row in the matrix; invite endpoint returns a clear error (not a silent no-op) if the Supabase Auth invite call fails, and never leaves a half-created local admin row with no matching auth-side invite (wrap in a transaction / reconcile on failure).
- [ ] Tests: the invite matrix table itself (Super Admin → anyone; School Admin → Honors/Content/Auditor only, rejected for School/Super; Honors/Content/Auditor → nobody); an invited admin cannot act until they've completed signup + MFA; every invite/verify/approve action produces an audit entry via `record_audit()`.

### Phase 4 — Employer organization registration and approval
- [ ] Resolve the open design decision from §11.0 first: employer identity as `User.role = 'employer'` (reuse existing Supabase-Auth-backed plumbing) vs. a fully separate identity — document the choice before modeling `EmployerAccount`.
- [ ] `EmployerOrganization` model (name, status: pending/approved/rejected).
- [ ] `EmployerAccount` model per the resolved identity decision above.
- [ ] Employer registration flow leaves the org/account `pending` with zero access until an Honors Admin approves.
- [ ] Honors Admin approval queue (approve/reject), audited via `record_audit()`.
- [ ] Error handling: a pending/rejected employer hitting any employer-only endpoint gets a clear `403` (`"Your organization is pending approval"` / `"…was not approved"`), not a generic auth failure — the employer portal needs to render that message meaningfully.
- [ ] Tests: a pending employer cannot submit opportunities, browse scholars, or otherwise touch any scholar data; a rejected employer stays rejected (no re-registration loophole that resets status to pending without Honors Admin action).

### Phase 5 — Employer opportunity submission and existing-feed publication
- [ ] `EmployerOpportunitySubmission` model (org_id, content, status: pending/approved/rejected, reviewer_id, reviewed_at).
- [ ] `OpportunityEligibility` model/field tying an approved submission to the Blueprint Bond-only visibility filter.
- [ ] Review workflow: Honors Admin approves/rejects a submission, audited via `record_audit()`.
- [ ] Rate-limit submission creation with `UserRateLimit` (mirrors the résumé-upload reuse in Phase 2).
- [ ] On approval, publish through the **existing** `campus_hub` publishing path into `CampusPost(kind=opportunity)` — no parallel feed/table for content.
- [ ] Error handling: rejecting a submission requires a reason recorded (not just a boolean flip) so the employer portal can show *why*; approval failing partway (e.g. the `CampusPost` publish step errors) must not leave the submission marked `approved` while nothing actually published — wrap in a transaction.
- [ ] Mobile: Opportunities tab gains the **Blueprint Bond** filter (visible only to verified scholars); every card shows a source badge (**Campus Opportunity** vs **Employer Partner**).
- [ ] Tests: an unapproved submission never reaches the feed; the eligibility filter is enforced server-side (a non-scholar hitting the endpoint directly still gets nothing), not just hidden client-side; a publish-step failure leaves the submission in a consistent, retryable state.

### Phase 6 — Approved employer scholar discovery
- [ ] `EmployerProfileView` model recording which employer viewed which scholar profile (audit trail).
- [ ] Discovery endpoint for approved employers surfaces only scholars with active `ProgramMembership` **and** current `employer_visibility_consent = true`.
- [ ] Employer-facing profile view exposes only the professional extension fields — never the social profile, activities, groups, or messages. Verify this at the serializer level (a dedicated `EmployerScholarView` DTO, not a filtered `ProfilePublic`) so a future field added to the social profile can't leak through by accident.
- [ ] Error handling: an employer requesting a scholar who has revoked consent (or been unverified) gets a `404`, not a stale cached profile.
- [ ] Tests: revoking consent immediately removes a scholar from employer discovery (no caching/staleness); no social-profile field ever leaks into the employer view/serializer; the employer-view DTO is asserted field-by-field against an allowlist, not just "doesn't crash."

### Phase 7 — Controlled enhancements after governance and stability review
- [ ] Explicit legal/policy sign-off checklist item before touching anything on the exclusions list (GPA disclosure, transcript ingestion, employer-student chat, full ATS).
- [ ] Security/load review before enabling any further feature.
- [ ] Nothing from §9 (First-release exclusions) is built ahead of its own governance approval, even if convenient to bundle in.

### Acceptance gate (ties back to §10)
- [ ] An Honors administrator can verify a scholar end-to-end.
- [ ] A verified scholar can complete and save the professional extension, résumé included, stored and served securely.
- [ ] An approved employer can submit an opportunity that a Honors Admin reviews and publishes.
- [ ] Eligible scholars see it through the existing Opportunities experience, correctly filtered and badged.
- [ ] Every privileged action across all phases is individually attributable and present in the audit log.
