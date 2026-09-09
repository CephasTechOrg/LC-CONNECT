# Opportunities — Link Preview + UX Redesign (implementation plan)

**Status:** Planned  
**Goal:** Make Opportunities clearer and more clickable — server-stored link previews on list + detail, cleaner cards, and complete authoring so campus staff can attach URLs (not only employers).

**Canonical content type:** `CampusPost` with `kind = 'opportunity'` (campus hub).  
Not `campus_positions` (staff directory).

**Rule for every phase:** ship only when that phase’s **gate** is green, plus the usual repo checks (`pytest`, `ruff`, `flutter analyze`, `check_line_limits.py`). Intentional API changes regenerate OpenAPI with `UPDATE_SNAPSHOTS=1 pytest` from `backend/`.

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| Where preview is fetched | **Server-side unfurl** on create/update when `external_url` is set/changed — not client OG fetch on scroll |
| Where preview is stored | Columns (or one JSON) on `campus_posts` — returned on list **and** detail |
| Failure mode | Soft fail: keep `external_url`; show domain fallback chip; never block publish |
| List vs detail | List = compact preview strip; detail = richer preview card + Apply CTA |
| Images | Use remote `preview_image_url` with placeholder on fail; **no** image proxy in V1 |
| SSRF | http/https only; block private/link-local; timeout + body size cap; limited redirects |
| Redesign scope | Opportunities list + shared opportunity affordances on detail; keep hub visual language (`AppColors`, DM Sans, badges) |
| Authoring | Staff compose + admin Posts must expose `external_url` (+ `expires_at` where missing) |

---

## Phase map

| Phase | Name | Primary owner surface | Depends on |
|------:|------|----------------------|------------|
| **0** | Spec & contracts (this doc) | Docs | — |
| **1** | Unfurl + DB persistence | Backend | 0 |
| **2** | API schemas + backfill | Backend | 1 |
| **3** | Mobile link-preview widgets | Mobile | 2 |
| **4** | Opportunities list redesign | Mobile | 3 (can start layout stubs earlier) |
| **5** | Authoring completeness | Mobile + Admin | 1–2 |
| **6** | Tests, verify, pilot smoke | Full stack | 3–5 |

Integrate in order **0 → 1 → 2 → 3 → 4**, with **5** parallelizable after **2**, and **6** as the merge gate.

```text
P0 Spec
  └─ P1 Unfurl + columns
       └─ P2 Schemas + backfill + snapshot
            ├─ P3 Mobile preview UI ──┐
            │                         ├─ P4 List redesign
            └─ P5 Authoring UIs ──────┘
                                      └─ P6 Verify + smoke
```

---

## P0 — Spec & contracts

- [x] Implementation phases written (this file)
- [x] UX rules: list shows preview when URL exists; detail shows fuller card; no preview = current Apply button / domain chip
- [x] API shape agreed (see below)
- [ ] Product confirmation: show preview on **list** (recommended) vs detail-only

### API shape (additive)

Extend `CampusPostSummaryRead` / `CampusPostRead` (and mobile models) with optional:

```text
link_preview: {
  domain: str | null
  site_name: str | null
  title: str | null
  description: str | null   # truncated
  image_url: str | null
  fetched_at: datetime | null
  status: "ok" | "failed" | "pending" | null
} | null
```

`external_url` remains the source of truth for launching.

**Gate:** Plan reviewed; no code required.

---

## P1 — Backend unfurl + persistence

**Files (expected):**

- `backend/app/models/campus.py` — preview columns (or JSONB)
- Alembic migration under `backend/alembic/versions/`
- `backend/app/shared/link_preview.py` (or `campus_hub/link_preview.py`) — fetch + parse + SSRF guards
- Wire in `campus_hub/publishing.py` + employer publish path (`shared/employer_publishing.py`)

**Work:**

- [x] Migration: add preview fields on `campus_posts` (null-safe; existing rows OK)
- [x] Unfurl helper: GET URL, parse `og:` / `<title>` / description; timeouts; size limit; private-IP block
- [x] On create/update: if `external_url` set/changed → unfurl (sync in request **or** best-effort then mark `pending` — prefer sync with short timeout for V1)
- [x] Clear preview fields when `external_url` cleared
- [x] Do not fail the HTTP write if unfurl fails — set `status=failed`, keep URL
- [x] Unit tests for parser + SSRF rejection (no network in unit tests; mock httpx)

**Gate:** Migration upgrades cleanly; create/update with URL populates preview or `failed`; ruff + unit tests green.

---

## P2 — API schemas + backfill

- [x] Extend Pydantic schemas in `campus_hub/schema.py`; serializers in `posts.py`
- [x] Include preview on list + detail + hub summary payloads that already expose posts
- [x] One-shot backfill script or admin-safe management command for rows that already have `external_url` and null preview
- [x] `UPDATE_SNAPSHOTS=1 .venv/bin/pytest` for intentional OpenAPI change
- [x] DB/integration coverage: create opportunity with mocked unfurl → summary includes preview

**Gate:** Snapshot updated intentionally; list endpoint returns preview for seeded URL posts.

---

## P3 — Mobile link-preview UI

**Files (expected):**

- `mobile/lib/features/campus_hub/models/campus_post.dart`
- New widget e.g. `widgets/link_preview_card.dart` (compact + expanded variants)
- `screens/campus_opportunities_screen.dart` — use compact on cards
- `screens/campus_post_detail_screen.dart` — expanded + Apply

**Work:**

- [x] Parse `linkPreview` from API
- [x] Compact strip: image thumb (or icon), site/domain, OG title (1 line)
- [x] Expanded: image, title, description (2 lines), domain, tap → `launchUrl` external
- [x] Fallback when URL present but preview failed/null: hostname chip + Apply
- [x] Loading/error placeholders for broken images (`errorBuilder`)
- [x] Widget tests for compact/expanded/fallback

**Gate:** `flutter analyze` clean; preview renders from fixture JSON; tap still opens `external_url`.

---

## P4 — Opportunities list redesign

Polish the page **after** preview lands so cards don’t get redesigned twice.

- [x] Card hierarchy: category/source badges → title → one-line summary → **link preview** → deadline
- [x] Clear apply affordance when `externalUrl != null` (don’t hide the link until detail)
- [x] Tighten spacing; reuse `CampusBadge` / `campusCategoryStyle`; avoid a second card system
- [x] Extract `_OpportunityCard` to `widgets/` if the screen approaches line limits (`part`/`part of` or shared widget)
- [x] Keep source tabs (All / Campus / Blueprint Bond) + category chips; improve empty states only if needed
- [ ] Optional later: employer org display name on list (may need API field — out of V1 unless already available)

**Gate:** Opportunities screen reads as one clean list; filters still work; no dead affordances.

---

## P5 — Authoring completeness

Without this, most campus-authored opportunities still have **no** URL to preview.

- [x] Staff mobile compose (`compose_campus_post_screen.dart` + publishing provider): optional URL + expires
- [x] Admin `PostsPanel.tsx`: optional external link + expires (API already accepts)
- [x] Validate URL client-side; server already uses `HttpUrl`
- [x] Confirm employer portal path still copies URL → publish → unfurl

**Gate:** Campus staff can create an opportunity with a link end-to-end; preview appears after publish.

---

## P6 — Verify + pilot smoke

- [x] Backend: unit + relevant `tests/db` if added
- [x] Mobile: `flutter analyze` + widget tests
- [x] `python scripts/check_line_limits.py` (no hard-cap failures; compose soft-warn at 415)
- [ ] Manual smoke (run once against staging/prod after deploy):

### Pilot smoke checklist

| # | Step | Pass? |
|---|------|:-----:|
| 1 | Admin or staff creates opportunity with a public `https://` URL → Opportunities list shows compact link preview | ☐ |
| 2 | Open detail → expanded preview + **Apply now** open the external URL | ☐ |
| 3 | Create/publish with a bad or unreachable URL → post still saves; list shows hostname fallback | ☐ |
| 4 | Edit post, clear the link, save → preview disappears on list/detail | ☐ |
| 5 | Set **Closes on** → card shows “Closes …” date | ☐ |
| 6 | Scholar with Blueprint Bond: All / Campus / Blueprint Bond filters still work | ☐ |
| 7 | Employer-submitted opportunity with link still previews after publish | ☐ |
| 8 | Optional: `cd backend && .venv/bin/python scripts/backfill_campus_post_link_previews.py --apply` for any legacy rows | ☐ |

**Gate:** Automated checks green; manual smoke before inviting pilot users.

---

## Hardening pass ✅

Closed after P6 against the Campus Hub badge / Blueprint Bond / live-publish gaps:

- **Opportunities badge** — last-seen cursor is **per-user** (account switch safe); pure count helpers unit-tested; open list still clears.
- **Opportunity WS ping** — publishing an opportunity fans out a content-free `opportunity` control event (same shape as announcements); mobile bumps the Opportunities tile live.
- **Announcements** — docs/API comments aligned with product: unread drops **per detail open** (not on list open). `POST /announcements/read` remains a bulk helper only.
- **Notifications** — keepAlive + list invalidate already shipped; inbox no longer flashes unread chrome while mark-all races the list refetch; provider tests cover seed / +1 / markAllRead / keepAlive.
- **Blueprint Bond prompt** — remount regression test; membership providers stay keepAlive (no blink).

**Gate:** `pytest` (incl. `test_redis_event_bus`, link-preview units) · `flutter analyze` · opportunity badge + BB + ws_protocol tests · `python scripts/check_line_limits.py`. OpenAPI regenerated only for intentional docstring/description updates on announcement read routes.

---

## Out of scope (defer)

- Client-side OG scraping on scroll
- Caching/proxying preview images on our storage
- In-app WebView for apply flows
- Linkify of arbitrary URLs inside `body` text
- Announcement-wide redesign (preview widget may be reused later if announcements have URLs)
- Changing `campus_positions` directory UX

---

## Suggested sprint slicing

| Slice | Phases | Outcome |
|-------|--------|---------|
| **A — Preview foundation** | P0–P2 | API returns stored previews |
| **B — Student UX** | P3–P4 | Nice list + detail |
| **C — Authoring + ship** | P5–P6 | Staff can attach links; verified |

---

## Related paths

| Area | Path |
|------|------|
| Model | `backend/app/models/campus.py` |
| Schemas / publish | `backend/app/features/campus_hub/` |
| Employer publish | `backend/app/shared/employer_publishing.py` |
| List UI | `mobile/lib/features/campus_hub/screens/campus_opportunities_screen.dart` |
| Detail UI | `mobile/lib/features/campus_hub/screens/campus_post_detail_screen.dart` |
| Staff compose | `mobile/lib/features/campus_hub/screens/compose_campus_post_screen.dart` |
| Admin posts | `admin/app/(dashboard)/dashboard/content/PostsPanel.tsx` |
| Employer form | `employer-portal/app/(dashboard)/dashboard/opportunities/` |
