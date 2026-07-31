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
- **No employer identity type exists** *(resolved in Phase 4 — see §11 Phase 4)*: `EmployerAccount`
  is a fully separate identity/table, never `User.role = 'employer'`, specifically to keep every
  existing student/staff endpoint default-deny for employers without re-auditing any of them.

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

**Checklist:** ✅ (2026-07-31)
- [x] `AdminMembership` model (migration `fca355e2d5c0`) — one row per (user, role); `super_admin`/`school_admin`/`honors_admin`/`content_admin`/`auditor` are real, distinct scopes. `User.role == 'admin'` (+ `require_admin_aal2`'s MFA check) stays the unchanged base gate; this layers *which* scopes an account holds on top.
- [x] `backend/scripts/create_admin.py` rewritten: refuses to run if a `super_admin` already exists (guards against exactly the "run it twice" mistake), otherwise invites the builder through the same `invite_auth_user` Supabase path the in-app flow uses, seeds `AdminMembership(role='super_admin')`. No more legacy `password_hash` write.
- [x] `invite_auth_user(email)` added to `app/shared/supabase_admin.py`, same guarded/failure-isolated shape as `delete_auth_user` — but callers must treat `None` as a real failure (503), not swallow it, since a "ghost" invite with no matching Supabase identity is a genuine bug, not a soft miss.
- [x] **Refinement from the original checklist wording**: no separate `pending`/unconfirmed `AdminMembership` status was built. Reasoning: `require_admin_aal2`'s aal2 check already means an invited admin cannot act on anything until they've actually completed Supabase signup + MFA, regardless of what the local row says — adding a `pending` status that would need its own transition trigger (there's no webhook/callback path from Supabase back into this backend) would either need invasive changes to the heavily-shared `require_admin_aal2` dependency or produce a status that never auto-updates and actively misleads a roster viewer. The real security property ("can't act until signup+MFA") holds either way.
- [x] `can_invite(inviter_role, target_role) -> bool` (`app/features/admin/admins.py`) — the one explicit matrix function, exercised directly by 14 parametrized tests. Reused for both invite **and** revoke authorization (a School Admin revoking a Super Admin would be a real bug otherwise — this wasn't explicitly asked for in the checklist wording but follows directly from the same security intent).
- [x] `require_admin_scope(*roles)` dependency factory layers on top of `require_admin_aal2` (never a parallel MFA system). Phase 1's Program-membership verify/revoke/list endpoints — deliberately left on the flat gate at the time — are now retrofitted to `require_admin_scope('honors_admin')`, paying down that documented dependency.
- [x] Endpoints: `POST /admin/admins/invite`, `GET /admin/admins` (roster, any admin — read-only), `POST /admin/admins/{id}/revoke`, `GET /admin/admins/me/scopes` (lets the UI gate its own nav).
- [x] Error handling: invite calls `invite_auth_user` **before** creating/mutating any local row, so a failed Supabase call (`503`) never leaves a half-created admin; `403` for a scope/matrix violation; `409` for an already-active duplicate role; `404` for revoking a membership that doesn't exist.
- [x] Admin portal (Next.js, `admin/`): new **Admins** page (roster + invite form, gated to the roles the current admin may actually grant) and **Scholars** page (Honors-only — verify/revoke Presidential Scholars against Phase 1's endpoints, active/revoked tabs). Nav in `(dashboard)/layout.tsx` now fetches `/admin/admins/me/scopes` and shows **Scholars** only to Honors Admins.
- [x] **Deferred, not built this pass** — "manage professional-profile status," "Honors resources," and "program analytics" from the original Admin UI prose: none of these have a concrete spec (no `status` field exists on `ScholarProfessionalProfile`, no `HonorsResource` model, no defined analytics metrics anywhere in this document). Building any of them now would mean inventing requirements rather than implementing them. Flagging explicitly rather than silently skipping — needs a real spec before a future pass.
- [x] Tests: `can_invite` matrix (14 cases) + `get_admin_scopes` + invite (new user, existing user, duplicate-409, reactivate-after-revoke, unknown-role-422, audit entry, failure leaves nothing half-created) + revoke (audit entry, cross-scope 403, not-found-404, already-revoked-409) + `require_admin_scope` dependency (31 tests total, `tests/db/test_admin_admins.py`). Full suite: backend 349 passed/ruff clean/snapshot additive-only; admin portal builds and lints cleanly.

### Phase 4 — Employer organization registration and approval ✅ (2026-07-31)
- [x] **Identity decision resolved**: `EmployerAccount` is a **fully separate identity, never a `User` row** (not `User.role='employer'`). Reasoning: reusing `User` would mean every one of the ~15 existing student/staff endpoints implicitly trusts anyone with a valid Supabase session unless individually re-audited to exclude the new role — a large, risky blast radius for a security-sensitive external-actor boundary. A fully separate identity means employers structurally can't resolve against `get_current_user`/`require_verified_student`/etc. at all — default-deny holds automatically, satisfying §8's "no employer access to social profiles, activities, or messages" by construction rather than by remembering to check a role everywhere.
- [x] `EmployerOrganization` model (name, status: pending/approved/rejected, review_note, reviewed_by/at) + `EmployerAccount` (organization_id, email — unique, the login identity — display_name, `auth_user_id` nullable). Migration `60d27337c593`.
- [x] Employer registration (`POST /employers/register`, public/unauthenticated — `app/features/employers/`) leaves the org **and** account pending with zero access: `EmployerAccount.auth_user_id` stays NULL until approved, so a pending employer has no Supabase identity at all, not just a gated one — the strongest form of "zero access."
- [x] Honors Admin approval queue (`app/features/admin/employers.py`, wired into `admin/router.py` under `require_admin_scope('honors_admin')`) — approval reuses the exact same `invite_auth_user` path Phase 3 built for admins: approving an employer sends them a real Supabase invite email (never an admin-set password). Rejection requires nothing beyond marking the org `rejected` (no auth ever granted).
- [x] Error handling: invite-side failure on approval leaves the org `pending` (not falsely marked `approved` with no matching Supabase identity) — same "auth call before any local mutation" pattern as Phase 3's admin invite; `409` for approving/rejecting a non-pending org; `404` for an unknown org id.
- [x] Tests (14, `tests/db/test_employers.py` + `tests/db/test_admin_employers.py`): duplicate-email registration blocked whether the existing org is pending/approved/rejected (**the explicit re-registration-loophole test** — confirms a second registration attempt never resets a rejected org back to pending), approve sets status + invites + audits, approve failure leaves org pending, reject sets status + note + audits, list filters by status, org-not-found 404.
- [x] Admin portal: new **Employers** page (Honors-only nav item) — pending/approved/rejected tabs, approve/reject with an optional rejection note.
- [x] **Not built this pass, by design**: no employer-facing registration *web page* — only the backend endpoint. Building a full separate employer-facing portal (registration UI, login, and eventually the Phase 5/6 dashboard) is a substantial standalone frontend project the Phase 4 checklist's own bullets don't ask for (they describe backend/admin-approval behavior); flagging this explicitly as a distinct future frontend deliverable rather than silently leaving it undiscussed.
- [x] **Prerequisite paid down mid-phase**: `app/models.py` was at 595/600 lines — Phase 4's new models would have pushed it over the hard cap and failed CI. Split into `app/models/` (a package: `core.py`, `social.py`, `messaging.py`, `groups.py`, `activities.py`, `notifications.py`, `campus.py`, `programs.py`, `admin.py`, `employers.py`, all sharing one `Base`/metadata via `__init__.py` re-exports — satisfies CLAUDE.md's "one metadata," not literally "one file"). Zero of the 78 files that `from app.models import X` needed to change. Proven behavior-identical: full suite passed before and after with the same count, and the OpenAPI snapshot was byte-for-byte unchanged.
- [x] Full suite: backend 363 passed, ruff clean, snapshot additive-only; admin portal builds + lints cleanly.
- [x] **Heads up for Phase 5/6**: `admin/router.py` is now at 447 lines (soft-target warning, not a hard-cap risk yet) — growing the same way `models.py` did each phase. Worth splitting into per-domain sub-routers before it gets as tight as `models.py` was.

### Phase 5 — Employer opportunity submission and existing-feed publication ✅ (2026-07-31)
- [x] `EmployerOpportunitySubmission` model (organization_id, submitted_by_id, title/description/category/external_url, status: pending/approved/rejected, review_note, reviewed_by/at, `published_post_id`). Migration `538c95a4732b`.
- [x] **`OpportunityEligibility` implemented as a field, not a model**: `CampusPost.eligible_program_slug` (nullable `String`, new column on the existing table) — when set, only active members of that Program may see the post, layered on top of the existing `audience` check via a correlated `EXISTS` in `published_posts_stmt`/`is_post_visible` (both now async, since eligibility requires a Program-membership lookup). NULL for every ordinary post — zero behavior/perf change on the common path. A shared `is_active_program_member` helper (`app/shared/programs.py`) backs both this and the scholars feature's own gate (also refactored to use it, removing a near-duplicate query).
- [x] `CampusPost.source` ('campus' default | 'employer') added alongside — drives the client's source badge without an extra join at read time.
- [x] Review workflow (`app/features/admin/employers.py`, Honors-only): approve publishes through the **existing** `campus_hub.publishing.create_post`/`publish_post` path — no parallel content table. Reject requires a reason (enforced at both the request schema `min_length=1` **and** the service layer against a whitespace-only string slipping through).
- [x] New `EmployerRateLimit` (`app/features/employers/rate_limit.py`) — mirrors `UserRateLimit`'s shape but keyed on `EmployerAccount.id` (employers aren't `User` rows, so the existing limiter couldn't be reused directly; it wraps the same generic `RateLimiter` bucket).
- [x] New employer-facing auth (`app/features/employers/auth.py`, `require_approved_employer`) — a **second, independent JWT→identity resolution path** alongside `app/dependencies.py`'s student/staff one, exactly because `EmployerAccount` is deliberately not a `User` (§11.0/Phase 4 decision). Same Supabase token, different local identity table. Returns the exact `"Your organization is pending approval"` / `"…was not approved"` messages the checklist specified.
- [x] **Real bug caught by the transaction-safety test, then fixed**: the first cut of `approve_submission` only recorded `submission.published_post_id` *after* the publish step succeeded — meaning a failure between "draft created" and "published" would, on retry, create a **second** duplicate draft (the idempotency guard never engaged, since the guard field was never actually set before the failure point). Fixed by recording `published_post_id` immediately once the draft exists and commits, *before* attempting to publish it, so a retry always finds and reuses the same draft. `tests/db/test_admin_employer_opportunities.py::test_retry_after_partial_publish_failure_is_idempotent` failed against the original code and passes against the fix — this is exactly the kind of thing "wrap in a transaction" was trying to prevent, achieved here via idempotent retry instead (see below for why not literal DB atomicity).
- [x] **Why idempotent retry instead of a literal DB transaction**: `campus_hub.publishing.create_post`/`publish_post` each `commit()` internally (pre-existing, unrelated-feature code) — they cannot be composed into one outer transaction without touching that shared Phase-1-era code. The idempotent-retry design achieves the same real guarantee (a retry after partial failure never double-publishes) without that broader, riskier change.
- [x] Mobile: Opportunities screen gains a source-tab row (**All / Campus / Blueprint Bond** — the last one only rendered for a verified scholar, via `isVerifiedScholarProvider`) independent of the existing category chips; every card shows a **Campus Opportunity** / **Employer Partner** badge. This is a client-side filter over posts the user already legitimately received — the server has already fully enforced eligibility by the time the list arrives.
- [x] Tests (21 total across `tests/db/test_employer_auth.py`, `test_employer_opportunities.py`, `test_admin_employer_opportunities.py`): pending/rejected/approved employer auth resolution and messages; submission creation + org-scoping; reject requires a real (non-whitespace) reason; approve publishes with correct `kind`/`source`/`eligible_program_slug`; audit entries; the retry/idempotency test that caught the bug above; an unapproved submission never reaches `published_posts_stmt`; a non-scholar gets nothing for an eligible post via both `is_post_visible` and the list statement directly (not just hidden client-side); a verified scholar does see it.
- [x] Full suite: backend 384 passed, ruff clean, snapshot additive-only; mobile 166 passed, analyze clean, line limits clean (no file crossed the 600 hard cap; `admin/router.py` now at 489 — see the standing note below).

### Phase 6 — Approved employer scholar discovery ✅ (2026-07-31)
- [x] `EmployerProfileView` model (migration `5c9a44153726`) — logged once per detail fetch (`GET /employers/scholars/{user_id}`), not on list/browse and not separately for the headshot/résumé signed-URL calls that follow the same view (would be noisy over-counting for the same act of viewing).
- [x] Discovery (`app/features/employers/discovery.py`, `GET /employers/scholars`) — a single shared query (`_eligible_scholars_stmt`) joins active `presidential_scholars` membership **and** `employer_visibility_consent = true`; both the list and the single-scholar lookup re-run this same query from scratch on every call — nothing is cached or synced from a prior read, so revocation takes effect on the very next request with zero extra plumbing.
- [x] `EmployerScholarView` (`app/features/employers/schema.py`) hand-built field-by-field in a dedicated router helper (`_scholar_view`) — never `ProfilePublic.model_validate(...)`, never `**profile.__dict__`. Exactly 9 fields: `user_id`, `display_name` (the one non-"professional" field — baseline identification, not social/behavioral data), `linkedin_url`, `handshake_url`, `summary`, `skills`, `career_interests`, `has_headshot`, `has_resume`. A future field added anywhere on `Profile`/`User` cannot appear here without someone deliberately editing this helper.
- [x] Error handling: `get_eligible_scholar_or_404` (and the headshot/résumé signed-URL functions, which call it first) — a scholar who revoked consent, or lost/never had active membership, or never existed, all collapse to the same `404`, not a stale cached profile or a different error shape that would leak which case it was.
- [x] Tests (14, `tests/db/test_employer_discovery.py`): list excludes non-consenting/plain-student/revoked-membership scholars; get-or-404 covers eligible/non-consenting/unknown-user; **revoking consent or membership after a successful fetch immediately 404s the very next call** (the literal no-caching/no-staleness test); `record_view` writes an audit row; signed-URL 404 without a file, success with storage mocked, and 404 for a non-consenting scholar even with a headshot on file (consent blocks signed-URL issuance too, not just the profile view); the field-allowlist test asserts `EmployerScholarView.model_fields.keys()` equals the exact 9-field set and is disjoint from a forbidden set (bio, major, class_year, avatar_url, interests, pronouns, country_state, campus).
- [x] No mobile work this phase — Phase 6's own checklist has no "Mobile:" bullet, and (per the Phase 4 decision) no employer-facing web portal exists yet to build this UI into; that portal remains a distinct, unscoped frontend project.
- [x] Full suite: backend 398 passed, ruff clean, snapshot additive-only. `admin/router.py` unchanged at 489/600 this phase (Phase 6 is entirely employer-facing, no new admin endpoints).

**This closes the content phases of the spec.** Phase 7 is governance/stability review (legal sign-off, security/load review before touching anything on the §9 exclusions list) — not something to implement in code.

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
