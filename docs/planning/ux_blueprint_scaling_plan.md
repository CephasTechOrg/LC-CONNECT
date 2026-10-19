# Implementation Plan — UX, Blueprint Bond, Messaging, Scaling

**Status:** Sprints 1–4 (Waves A–E) implemented — login hero swap waits on a new asset  

**Scope:** Connect/Discovery polish, Campus Hub UX, Blueprint Bond professional profile + Honors approval, message reactions fix, login asset, scaling readiness for ≤ ~1,500 users  
**Source of truth for architecture:** `architecture_review/` (this plan does not change locked ADRs)

---

## Goals

1. Make Connect cards and Blueprint Bond feel professional and consistent.
2. Gate employer-visible scholar profiles behind Honors admin approval.
3. Fix mutual message reactions UX.
4. Document and harden scaling/reliability for campus scale (no premature Redis caching).
5. Light Campus Hub / login polish.

---

## Priority order (execution waves)

| Wave | Theme | Why first |
|------|--------|-----------|
| **A** | Connect UX + Blueprint CTA + reactions | High user-visible pain; mostly Flutter; low schema risk |
| **B** | Blueprint Bond fields + professional UI | Product depth for scholars |
| **C** | Honors admin approval before employer portal | Security/product gate; needs migration + admin UI |
| **D** | Campus Hub polish + login image | Visual; login image when asset ready |
| **E** | Scaling / rate limits / concurrency hardening | Ops readiness; mostly docs + small code fixes |

Do **not** start Wave C until Wave B field shapes are agreed (approval reviews the same payload employers will see).

---

## Wave A — Connect UX, Blueprint prompt, reactions

### A1. Connect page header (remove redundant chrome)

**Problem:** Bottom nav already says “Connect”; shell title + subtitle (“Students & study partners…”) + Students / Study Partners tabs stack the same idea above filters.

**Work**
- [x] `mobile/lib/features/discovery/screens/discovery_screen.dart` — drop or drastically shorten `AppShellHeader` subtitle; prefer compact actions row (requests + bell) without repeating “study partners”.
- [x] Resolve **tab vs filter overlap**: Study Partners tab forces `study_partner` while chips also filter — keep **one** primary control (recommend: keep filter chips + search; simplify or remove the Students/Study Partners segment if redundant).
- [x] Align filter chip labels with backend lookups (`backend/app/seed.py` / lookups API); remove retired `open_connection` if still in UI.

**Done when:** Opening Connect shows search + filters + cards without a wrapping marketing subtitle; filter labels match profile “looking for” names.

### A2. Smaller, consistent discovery cards

**Files:** `discovery_student_card.dart`, `discovery_card_parts.dart`, optionally shared chip widget with `profile_looking_for.dart`.

**Work**
- [x] Reduce avatar (~70 → ~52–56) and vertical padding so more cards fit per screen without feeling cramped.
- [x] Card shows **summary only**: name, class/major, **≤2 interests** (+N), **≤2 languages** (+N). Full interests / looking-for / bio on public profile tap.
- [x] Looking-for: show **once** (no top “Wants …” badge + duplicate chip row). Use same labels/icons as profile (“Friendship”, “Study partner”, …) — not “Wants study partner”.
- [x] Remove always-on “Livingstone College” row (adds noise for an all-campus app).
- [x] CTAs: keep primary Connect; show Study Together only when relevant to their looking-for (optional polish).
- [ ] Shared display-name helper: prefer `display_name`; never show raw email local-part as the hero name on cards if profile name is set during onboarding — align Connect fallback with Campus Hub (`Student` vs email-derived greeting). *(deferred — cards already use `display_name` / `Student`; hub email greeting left as-is)*

**Done when:** Cards are visually consistent height/density; clicking through still shows full profile.

### A3. Blueprint Bond hub prompt (copy + layout)

**File:** `mobile/lib/features/scholars/widgets/blueprint_bond_card.dart` (`BlueprintBondStyle.prompt`)

**Work**
- [x] Title only: **“Finish your Blueprint Bond profile”** — single line (`maxLines: 1`, slightly smaller type).
- [x] **Remove** “Still needed: a short summary, a few skills…” subtitle from the prompt card (detail belongs inside the editor).
- [x] Keep one clean tappable card (no stacked wrapping explanation).

**Done when:** Hub prompt is one short line + chevron; no multi-line “still needed” stack.

### A4. Message reactions — both sides (bugfix)

**Root cause (confirmed):** Backend and `_canReact` already allow reacting to any accessible message. Long-press menu is gated by:

```dart
_hasMenu => _canReport || _canDelete  // missing _canReact / _canEdit
```

So the reaction **picker** is unreliable when report/delete aren’t offered the same way; own messages (delete) always get the menu.

**Work**
- [x] `chat_bubble.dart`: `_hasMenu` includes `_canReact` (and `_canEdit` if desired).
- [ ] Manual QA: long-press partner message → picker → reaction appears for both users; strip toggle still works.
- [ ] Optional: double-tap or dedicated react affordance so discovery doesn’t depend on long-press alone.

**Done when:** Either participant can add/remove reactions on the other’s messages in DM and group.

---

## Wave B — Blueprint Bond professional profile

### B1. New structured fields

**Today:** headshot, résumé, summary, skills, career interests, LinkedIn, Handshake, consent.  
**Add (student-editable):**

| Field | Shape (proposed) | Notes |
|-------|------------------|--------|
| Internships / experience | JSON list: `title`, `organization`, `start`/`end` or `is_current`, short `description` | Cap e.g. 5 entries |
| Projects | JSON list: `name`, `role?`, `url?`, short `description` | Cap e.g. 5 entries |

**Work**
- [x] Alembic migration on `scholar_professional_profiles` (or child tables if lists grow — JSONB is fine at this scale).
- [x] `scholars/schema.py` + `service.py` validation (length, count, sanitize URLs).
- [x] Completeness rules: decide if internships/projects are **required** for `is_complete` or optional enrichment (recommend: **optional** for v1 so approval isn’t blocked).
- [x] Mobile `blueprint_bond_screen.dart` — professional sections UI (forms for add/edit/remove).
- [x] Employer DTOs (`EmployerScholarView`) + employer-portal detail page show new sections when approved.

### B2. Professional page UX

**Work**
- [x] Visual hierarchy: headshot + name → summary → experience → projects → skills → links → documents → consent/status.
- [x] Clear **submission status** UI once Wave C lands (draft / pending review / approved / changes requested).
- [x] Keep social Profile separate (no leaking dating-style bio to employers).

**Done when:** Scholars can save internships/projects; incomplete optional fields don’t break existing complete profiles.

---

## Wave C — Honors admin approval before partner portal

**Today:** Employer discovery requires active Presidential Scholar + `employer_visibility_consent` only. Spec deferred “manage professional-profile status.”

### C1. Status model

Proposed statuses on `ScholarProfessionalProfile`:

```text
draft → pending_review → approved
                      ↘ changes_requested → (edit) → pending_review
admin may also → revoked / hidden
```

**Visibility rule for `GET /employers/scholars*`:**

```text
active membership
AND employer_visibility_consent
AND status == approved
AND (optional) is_complete   # product choice — recommend require complete before submit
```

### C2. Student flow

- [x] “Submit for review” (not auto-publish on consent alone).
- [x] Consent remains required but **insufficient** without approval.
- [x] Edits after approval: either auto-revert to `pending_review` (recommended) or allow minor edits without re-review (product call — recommend **re-review on material fields**).

### C3. Honors admin

- [x] Admin API under `require_admin_scope('honors_admin')`: list pending, approve, request changes (note), revoke.
- [x] Admin portal page (mirror Employers queue UX).
- [x] Audit log entries for approve/reject/revoke.
- [ ] In-app or email notify scholar on decision (nice-to-have in same wave or follow-up).

### C4. Employer portal

- [x] Directory copy: only Honors-approved profiles.
- [x] No change to social discovery — Blueprint Bond remains employer-facing only.

**Done when:** A scholar with consent but unapproved status never appears in employer directory; approving makes them visible.

---

## Wave D — Campus Hub + login

### D1. Campus Hub (main dashboard)

**File area:** `campus_hub_screen.dart` + widgets

**Work (light polish — not a redesign)**
- [x] Tighten section spacing; ensure Blueprint prompt (A3) doesn’t dominate.
- [x] Align “Suggested connections” preview cards with compact Connect card density.
- [x] Keep one clear greeting; avoid competing CTAs in the first viewport.
- [x] Quick actions / updates hierarchy: one job per section.

### D2. Login image

- [ ] Swap login hero/branding asset when new image is provided (`login_branding.dart` / assets). *(still on `groupstudent.webp` — no replacement asset designated)*
- [ ] Verify light/dark and small-phone crop.

---

## Wave E — Scaling & efficiency (≤ ~1,500 users)

### E1. Strategy (decision — document, don’t overbuild)

| Concern | Decision for campus scale |
|---------|---------------------------|
| **Redis** | **Not required** for single Render instance. **Required before 2+ workers** for WS fan-out + distributed rate limits (`REDIS_URL`). See ADR-003 / `PHASE_0_1_STATUS.md`. |
| **Caching** | Do **not** add Redis as a general response cache yet. Hot paths already use Postgres + short in-process caches (JWKS, policy docs). If we add cache later: key by entity id + version/updated_at; invalidate on write in the same service method. |
| **Message history** | Never in Redis (locked). |
| **Login abuse** | Supabase Auth dashboard limits (already). |
| **API abuse** | Existing token buckets in `app/shared/rate_limit.py` + `config.py` (e.g. WS send 20/10s, REST messages 60/min, reactions 60/min). Tune env vars for pilot; global “20 req/s per user” is usually **too blunt** — prefer per-endpoint caps already present. |

**Work**
- [x] Add short runbook section to `architecture_review/PRODUCTION_SETUP_CHECKLIST.md` or a new `docs/ops/scaling_1500.md`: when to set Redis, readiness (`/health/ready`), what breaks if Redis is down with multi-instance.
- [x] Fix doc drift: `docs/security/rate_limiting.md` still says Redis limits are deferred — update to match code.
- [ ] Optional: Cloudflare/Render edge rate limit for anonymous floods (deferred unless abuse appears).

### E2. Concurrency / correctness (spot harden)

Already strong patterns: message idempotency, reaction unique constraint, bootstrap unique indexes, `SELECT FOR UPDATE` on activity/group capacity.

**Work**
- [x] Add `IntegrityError` handling on connection **accept → match** if missing (mirror mutual-connect path).
- [x] Confirm scholar profile create + submit-for-review are transaction-safe (single commit; no half-approved state).
- [x] Wave C approve/reject: row lock or version column so two admins can’t double-decide.

### E3. Latency / throughput (observability lite)

**Work**
- [x] Ensure request-id logging stays on; document how to watch Render latency for `/discover`, `/messages`, `/ws`.
- [x] No full APM required for pilot; add simple timing logs on discovery list + employer scholar list if p95 becomes an issue. *(documented trigger in `scaling_1500.md` — no code until needed)*
- [x] Cap group size / reaction fan-out awareness (existing `GROUP_MAX_MEMBERS`).

---

## Out of scope (explicit)

- End-to-end encryption, presence “online” badges (ADR-009).
- Redis-backed discovery/profile response cache before multi-instance need.
- Redesigning employer registration or admin MFA.
- Changing campus email / dual-email auth model.

---

## Suggested sprint breakdown

| Sprint | Deliverables |
|--------|----------------|
| **1** | Wave A (Connect + prompt + reactions) — **done** |
| **2** | Wave B (fields + professional UI) — **done** |
| **3** | Wave C (approval workflow end-to-end) — **done** |
| **4** | Wave D + E (hub polish + scaling docs/hardening) — **done** (login asset swap pending) |

---

## Acceptance checklist (release)

- [x] Connect: no redundant study-partners header; compact cards; limited chips; consistent looking-for.
- [x] Blueprint prompt: single clean line.
- [x] Blueprint: internships + projects editable; professional layout.
- [x] Employer directory shows only Honors-**approved** + consented scholars.
- [x] Reactions work on partner messages via long-press (or better affordance). *(code fix shipped; confirm on device)*
- [x] Scaling note published; Redis provision path clear; rate-limit docs accurate.
- [x] Tests: scholars approval + employer discovery filter; Flutter card/prompt tests. *(reaction menu: code fix shipped; device QA + dedicated widget test still optional)*
- [ ] `pytest` + `flutter analyze` + line limits green; OpenAPI snapshot updated only for intentional API changes.

---

## Key file index

| Area | Paths |
|------|--------|
| Connect | `mobile/lib/features/discovery/screens/discovery_screen.dart`, `widgets/discovery_student_card.dart`, `discovery_card_parts.dart` |
| Blueprint card | `mobile/lib/features/scholars/widgets/blueprint_bond_card.dart` |
| Blueprint editor | `mobile/lib/features/scholars/screens/blueprint_bond_screen.dart`, `providers/scholars_provider.dart` |
| Scholars API | `backend/app/features/scholars/`, `models/programs.py` |
| Employer discovery | `backend/app/features/employers/discovery.py`, `employer-portal/` |
| Admin | `backend/app/features/admin/`, `admin/` portal |
| Reactions | `mobile/.../chat_bubble.dart`, `backend/app/features/messages/reactions.py` |
| Rate limits / Redis | `backend/app/shared/rate_limit.py`, `redis_client.py`, `config.py`, `features/realtime/event_bus.py` |
| Spec debt | `docs/LC_CONNECT_BLUEPRINT_BOND_INTEGRATION_SPEC.md` (deferred profile status) |
