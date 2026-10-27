# LC Connect — Final Pre-Launch UX, Functional Corrections & Product Intelligence Refinement

> **Status:** implemented 2026-10-27 against `main`.
> **Scope guardrails honoured:** no pricing/provisioning/scaling changes, no Redis/infra work, no DB
> restructuring, no new third-party services, no AI/ML/vector services. Existing architecture, auth,
> custom FastAPI WebSocket messaging, DB design, Flutter UI and security controls were preserved.
> Spotlight stays manual-swipe only. Blueprint Bond completeness stays server-owned (6 required
> fields). No new migrations were introduced.

## Context

This is the implementation record for the final pre-launch refinement pass. Each item below was a
discrete, verifiable change; every significant change ships with tests, and the full gate
(`flutter analyze`/`test`, `ruff`, backend unit + DB `pytest`, OpenAPI snapshot, line-limit check)
is green. Where a decision could have gone two ways it is called out with the reasoning.

Two product decisions were confirmed up front:

- **Reaction inbox durability = REST-backed.** The thread list seeds the latest reaction from a
  durable REST field; the live WebSocket event only decorates an already-loaded row.
- **Resource category images = app-provided assets.** Six fixed categories always render, backed by
  bundled per-category images with a tinted-icon fallback.

---

## Changes

### 1. Home greeting — stable, name-first (`greeting`)

- **Problem:** the greeting flickered between a generic fallback and the user's name on every
  load/refresh, and sometimes ignored the saved profile name.
- **Fix:** `resolveGreetingName()` resolves first-name → display-name → email, and the Campus Hub
  screen holds the last-good name across reloads (Riverpod `.value` retains the previous value during
  a reload) so it never blinks back to "there".
- **Files:** `campus_hub_screen.dart`, `campus_hub/data/greeting_name.dart`.
- **Tests:** `greeting_name_test.dart` (resolution order + null-while-loading),
  `campus_hub_layout_test.dart` (greets with the first word of the saved name).

### 2. Spotlight stays manual (`spotlight-verify`, `home-spacing`)

- Confirmed the spotlight carousel never auto-advances (existing test retained), and tightened the
  spotlight→quick-actions gap without touching the shortcut design; validated at 320 dp and 393 dp.

### 3. Message reactions attached to the bubble (`reactions-attached`)

- **Fix:** reactions now render as a collision-safe `Stack`/`Positioned` strip overhanging the
  tail-side corner of the bubble, with a subtle elevation, instead of a detached row. Toggle,
  optimistic update and remote-reaction behaviour are unchanged.
- **Files:** `chat_bubble.dart`, `chat_reactions.dart`.
- **Tests:** `reaction_badge_layout_test.dart` (chip overlaps the bubble edge).

### 4. Reaction inbox — see who reacted, in the thread list (`inbox-reaction-event`, `inbox-reaction-rest`, `inbox-reaction-client`)

- **Durable (REST):** `MessageThreadRead` gained `latest_reaction` (a `ThreadReactionPreview`),
  populated by **one bounded query** (`DISTINCT ON (conversation_id)` over reactions to the owner's
  own, non-deleted messages, excluding self-reactions). No migration, no ordering/unread change.
- **Live (WebSocket):** new user-channel event `messages.reaction_activity`; `PROTOCOL_VERSION`
  bumped **3 → 4** (client `kProtocolVersion` to match). Published best-effort on reaction toggle,
  alongside the existing notification.
- **Client:** parses the new frame and seeds from REST; the thread subtitle precedence is
  **typing → reaction → message**, and a reaction is shown only when it is newer than the latest
  message. Crucially it **never re-sorts** the thread list — a reaction is not new-message activity.
  The live handler safely no-ops for a thread that isn't loaded (REST seeds it on next open).
- **Files:** `messages/schema.py`, `messages/reactions.py`, `messages/service.py`,
  `realtime/protocol.py`, `realtime/runtime.py`, `messages/router.py`, `ws_protocol.dart`,
  `messages_provider.dart`, `messages_screen.dart`.
- **Tests:** `test_thread_reaction_preview.py` (8 DB tests), realtime runtime test (event reaches
  only the author's channel), `ws_protocol_test.dart`, `messages_test.dart` widget tests. OpenAPI
  snapshot regenerated (intentional, additive contract change).

### 5. Campus resources — always six categories (`resources-grid`)

- **Fix:** the six fixed categories always render as a grid (not only when the list is non-empty),
  each backed by a bundled `assets/images/resources/<key>.webp` with a tinted-icon fallback via
  `Image.asset`'s `errorBuilder`. Assets registered in `pubspec.yaml`.
- **Files:** `campus_resources_screen.dart`, `assets/images/resources/README.md`, `pubspec.yaml`.
- **Tests:** `campus_resources_test.dart` (tall viewport; grid-unique titles).

### 6. Activity compact card banner (`activity-compact-banner`)

- **Fix:** the compact card thumbnail renders `bannerUrl` via `CachedNetworkImage` with a placeholder
  and a generic `school.webp` fallback for banner-less or failed images.
- **Tests:** `activities_compact_thumbnail_test.dart`.

### 7. Featured activities — deterministic ranking (`featured-algo`)

- **Fix:** replaced "feature whatever the API returned first" with a pure, injectable
  `selectFeatured(activities, now:)`:
  - **Signals (bounded, weighted):** timing `0.45` (exponential decay), scarcity `0.20`
    (near-full ranks up; **full ranks down** — a dead end), participation `0.35` (relative to the
    current pool).
  - **Fairness:** already-joined `-0.15` (favour discovery), full `-0.20` (can't act on it),
    exact ties break on `id` (reproducible, no flicker).
  - **Honest label:** the hero badge states *why* — "Filling up" / "Starting soon" / "Popular" /
    "Featured" — instead of a blanket "Featured".
- Added `is_cancelled` / `created_at` to the mobile `Activity` model (already sent by the backend).
- **Files:** `activities/data/featured_ranking.dart`, `activities_list.dart`,
  `activities_featured_card.dart`, `activities_provider.dart`; doc at
  `docs/features/activities/featured_ranking.md`.
- **Tests:** `featured_ranking_test.dart` (eligibility, timing, full-penalty, join-penalty, ties,
  all four labels); existing layout test updated.

### 8. Activity detail menu contrast (`activity-menu-contrast`)

- **Fix:** the back arrow and three-dot menu adapt — **white over the banner photo** (backed by a
  strengthened two-sided top scrim), **dark once the bar collapses** onto the solid surface. Gating
  and actions unchanged.
- **Files:** `activity_detail_screen.dart`, `activity_detail_parts.dart`.
- **Tests:** layout test asserts the icon colour flips on collapse.

### 9. Blueprint Bond save robustness (`blueprint-save`)

- **Re-sync optional lists:** after a successful save/submit, the editable lists (skills, career
  interests, internships, projects) are re-seeded from the server's response, so what the student
  sees matches exactly what was stored (server trimming/de-duping/ordering).
- **URL validation:** LinkedIn/Handshake fields are validated and normalized before leaving the
  device (blank clears; scheme-less hosts gain `https://`; junk is rejected with a field-named
  message). A bad URL never reaches the API.
- **Clarity:** added a "Required" group label to mirror the existing "Optional" one.
- **Files:** `scholars/data/url_field.dart`, `blueprint_bond_screen.dart`.
- **Tests:** `url_field_test.dart` (9 pure tests), `blueprint_bond_test.dart` (bad URL blocks save;
  scheme-less normalizes; lists re-sync from the response).

### 10. Groups information architecture (`groups-ia`)

- **De-duplicate:** the Discover list now hides groups you're already a member of (shown in "Your
  groups") or invited to (shown in "Pending invites") via a pure `discoverableGroups()` helper; the
  "All groups" heading became "Discover", with an accurate empty state. Requested/joinable groups
  stay. All existing features preserved.
- **Files:** `groups/data/group_models.dart`, `groups_panel.dart`.
- **Tests:** `group_models_test.dart` (de-dupe helper), `groups_panel_test.dart` (Discover hides
  joined/invited; "in all the groups here" empty state).

### 11. Discovery ranking (`discovery-ranking`)

- **Problem:** the endpoint applied `.limit(150)` to an **unordered** query *before* scoring, so a
  strong match outside that arbitrary window was dropped before it could be compared.
- **Fix:** scoring moved into `rank_candidates()` in the service (router stays thin). It scores the
  **full eligible pool** (the SQL filters already bound it to active/visible/completed students),
  orders by **score desc then `user_id`** (deterministic, reproducible ties), and applies a light
  **diversity pass**: within a run of equal scores it round-robins by major so one program can't
  monopolise a tie block. Per-signal weights remain bounded; filters unchanged.
- **Files:** `discovery/service.py`, `discovery/router.py`.
- **Tests:** `test_discovery_ranking.py` (full-pool scoring, limit, deterministic ties, diversity,
  diversity-never-beats-score, interest cap). OpenAPI snapshot unchanged (data-only behaviour).

### 12. Cross-feature stability / accessibility / WebSocket lifecycle (`stability-pass`)

- Verified disposal on every touched stateful flow (scroll controller, debounce timer, text
  controllers, WS listener via `ref.onDispose`); the new reaction event handler no-ops safely for
  unloaded threads and never changes ordering; adaptive contrast improves (not weakens) legibility.
- Whole-project `flutter analyze` clean; line-limit check passes (every touched file < 600).

### 13. Chat copy, paste, and link previews (post-plan)

- **Copy / paste:** long-press on a non-deleted bubble offers Copy; the body goes on the clipboard
  with a "Copied" snack. Composer paste is the stock TextField path.
- **Tappable URLs:** `LinkedMessageText` splits `http(s)` runs and opens them externally.
- **OG cards:** bubbles and the composer (when a URL is pasted) show `MessageLinkCard`. Unfurl is
  on-demand via `POST /messages/link-preview` — same SSRF-guarded fetch as campus posts. Not stored
  on `Message` rows, does not block send, no protocol bump, no Redis history.
- **Files:** `messages/router.py`, `messages/schema.py`, `shared/link_preview.py` (`first_http_url`),
  `message_urls.dart`, `link_preview_provider.dart`, `message_link_preview.dart`, `chat_bubble.dart`,
  `chat_bubble_options.dart`, `chat_input.dart`.
- **Tests:** `test_link_preview.py`, `test_message_link_preview.py`, `message_urls_test.dart`,
  `chat_copy_link_test.dart`. Isolated widgets (full `ChatScreen` + `pumpAndSettle` hangs on
  RealtimeClient keepalives). OpenAPI + route inventory regenerated for the additive endpoint.

---

## Verification

All gates green on 2026-10-27 (final sweep, including copy/link):

| Gate | Result |
| --- | --- |
| `flutter analyze` (whole project) | No issues |
| `flutter test` (whole suite) | **839 passed** |
| `ruff check .` | All checks passed |
| `pytest --ignore=tests/db` (unit + snapshot + route inventory) | **460 passed** |
| `pytest tests/db` (integration, local Postgres, `REQUIRE_TEST_DB=1`) | **539 passed** |
| OpenAPI + route inventory | Regenerated for additive `latest_reaction` and `POST /api/v1/messages/link-preview` |
| `scripts/check_line_limits.py` | Passes (no file over the 600 hard cap; 25 files over the 400 soft target, pre-existing) |

**Remaining human step:** a manual on-device pass (physical iOS/Android) for the visual items
— greeting stability, attached reactions, resource grid imagery, featured labels, activity-menu
contrast over real banners, copy-from-bubble / paste-into-composer / OG cards on a live URL —
which cannot be exercised in the automated harness. Simulator is running; hot-restart to pick up
new Dart files.

## Final status

All 17 planned items plus chat copy/link previews are implemented and verified. The work stayed
within the stated guardrails: no infra/pricing/scaling changes, no new services, no DB
restructuring, auth and messaging architecture untouched, security/authorization/privacy preserved.
