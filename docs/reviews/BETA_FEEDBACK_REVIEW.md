# LC Connect — Beta Feedback Review & Implementation Blueprint

> **Status:** reviewed 2026-09-16 against `main` @ `4195ff0`.
> **Phase 0 and Phase 1 are implemented** (see the ticked boxes in Part 4b); Phases 2–4 are not.
>
> **Implementing? Start at [Part 4b — Master checklist](#part-4b--master-checklist-work-top-to-bottom).**
> It is a single sequential list covering all 23 reports; work it top to bottom and open Part 2 for
> the detail on whatever item you are on. Part 4 explains why the order is what it is.
>
> **Companion docs:** [`architecture_review/README.md`](../../architecture_review/README.md) ·
> [`architecture_review/PHASE_0_1_STATUS.md`](../../architecture_review/PHASE_0_1_STATUS.md) ·
> [`CONVENTIONS.md`](../../CONVENTIONS.md)

## Context

23 issues were reported during beta testing of the LC Connect mobile app. This document is the
**investigation output**: a read-only review of the actual Flutter app, FastAPI backend, database
models, realtime gateway, push pipeline, navigation, and state management, mapping each report to
what the code really does rather than to assumptions about it.

No code, migrations, data, or deployments were changed in producing it.

**Headline outcome.** The architecture is in good shape and mostly should not be touched. The
messaging stack in particular is mature: persist-before-publish, client-generated idempotency keys
behind a partial unique index, keyset pagination, an optimistic-send ladder with REST escalation,
half-open socket detection, and a bounded outbox. Nine of the twenty-three reports are *not*
architectural — they are **four small systemic defects** whose symptoms surface in many places, plus
genuinely missing features. Two reports turn out to be already-correct behaviour that the reports
misread. Specifically:

- **Report #9 (time mismatch) is a 5-line client render bug**, fully confirmed, not a timezone
  architecture problem. Write path, DB columns, and serialization are all correct.
- **Reports #6, #7, #8 share one root cause**: providers collapse errors into "not eligible", the
  widget renders `SizedBox.shrink()`, and nothing ever retries. One cold-start failure hides four
  dashboard surfaces for the rest of the session.
- **Report #10 is not about token lifetimes.** The app calls `_auth.signOut()` on *any* non-suspension
  bootstrap failure, destroying a perfectly valid session on a transient network error.
- **Report #22's warning is already respected** in the backend — push reachability is never used as
  presence. The inverse is true: presence gates push.
- **Report #12 has a cause independent of infrastructure**: accepting one direct message performs
  **~11 serial database round trips**, eight of them authorization reads, before the server acks.
  That costs 20–55 ms with a co-located database and 0.8–1.6 s across regions — enough to explain
  the report on a fully warm backend. The fix is a design change (cache the authorization decision
  behind the control-event plane that already exists), not workers, Redis, or more CPU.

**Adopted decisions** (confirmed with the owner; these are settled, not open questions):

1. **The Blueprint card leaves the dashboard once the profile is complete**, and the **Profile**
   keeps a permanent entry row as the way back in. This follows report #6 and **supersedes** the
   current code's behaviour (which swaps in a quiet status row and never removes it) — see the
   comment at
   [blueprint_bond_card.dart:46-48](../../mobile/lib/features/scholars/widgets/blueprint_bond_card.dart#L46-L48),
   which this decision knowingly overrides. Because removal now has consequences, **"complete" must
   be defined by an explicit required-field set** computed **server-side** (#6). Revised 2026-09-16
   after an initial decision to keep the row.
2. Groups **move into Messages** as a `Chats | Groups` structure, and leave Discovery.
3. **#12's P1 client work (Phase 2.5) is deliberately not gated behind measurement.** It ships
   before the instrumentation at 2.6, because it is free, low-risk, and an improvement under every
   branch of #12's decision tree. Only P2/P3 wait on data. This ordering is intentional — do not
   "correct" it into a dependency on 2.1/2.6.

---

## Evidence standard used

Every verdict below is one of:

| Verdict | Meaning |
|---|---|
| **Confirmed (code)** | Root cause located and proven by reading code. No runtime test needed. |
| **Confirmed (design)** | The behaviour is real and intentional; the report is a valid product complaint. |
| **Partially confirmed** | Feature exists but is incomplete or too weak to satisfy the report. |
| **Already correct** | The report describes a problem the code does not have. |
| **Needs measurement** | Mechanism identified; the dominant factor must be measured before choosing a fix. |

---

## Part 1 — Four systemic root causes behind nine reports

### S1. Error-to-hidden collapse with no recovery path
*Drives #6, #7, #8; contributes to #17.*

The pattern, repeated across scholars and attendance:

1. A provider swallows failure into a falsy value —
   [attendance_provider.dart:93-102](../../mobile/lib/features/attendance/providers/attendance_provider.dart#L93-L102)
   catches **every** exception and returns `false`;
   [programs_provider.dart:63-68](../../mobile/lib/features/programs/providers/programs_provider.dart#L63-L68)
   falls back to `const []` on `AsyncError`.
2. The widget treats falsy as "not eligible" and renders nothing —
   [blueprint_bond_card.dart:31](../../mobile/lib/features/scholars/widgets/blueprint_bond_card.dart#L31),
   [blueprint_bond_card.dart:45](../../mobile/lib/features/scholars/widgets/blueprint_bond_card.dart#L45),
   [attendance_open_card.dart:57-63](../../mobile/lib/features/attendance/widgets/attendance_open_card.dart#L57-L63).
3. **Nothing retries.** Campus Hub's pull-to-refresh
   ([campus_hub_screen.dart:74-78](../../mobile/lib/features/campus_hub/screens/campus_hub_screen.dart#L74-L78))
   invalidates only `campusHubOverviewProvider`, `activeAttendanceProvider`, and the opportunity
   counter. There is **no `ref.invalidate(myProgramMembershipsProvider)` or
   `ref.invalidate(scholarProfileNotifierProvider)` anywhere in `mobile/lib`**, and
   `myProgramMembershipsProvider` is `keepAlive`, so it re-runs only when `authNotifierProvider`
   changes identity.

Net effect: **one failed `GET /programs/me` at launch silently removes four surfaces —** the
Blueprint card, the attendance check-in card, the attendance scanner (reported to the user as
*"not available for your account"*), and the scholar filter on Campus Opportunities
([campus_opportunities_screen.dart:88-105](../../mobile/lib/features/campus_hub/screens/campus_opportunities_screen.dart#L88-L105))
— with no error, no retry, and no in-app recovery short of killing the app.

**Fix (shared).** Introduce one convention and apply it to every eligibility-gated surface:

- Eligibility providers must distinguish **"no" from "unknown"**. Replace `bool` with a small
  sealed result (`Eligible` / `NotEligible` / `Unknown(error)`), or keep `AsyncValue` and have the
  widget branch on `hasError` explicitly.
- A widget may hide on `NotEligible`, but on `Unknown` it must render a compact retry affordance
  (reuse `AppErrorState` from [app_states.dart:5](../../mobile/lib/shared/widgets/app_states.dart#L5), or a
  one-line inline variant sized for a dashboard slot).
- Remove the blanket `catch (_) { return false; }` in `honorsAttendanceEnabledProvider`. A feature
  flag that cannot be read is unknown, not off.
- Add both providers to Campus Hub's `RefreshIndicator`, and add an automatic re-fetch on
  `AppLifecycleState.resumed` and on realtime `reconnected` — the pattern already proven in
  [notifications_provider.dart:41-44](../../mobile/lib/features/notifications/providers/notifications_provider.dart#L41-L44)
  and [unread_provider.dart:61-62](../../mobile/lib/features/messages/providers/unread_provider.dart#L61-L62).

### S2. Free-tier cold start is a large latency term — but not the only one
*Amplifies #7, #8, #10, #11, #13, #17; a contributing (not sole) cause of #12.*

> **Scope caveat.** An earlier draft called this "the dominant latency term". Tracing #12's send path
> found a second, independent cost — **~11 serial database round trips per message send** — that
> explains the same symptom on a fully warm backend. Do not treat cold start as the explanation for
> every slow path until Part 5 item 1 separates them. Where a report has a non-cold-start cause, it
> is named in that report's own section.

[render.yaml:6,12](../../render.yaml#L6-L12) — `plan: free`, and the start command is bare
`uvicorn app.main:app` with **no `--workers`**: one process, one event loop, 0.1 CPU, and Render
free-tier spin-down after idle. The app already documents the consequence in
[app_constants.dart:24-29](../../mobile/lib/core/constants/app_constants.dart#L24-L29):

> "The API runs on a plan that suspends after idle, so the FIRST request after a quiet period waits
> on a 30–60s cold start — a 10s connect timeout failed those outright."

The API is in `region: oregon` while users are in North Carolina, adding a steady ~70–80 ms RTT
floor to every request on top of that.

This fact explains a family of reports, though #12 additionally has a cause of its own. A push notification arrives precisely when the
backend is *most likely* to be cold (nobody has used it), so the user taps and the app's first
request hits a spun-down server. That is why *"attendance notifications sometimes fail when
opened"* — combined with S1, the timeout is rendered as an eligibility error.

**This is a measurement item, not an automatic infrastructure purchase.** See Part 5. Explicitly do
**not** add `--workers N` as a fix: with `REDIS_URL` unset (absent from
[render.yaml](../../render.yaml)), a second worker breaks in-process realtime fan-out
([manager.py:107-111](../../backend/app/features/realtime/manager.py#L107-L111)), breaks
`schedule_offline_push`'s socket-count presence check
([runtime.py:236-264](../../backend/app/features/realtime/runtime.py#L236-L264)), and breaks the
**process-local attendance QR challenge dict**
([challenges.py:42-55](../../backend/app/features/attendance/challenges.py#L42-L55)) — a QR issued on
instance A would fail `challenge_exists` on instance B and return `410 "QR expired"` on a valid
scan. `architecture_review/DECISION_LOG.md:19` already records this ordering: Redis first, then
workers. The correct sequence is confirmed and must be preserved.

### S3. No bootstrap state; `AsyncLoading` is read as "logged out"
*Drives #11; causes the silent-deep-link loss in #8; #10 is a related but distinct defect.*

[app_router.dart:83](../../mobile/lib/core/router/app_router.dart#L83) sets `initialLocation: '/login'`,
and [app_router.dart:60-61](../../mobile/lib/core/router/app_router.dart#L60-L61) collapses loading into
logged-out:

```dart
bool get isLoggedIn => _ref.read(authNotifierProvider).asData?.value != null;
```

So while `POST /auth/bootstrap` is in flight for a user with a valid stored session, the redirect at
[app_router.dart:124](../../mobile/lib/core/router/app_router.dart#L124) holds them on `/login`. Combined
with S2 this is not a flash — it is **up to 60 seconds of a fully interactive login form** shown to
an already-authenticated user.

Separately and more seriously, [auth_provider.dart:94-101](../../mobile/lib/features/auth/providers/auth_provider.dart#L94-L101):

```dart
} on DioException catch (e) {
  if (isAccountSuspendedError(e)) { _markSuspended(); return null; }
  await _auth.signOut();          // ← destroys a valid session on a network error
  return null;
}
```

A cold-start timeout or flaky campus Wi-Fi at launch **signs the user out**. This is report #10's
actual cause: the Supabase session and refresh token were fine; the app threw them away because a
*backend* call failed.

### S4. No client cache layer at any level
*Drives #1, #17; contributes to #13.*

[pubspec.yaml](../../mobile/pubspec.yaml) contains **no** `cached_network_image`, `dio_cache_interceptor`,
`flutter_cache_manager`, `shared_preferences`, `hive`, or `sqflite`. Consequences:

- **No HTTP cache, no ETag, no request dedup.** [api_client.dart:28-40](../../mobile/lib/core/api/api_client.dart#L28-L40)
  has exactly two interceptors (auth, offline-banner). The only in-flight coalescing in the app is
  for token refresh ([api_client.dart:123-125](../../mobile/lib/core/api/api_client.dart#L123-L125)).
- **No image disk cache.** All 11 remote-image sites use raw `Image.network`, which uses Flutter's
  **RAM-only** `ImageCache` — wiped on every app restart and under memory pressure.
- **`ShellRoute`, not `StatefulShellRoute`** ([app_router.dart:217](../../mobile/lib/core/router/app_router.dart#L217)),
  and tabs switch with `context.go` ([nav_shell.dart:51](../../mobile/lib/shared/widgets/nav_shell.dart#L51)),
  which *replaces* the stack. Combined with 18 `autoDispose` providers, **every tab switch is a full
  cold refetch with a skeleton flash.** Opening the Groups tab fires 3 requests; opening a group
  detail fires 3 more; opening the notification inbox refetches `GET /notifications` every time.
- **Only one persistent data cache exists in the whole app**:
  [chat_message_cache.dart](../../mobile/lib/features/messages/data/chat_message_cache.dart) — flat JSON
  per conversation under `<appDocs>/chat_cache/`. It is the right pattern and the model to extend.

---

## Part 2 — Report-by-report findings

### #1 Message drafts are not preserved — **Confirmed (code)**

**Exists.** Nothing. `inputController` is a plain `TextEditingController` created at
[chat_screen.dart:75](../../mobile/lib/features/messages/screens/chat_screen.dart#L75), cleared on send at
[chat_send_logic.dart:20](../../mobile/lib/features/messages/widgets/chat_send_logic.dart#L20), and disposed
at [chat_screen.dart:170](../../mobile/lib/features/messages/screens/chat_screen.dart#L170). It is never
read from or written to any store. `ChatMessageCache` persists sent/failed `ChatMessage` rows only —
not composer text.

**Expected.** Unsent composer text survives leaving the conversation, app backgrounding, and app
restart; it is scoped per conversation; it is cleared on successful send or when the user empties the
field.

**Design.** Add `ChatDraftStore` alongside `ChatMessageCache`, same mechanism (`path_provider` +
`<appDocs>/chat_drafts/<sanitized-conversation-id>.json`), same best-effort error swallowing.

- Write: debounce ~500 ms on `onChanged` (mirroring `scheduleCacheSave`'s 400 ms debounce at
  [chat_screen_logic.dart:157-163](../../mobile/lib/features/messages/widgets/chat_screen_logic.dart#L157-L163)),
  plus a synchronous flush in `dispose()` and on `AppLifecycleState.paused`.
- Read: load in `initState` and seed `inputController.text`, restoring the cursor to the end.
- Delete: on successful send (after the optimistic row is added, not after the ack — the text is
  already committed to the message list), and when the trimmed field becomes empty.
- Do **not** keep drafts in a Riverpod provider keyed by conversation id as the source of truth:
  the store must survive process death, which provider state does not.
- Key by the **canonical conversation id**, not the addressing id, so a DM's `match_id` and its
  conversation cannot produce two drafts.

**Edge cases.** Draft for a conversation the user is later removed from or blocked in (prune on a
`403`/`404` load of that thread); draft older than a retention window (prune drafts untouched for
30 days on app start); a draft plus a failed optimistic message — they are independent and both must
render; multiple devices are deliberately **not** synced (a draft is device-local, and syncing it
would need a server round trip per keystroke).

**Privacy.** Drafts are unsent user text in app-private storage. They must be deleted on logout and
on account deletion — extend the existing teardown so the `chat_drafts` directory is removed
alongside `chat_cache`.

**Tests.** Unit tests on `ChatDraftStore` mirroring
[chat_message_cache_test.dart](../../mobile/test/features/messages/chat_message_cache_test.dart); widget
test that types, pops the route, re-enters, and asserts the text; widget test that sends and asserts
the draft file is gone.

---

### #2 Bottom navigation appears inside conversations — **Confirmed (design)**

**Exists.** The chat routes are nested inside `/messages`, which is inside the `ShellRoute`, so
`NavShell` wraps them — [app_router.dart:286-316](../../mobile/lib/core/router/app_router.dart#L286-L316).
`ChatScreen` then renders its *own* full-screen `Scaffold` with a custom header and a manual back
button ([chat_header.dart:41-44](../../mobile/lib/features/messages/widgets/chat_header.dart#L41-L44))
*inside* `NavShell`'s `Scaffold` — two stacked scaffolds, one redundant nav bar.

**A latent crash is hiding here.** The comments at
[app_router.dart:196-211](../../mobile/lib/core/router/app_router.dart#L196-L211) record that
`/connections` and `/profile/blueprint-bond` were moved **out** of the shell because cross-navigator
pushes locked the navigator (`'!_debugLocked'`), *"which surfaced as the app appearing to sign
out"*. The chat screen still performs exactly that kind of push: tapping a group sender's avatar
pushes the top-level `/users/:profileId`
([chat_bubble.dart:41](../../mobile/lib/features/messages/widgets/chat_bubble.dart#L41)) and the header
identity pushes top-level `/groups/:groupId`
([chat_screen.dart:240](../../mobile/lib/features/messages/screens/chat_screen.dart#L240)). **Moving chat
out of the shell removes this exposure**, so #2 is a stability fix as well as a UI fix.

**Design.** Promote the three chat routes to top level, beside the precedent already set by
`/attendance/scan`, `/connections`, `/groups/:groupId`:

```
/messages/new                      → stays in shell (a list-like picker)
/chat/:matchId                     → top level
/chat/group/:conversationId        → top level
```

Keep `/messages/:matchId` as a redirect for one release so any live push payload or saved deep link
still resolves. `nav_shell.dart`'s `_currentIndex` uses `location.startsWith(t.path)`, so once chat
is outside the shell nothing needs to change there. Update the six push sites:
[messages_screen.dart:141-145](../../mobile/lib/features/messages/screens/messages_screen.dart#L141-L145),
[message_navigation.dart:22-34](../../mobile/lib/features/messages/utils/message_navigation.dart#L22-L34),
[groups_panel.dart:80-93](../../mobile/lib/features/groups/widgets/groups_panel.dart#L80-L93),
[your_groups_section.dart:30](../../mobile/lib/features/groups/widgets/your_groups_section.dart#L30).

Also drop the now-redundant inner `Scaffold` nesting and keep one back affordance.

**Cross-platform.** Verify the iOS edge-swipe-back gesture still pops correctly now that chat is a
root-navigator route, and that the Android hardware back button returns to `/messages` rather than
exiting the app.

**Tests.** Widget test asserting no `BottomNavigationBar` in the chat subtree; navigation test that
back from chat lands on `/messages`; a redirect test for the legacy path.

---

### #3 Profile-picture viewing is limited — **Confirmed (code)**

**Exists.** Nothing. `grep` for `Hero(`, `InteractiveViewer`, `photo_view`, or any full-screen image
dialog across `mobile/lib` returns **zero hits**.
[AvatarWidget](../../mobile/lib/core/widgets/avatar_widget.dart#L4) has no `onTap` parameter at all; it is
used at 22 sites.

**Design.** Add an `AvatarWidget`-adjacent viewer rather than 22 ad-hoc dialogs:

- Add an optional `onTap` to `AvatarWidget` and a shared `showAvatarPreview(context, url, heroTag)`
  helper that opens a dismissible full-screen route: black scrim, `Hero` transition keyed on a
  stable tag (`avatar:<userId>`), `InteractiveViewer` for pinch-zoom, swipe-down-to-dismiss, and a
  close button with a ≥48 px target.
- Only attach it where a preview is meaningful and permitted: own profile
  ([profile_hero.dart:30](../../mobile/lib/features/profile/widgets/profile_hero.dart#L30)), a public
  profile the viewer is already allowed to see
  ([public_profile_screen.dart:268](../../mobile/lib/features/profile/screens/public_profile_screen.dart#L268)),
  the chat header, and group avatars. **Not** on dense list rows (inbox, directory, member lists) —
  tapping a row must keep navigating, not open an image.

**Privacy.** Do not add a preview anywhere the profile itself is gated. `Profile.is_hidden` and
`Profile.show_profile_to_verified_only` ([core.py:98-100](../../backend/app/models/core.py#L98-L100))
already govern visibility server-side; the preview must never be reachable from a surface those
flags would hide. Scholar headshots live in a **private** bucket behind 300-second signed URLs
([storage.py:114-133](../../backend/app/shared/storage.py#L114-L133)) — those must never be routed through
a cached preview, and a signed URL must not be retained after the route closes.

**Accessibility.** Semantics label ("Profile photo, double tap to close"), focus trap in the route,
`Escape`/back dismissal, and respect `MediaQuery.disableAnimations` for the Hero transition.

**Tests.** Widget test that tapping the profile hero opens the viewer and that dismissal restores the
previous route; a test asserting list-row avatars do **not** open it.

---

### #4 Message reactions are missing — **Confirmed (code)**

**Exists.** Nothing on either side. `grep -i reaction` over `backend/app` and `mobile/lib` returns
zero hits: no table, no column, no endpoint, no protocol frame, no UI. The long-press bottom sheet
([chat_bubble.dart:154-199](../../mobile/lib/features/messages/widgets/chat_bubble.dart#L154-L199)) offers
only "Delete for everyone" and "Report message".

**Design.**

*Schema* — new table, not a JSON column on `messages` (a JSON blob cannot be uniquely constrained,
and concurrent reactions would lose writes):

```
message_reactions
  id              UUID PK
  message_id      UUID FK messages(id) ON DELETE CASCADE, indexed
  user_id         UUID FK users(id)    ON DELETE CASCADE, indexed
  emoji           VARCHAR(8)  NOT NULL          -- server-side allowlist
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
  UNIQUE (message_id, user_id, emoji)           -- idempotent toggle
  INDEX (message_id, emoji)                     -- aggregate per message
```

Constrain `emoji` to a small server-side allowlist (6–8 reactions). A free-text emoji column is an
abuse surface and makes the aggregate unbounded.

*API* — `PUT /messages/{message_id}/reactions/{emoji}` (idempotent add) and
`DELETE /messages/{message_id}/reactions/{emoji}`. Authorization must reuse
`accessible_conversation` ([conversations.py:134](../../backend/app/shared/conversations.py#L134)) — the
same gate REST sends use, which already handles 404-if-not-a-member, 403-if-blocked, and
403-if-staff-thread-closed. Reject reactions on soft-deleted messages (`deleted_at IS NOT NULL`).

*Realtime* — two new protocol frames mirroring the existing shape in
[protocol.py](../../backend/app/features/realtime/protocol.py) and its Dart mirror
[ws_protocol.dart](../../mobile/lib/core/realtime/ws_protocol.dart): `message.reaction.added` /
`message.reaction.removed`, carrying `{conversation_id, message_id, user_id, emoji}`. Publish to the
conversation channel via `event_bus.publish_to_conversation`, exactly as `emit_message_created` does
([runtime.py:151-167](../../backend/app/features/realtime/runtime.py#L151-L167)). Bump
`PROTOCOL_VERSION`; unknown frames already degrade safely via `UnknownEvent`
([ws_protocol.dart:199](../../mobile/lib/core/realtime/ws_protocol.dart#L199)), so older clients are
forward-compatible.

*Read path* — include an aggregated `reactions: [{emoji, count, reacted_by_me}]` on `MessageRead`.
Aggregate in the **same query** as the message page using a lateral join or a grouped subquery — do
not add a per-message round trip, which would reintroduce N+1 on a 50-row page.

*Client* — extend the long-press sheet with a reaction row; render a compact chip strip under the
bubble; apply optimistically and roll back on failure (the pattern already used for delete at
[chat_screen_logic.dart:199-216](../../mobile/lib/features/messages/widgets/chat_screen_logic.dart#L199-L216)).

**Race conditions.** Double-tap producing two adds → the unique constraint makes it idempotent;
catch `IntegrityError` and return success, mirroring `persist_message_idempotent`
([service.py:222-264](../../backend/app/features/messages/service.py#L222-L264)). Add and remove racing →
last-write-wins is acceptable; the realtime event carries the resulting state. A reaction arriving
for a message not yet in the local list (paged out) → ignore, and let the next page load carry the
aggregate.

**Rate limiting.** Add a per-minute reaction limit alongside `ws_send_rate_per_10s`; a reaction
toggle is cheaper than a message but trivially spammable.

**Accessibility.** Each chip needs a semantics label ("👍 3 reactions, you reacted"); the reaction
picker needs ≥48 px targets and must be reachable without a long-press (long-press alone is not an
accessible-only affordance — add it to the existing options sheet too).

---

### #5 Sent-message editing is missing — **Confirmed (code)**

**Exists.** No edit path at all. The **only** mutation on a message is soft delete —
`DELETE /messages/{message_id}` ([router.py:161](../../backend/app/features/messages/router.py#L161)) →
[service.py:202-219](../../backend/app/features/messages/service.py#L202-L219). There is no `edited_at`
column anywhere in `backend/app/models/`.

**Recommended edit window: 15 minutes, server-enforced, measured from `created_at`.** Rationale
rather than an arbitrary pick:

- It must be short enough that the conversational record stays trustworthy — the report itself asks
  for "a reasonable, intentionally defined period".
- It must be **longer than the client's own send-failure ladder** so an edit can never race a
  retry: `sendDeadline` is 60 s ([chat_screen.dart:62-73](../../mobile/lib/features/messages/screens/chat_screen.dart#L62-L73)).
- It must be **shorter than the moderation-report window** so an edit cannot be used to sanitise a
  message after someone has reported it. Report evidence is already snapshotted at
  [safety/service.py:34-47](../../backend/app/features/safety/service.py#L34-L47); 15 minutes keeps the
  edit window well inside a plausible reporting delay, and the audit table below closes the gap
  entirely.
- 15 minutes matches user expectation set by mainstream messengers, so it needs no explanation in
  the UI beyond a countdown.

Make it `MESSAGE_EDIT_WINDOW_SECONDS` in [config.py](../../backend/app/config.py) (default 900) so it is
tunable without a code change, consistent with how every other window in the app is configured.

**Design.**

*Schema* — two changes:

```
ALTER messages ADD edited_at TIMESTAMPTZ NULL

message_edits                                  -- immutable audit/history
  id           UUID PK
  message_id   UUID FK messages(id) ON DELETE CASCADE, indexed
  previous_body TEXT NOT NULL
  edited_at    TIMESTAMPTZ NOT NULL DEFAULT now()
```

`message_edits` is required, not optional: without it an edit destroys evidence, and the repo
already treats that as unacceptable (see the soft-delete rationale at
[messaging.py:95-98](../../backend/app/models/messaging.py#L95-L98) and the report snapshot table). Purge
it on the same retention schedule as soft-deleted bodies —
`MESSAGE_SOFT_DELETE_RETENTION_DAYS` / [message_retention.py](../../backend/app/shared/message_retention.py),
so the runbook in `architecture_review/MESSAGE_RETENTION_CRON_RUNBOOK.md` needs one added step.

*API* — `PATCH /messages/{message_id}` with `{body}`. Authorization, in order:

1. `accessible_conversation` (member, not blocked, thread open).
2. `message.sender_id == actor_id` — **sender only**. Unlike delete, a group admin must **never** be
   able to edit someone else's words; that would be a forgery primitive. This is a deliberate
   asymmetry from the delete rules at
   [service.py:202-206](../../backend/app/features/messages/service.py#L202-L206).
3. `deleted_at IS NULL` → else 409.
4. `now() - created_at <= window` → else **409** with a distinct machine-readable code so the client
   can say "edit window has passed" rather than a generic failure.
5. Same body validation as send (1–2000 chars, `MAX_BODY_CHARS`).

Write `previous_body` to `message_edits` and set `edited_at` in one transaction.

*Realtime* — new `message.edited` frame `{conversation_id, message_id, body, edited_at}`, published
to the conversation channel and to each member's user channel (so the inbox preview updates too) —
same dual publish as `broadcast_message_deleted`
([runtime.py:170-176](../../backend/app/features/realtime/runtime.py#L170-L176)).

*Client* — add "Edit" to the long-press sheet, shown only when `isMine && !deleted && withinWindow`;
reuse the composer in an edit mode with a visible remaining-time hint; mark edited bubbles with a
small "edited" label next to the timestamp at
[chat_bubble.dart:135-144](../../mobile/lib/features/messages/widgets/chat_bubble.dart#L135-L144). Apply
optimistically, roll back on failure. Extend `ChatMessage` and `_toCacheJson`/`_fromCacheJson`
([chat_message_cache.dart:55-82](../../mobile/lib/features/messages/data/chat_message_cache.dart#L55-L82))
with `editedAt` — and note the cache format change needs a tolerant reader, since existing cache
files lack the key.

**Edge cases.** Editing a message that another member has already reported (allowed — the snapshot
and `message_edits` both preserve the original); editing while offline (queue is out of scope for v1
— require connectivity and fail clearly); an edit arriving for a paged-out message (ignore);
an edit racing a delete (delete wins: check `deleted_at` inside the transaction, not before it);
clock skew — the window is evaluated **server-side only**, and the client's countdown is advisory.

**Push.** An edit must **not** fire a push notification. Only new messages do.

---

### #6 Blueprint card sometimes does not appear — **Confirmed (code)**

**Exists.** Backend is correct and needs no change. Eligibility is a single concept — an active
`ProgramMembership` on `Program.slug == 'presidential_scholars'`
([programs.py:19-33](../../backend/app/shared/programs.py#L19-L33)) — enforced twice, at the router
dependency ([scholars/router.py:20-31](../../backend/app/features/scholars/router.py#L20-L31)) and again at
the service choke point ([scholars/service.py:57-65](../../backend/app/features/scholars/service.py#L57-L65)).
`GET /scholars/me` **lazily creates** the profile row
([service.py:66-75](../../backend/app/features/scholars/service.py#L66-L75)), so a newly verified scholar
never gets a 404. `GET /programs/me` is gated only by `get_current_user`
([programs/router.py:13-31](../../backend/app/features/programs/router.py#L13-L31)).

Terminology note for the doc: there is **no "Honest" status in the codebase**. `grep -i honest`
returns three prose comments and nothing else. The gating concept is **Honors / Presidential
Scholars**, and it is distinct from both `User.is_verified` (email confirmed) and
`User.campus_verified` (admin-granted badge) — three different "verified" notions that the beta
reports conflate.

**Root cause.** Entirely client-side, and it is **S1**:

1. `myProgramMembershipsProvider` errors → `isVerifiedScholarProvider` returns `false` →
   [blueprint_bond_card.dart:31](../../mobile/lib/features/scholars/widgets/blueprint_bond_card.dart#L31)
   hides the card. A failed `GET /programs/me` is indistinguishable from "not a scholar".
2. `scholarProfileNotifierProvider` errors → `profile == null` →
   [blueprint_bond_card.dart:45](../../mobile/lib/features/scholars/widgets/blueprint_bond_card.dart#L45)
   hides the prompt.
3. Neither provider is in any invalidation path. The card is gone for the rest of the session.

**Additional defect found.** The `entry` style on Profile
([blueprint_bond_card.dart:55-58](../../mobile/lib/features/scholars/widgets/blueprint_bond_card.dart#L55-L58))
does **not** guard on `profile == null`, so a failed `/scholars/me` renders
"Blueprint Bond · profile **incomplete**" with an amber dot for a scholar whose profile may be
complete. That is worse than hiding — it states something false.

**Expected (confirmed decision — Adopted decision 1).**

| Surface | Incomplete | Complete |
|---|---|---|
| **Dashboard** (Campus Hub) | `_PromptCard` — "Finish your Blueprint Bond profile" | **nothing — the card leaves the dashboard** |
| **Profile** | `_EntryRow`, amber dot, "profile incomplete" | `_EntryRow`, green dot, "profile complete" — **permanent, always the way back in** |

So the dashboard is purely a nudge that retires itself, and Profile is the durable reference. This
overrides the current `_StatusRow`-on-dashboard behaviour; `_StatusRow` becomes dead code on the Hub
and should be deleted rather than left for a future reader to wire back up.

#### Completeness must be defined and moved server-side

Today completeness is computed **on the client**, from three fields
([blueprint_bond_card.dart:38-40](../../mobile/lib/features/scholars/widgets/blueprint_bond_card.dart#L38-L40)):

```dart
final isComplete = profile != null &&
    (profile.summary?.isNotEmpty ?? false) &&
    (profile.hasResume || profile.hasHeadshot);
```

Two problems, and the decision above makes both load-bearing — a rule that merely changed a card's
styling now decides whether the card exists at all.

1. **The rule is too loose, and it omits the one field that matters most.**
   `employer_visibility_consent` is **not** part of it. So a scholar can be "complete", lose the
   dashboard nudge, and still be **invisible to every employer** — which is the entire stated purpose
   of the card ("Get seen by employer partners",
   [blueprint_bond_card.dart:159-165](../../mobile/lib/features/scholars/widgets/blueprint_bond_card.dart#L159-L165)).
   That is the worst possible failure of this feature: it would silently stop asking precisely when
   the student has not yet achieved the goal. `summary?.isNotEmpty` also accepts a single character,
   and `hasResume || hasHeadshot` accepts a headshot with no résumé.
2. **It is client-side, so it will drift.** The admin portal, the employer portal, and any future
   surface would each re-derive "complete" independently. There must be exactly one definition.

**Fix: make the server the authority.** Add to `ScholarProfessionalProfileRead`
([scholars/schema.py:9-24](../../backend/app/features/scholars/schema.py#L9-L24)) two computed fields,
populated in `_to_read` ([scholars/service.py:39-54](../../backend/app/features/scholars/service.py#L39-L54)):

```
is_complete:    bool
missing_fields: list[str]     # e.g. ["resume", "skills", "employer_visibility_consent"]
```

The client then renders from `is_complete` and never computes it. `missing_fields` is what lets the
prompt say *what* is left instead of a generic nudge — a strictly better prompt, and it costs nothing
extra because the server already has every field in hand.

**Recommended required-field set** (no schema migration needed — every field already exists on
`ScholarProfessionalProfile`, [programs.py:55-85](../../backend/app/models/programs.py#L55-L85)):

| Field | Requirement | Why |
|---|---|---|
| `summary` | non-empty, **≥ 80 characters** | a one-word summary is not an employer-facing bio |
| `headshot_path` | present | employer-facing views lead with it |
| `resume_path` | present | the core artefact; the current `OR` makes it optional |
| `skills` | **≥ 3** | drives employer discovery/matching |
| `career_interests` | **≥ 1** | drives employer discovery/matching |
| `employer_visibility_consent` | `true` at the **current** `consent_version` | without it the profile is invisible — completeness without it is meaningless |
| `linkedin_url`, `handshake_url` | **optional** | not every student has them; requiring either would strand people |

Put the thresholds in one module-level constant beside `CURRENT_CONSENT_VERSION` in
[scholars/service.py](../../backend/app/features/scholars/service.py) so they are tunable in one place,
and so `is_complete` and the prompt copy can never disagree.

> **Confirm the thresholds before implementing.** The set above is a recommendation, not a settled
> decision. Too strict and the card never leaves the dashboard (the complaint returns inverted); too
> loose and incomplete profiles reach employers. The consent requirement is the one item I would
> argue is non-negotiable; the `80` / `3` / `1` numbers are adjustable.

**Completeness can now regress — the card must be able to come back.** This is new behaviour the
current design never had to handle: revoking consent, or bumping `CURRENT_CONSENT_VERSION` to force
re-consent ([programs.py:76-81](../../backend/app/models/programs.py#L76-L81)), flips a complete
profile back to incomplete. The dashboard prompt must reappear in that case, which it will
automatically **provided** `scholarProfileNotifierProvider` is invalidated after any consent change —
`setConsent` already writes `state = AsyncData(...)`
([scholars_provider.dart:77-81](../../mobile/lib/features/scholars/providers/scholars_provider.dart#L77-L81)),
so this works today, but it must be covered by a test rather than left implicit.

**Fix (client).** Apply S1; render from the server's `is_complete`; delete the dashboard
`_StatusRow`; guard the `entry` style on `profile == null` so it renders an unknown state instead of
asserting "incomplete"; surface `missing_fields` in the prompt.

**Ordering note.** The server-side `is_complete` must ship **before or with** the client change.
Shipping the client first would have it read a field that does not exist yet and treat every profile
as incomplete — so the card would never leave the dashboard, which is the opposite of the intent.

**Tests.** Widget tests: scholar + `is_complete: true` → **nothing on the dashboard**, green entry row
on Profile; scholar + incomplete → prompt on both, naming a missing field; non-scholar → nothing
anywhere; **`/programs/me` errors → retry affordance, not silence**; **`/scholars/me` errors on
Profile → neither "complete" nor "incomplete" asserted**. Backend tests in
[test_scholars.py](../../backend/tests/db/test_scholars.py): `is_complete` false for each single
missing field in turn; true only when all are satisfied; **false when consent is revoked** and
**false when `consent_version` is stale**. Extend
[blueprint_bond_test.dart](../../mobile/test/features/scholars/blueprint_bond_test.dart). Note the
`ScholarProfessionalProfileRead` change **will** move the OpenAPI snapshot — regenerate deliberately.

---

### #7 Attendance check-in card sometimes does not appear — **Confirmed (code)**

**Exists.** The backend model is sound. `AttendanceSession` is fully `timestamptz`
([attendance.py:36-41](../../backend/app/models/attendance.py#L36-L41)); "one open session per program" is
enforced by a partial unique index
([attendance.py:18-26](../../backend/app/models/attendance.py#L18-L26)); `_now()` is
`datetime.now(UTC)`; the client learns about sessions from
`GET /attendance/honors/active` ([router.py:34-54](../../backend/app/features/attendance/router.py#L34-L54)).

Eligibility unrolls to: valid JWT → bootstrapped row → active account → `is_verified` →
**`role == 'student'`** → `HONORS_ATTENDANCE_ENABLED` → active `presidential_scholars` membership
([permissions.py:32-42](../../backend/app/features/attendance/permissions.py#L32-L42)).

**Root causes — three live causes in likely order of impact, plus one ruled out.** Items 1–3 are
the candidates; item 4 was investigated and eliminated.

1. **S1 again, and worse here.** `honorsAttendanceEnabledProvider`
   ([attendance_provider.dart:93-102](../../mobile/lib/features/attendance/providers/attendance_provider.dart#L93-L102))
   catches every exception and returns `false`. `honorsAttendanceVisibleProvider`
   ([:127-131](../../mobile/lib/features/attendance/providers/attendance_provider.dart#L127-L131))
   requires it `== true`, so a single cold-start timeout on `GET /attendance/honors/status` disables
   every attendance surface for the session. Campus Hub's pull-to-refresh does **not** invalidate
   it.
2. **`role == 'student'` is derived from the email domain, permanently.**
   [email_roles.py:36-54](../../backend/app/shared/email_roles.py#L36-L54) maps
   `@students.livingstone.edu → student` and `@livingstone.edu → staff`, and
   `sync_user_role_from_email` re-applies it on **every** bootstrap
   ([auth/service.py:197](../../backend/app/features/auth/service.py#L197)). An Honors student whose
   campus address is `@livingstone.edu` is permanently `staff` → **403 on
   `/attendance/honors/active`** → card silently hidden. This also makes the Groups tab unreachable
   for them (see #19). **This needs a data check** (Part 5) — it would exactly explain "some
   eligible users do not receive the card" while others do.
3. **The realtime notification does not refresh attendance state.** The WS `notification` frame for
   `honors_attendance_open` only bumps the bell counter and invalidates the notification list
   ([notifications_provider.dart:66-71](../../mobile/lib/features/notifications/providers/notifications_provider.dart#L66-L71)).
   It does **not** invalidate `activeAttendanceProvider`. So on an already-open dashboard the card
   can lag by up to 30 s, and the 30 s timer
   ([attendance_open_card.dart:33-39](../../mobile/lib/features/attendance/widgets/attendance_open_card.dart#L33-L39))
   only runs **while the card's widget is mounted** — i.e. only while the user is on the Campus Hub
   tab. Because `ShellRoute` replaces the stack on tab switch, leaving Home disposes the timer
   entirely.
4. **Config drift risk — *not* a live cause.** `HONORS_ATTENDANCE_ENABLED` (default `False`,
   [config.py:139](../../backend/app/config.py#L139)) and `ATTENDANCE_QR_SIGNING_SECRET`
   ([config.py:143](../../backend/app/config.py#L143)) are **absent from
   [render.yaml](../../render.yaml)**. **Both are confirmed set in the Render dashboard today**
   (owner-confirmed, 2026-09-16), so this is *not* contributing to the reported symptom — rule it
   out as a cause of #7. It remains a real fragility: the values exist only in dashboard state, so a
   service re-create or a fresh environment silently turns attendance off (404 on every student
   route) or breaks QR signing (503 on session start), with no signal in version control. Declare
   both with `sync: false` so the requirement is visible and a new environment fails loudly instead
   of quietly.

**Additional defects found.**

- `_tickCountdown` calls `ref.read(activeAttendanceProvider)` **once per second**
  ([attendance_open_card.dart:48-53](../../mobile/lib/features/attendance/widgets/attendance_open_card.dart#L48-L53)).
  On an `autoDispose` provider with no other listener, each `read` can start and immediately dispose
  the provider — a request storm risk. Derive the countdown from a locally held `closesAt` captured
  in `build`, and never touch a provider from a 1 Hz timer.
- The card does not check `active.isCheckedIn`, so it keeps saying **"Scan to Check In"** after a
  successful check-in until the session closes.
- **Sessions never auto-close without a read.** `maybe_auto_close_session`
  ([attendance/service.py:91-96](../../backend/app/features/attendance/service.py#L91-L96)) is lazy and
  read-triggered; there is no scheduler. A lapsed session stays `status='open'` in the DB and holds
  the partial unique index until something touches it — which blocks the instructor from starting the
  next session (409). Add a periodic sweep (the `lifespan` already runs two background loops —
  [main.py:70-71](../../backend/app/main.py#L70-L71) — so this is a third task, not new infrastructure).
- `AttendanceSession.started_by_id` is `nullable=False` with an `ondelete='SET NULL'` FK
  ([attendance.py:33-35](../../backend/app/models/attendance.py#L33-L35)) — contradictory; a real user
  deletion will raise.

**Expected.** Every eligible student sees the card the moment a session opens — pushed, not polled —
with an accurate countdown and a check-in action; the card reflects "already checked in"; it
disappears when the session closes; and any failure to *determine* eligibility shows a retry, never
silence.

**Fix.** S1 + add `activeAttendanceProvider` invalidation to the WS `honors_attendance_open`
handler + hold the countdown locally + render a checked-in state + declare the two env vars + add
the auto-close sweep. Keep the 30 s poll as a backstop but treat realtime as the primary signal.

---

### #8 Attendance notifications fail when opened — **Confirmed (code)**

**Exists.** Payload is minimal and correct-by-design:
`{'type': 'honors_attendance_open', 'session_id': <uuid>}`
([push.py:232-254](../../backend/app/features/notifications/push.py#L232-L254)) — the rotating QR secret is
deliberately never sent. Tap handling covers background
(`onMessageOpenedApp`) and terminated (`getInitialMessage()`)
([notification_service.dart:66-73](../../mobile/lib/core/notifications/notification_service.dart#L66-L73)).
The route is top level ([app_router.dart:212-216](../../mobile/lib/core/router/app_router.dart#L212-L216)).

**Root causes — this is the most multi-factor item in the set.**

1. **Eligibility failure is reported as ineligibility.**
   [attendance_scanner_screen.dart:52-65](../../mobile/lib/features/attendance/screens/attendance_scanner_screen.dart#L52-L65):
   `catch (_) { visible = false; }` → *"This attendance session is not available for your
   account."* A cold-start timeout on `/programs/me` or `/attendance/honors/status` produces a
   **wrong, alarming, and unrecoverable** message. Combined with S2 — a push arrives exactly when
   the backend is coldest — this is very likely the reported error.
2. **`session_id` is read from the payload and then discarded.** `onOpenAttendanceScanner` takes no
   argument ([notification_service.dart:203-205](../../mobile/lib/core/notifications/notification_service.dart#L203-L205)),
   so the scanner re-resolves "the active session" itself. A tap on a slightly stale notification
   yields *"Attendance is closed."* with no explanation of which session.
3. **The router redirect can silently swallow the deep link.** `push('/attendance/scan')` is
   evaluated by the redirect gate. If auth is still `AsyncLoading` → `/login`
   ([app_router.dart:124](../../mobile/lib/core/router/app_router.dart#L124)); unverified →
   `/verify-email`; stale policy version → `/accept-policies`; incomplete profile → `/onboarding`.
   In all four cases the tap lands somewhere else with **no indication why**. This is S3.
4. **Permission states fall through.**
   [attendance_scanner_screen.dart:67-77](../../mobile/lib/features/attendance/screens/attendance_scanner_screen.dart#L67-L77)
   handles `isDenied`, `isRestricted`, `isPermanentlyDenied` — but **not** `isLimited` /
   `provisional`. Those fall through and proceed *without* permission; `MobileScanner` then fails
   with no handler.
5. **`setState` after await with no `mounted` guard** at lines 71 and 76 (lines 58 and 81 *do*
   guard) — backing out during the OS permission prompt throws.
6. **Error recovery keys off string equality.**
   [:171-172](../../mobile/lib/features/attendance/screens/attendance_scanner_screen.dart#L171-L172)
   compares `_errorMessage == 'Attendance is closed.'`. The backend's 409 detail is
   `'Attendance is closed'` — **no trailing period**
   ([attendance/service.py:280](../../backend/app/features/attendance/service.py#L280)) — so a genuinely
   closed session gets a "Scan again" button that cannot succeed.
7. **Unparseable QR is silently ignored.** `tryParse` returns `null` → bare `return`
   ([:113-114](../../mobile/lib/features/attendance/screens/attendance_scanner_screen.dart#L113-L114)) —
   the scanner appears dead.
8. **No foreground push handler exists at all.** There is no
   `FirebaseMessaging.onMessage` listener anywhere in `mobile/lib`, and no
   `onBackgroundMessage` handler. A push arriving while the app is foregrounded produces nothing.
9. If notification permission was denied, `registerForUser` returns at
   [:57-60](../../mobile/lib/core/notifications/notification_service.dart#L57-L60) **before**
   `_listenersAttached = true`, so no tap handler exists for that session and the tap is dropped.

**Related deep-link bug in the same family.**
[message_navigation.dart:12-34](../../mobile/lib/features/messages/utils/message_navigation.dart#L12-L34)
resolves group-vs-DM from the **already-loaded thread list**. On a cold start `threads` is `null`, so
a **group** message notification opens the **DM** route with `extra: null` — wrong header, no
`groupId`, group features disabled.

**Design.**

- Carry the id: `onOpenAttendanceScanner(String? sessionId)` → `/attendance/scan?session=<id>`; the
  scanner validates that the resolved active session matches, and says so specifically when it does
  not ("That session has closed" vs "Attendance is closed").
- Replace error-string matching with **typed error codes** from the API. Add a machine-readable
  `code` to attendance error responses and branch on that.
- **Queue the deep link until the app is ready.** Add a pending-deep-link holder: capture the intent,
  and apply it only once the router reports a settled authenticated state. This is the same fix as
  S3 and must be built once for all notification types.
- Handle `isLimited`/`provisional` explicitly; add `mounted` guards at both missing sites; give
  unparseable-QR visible feedback; add a foreground `onMessage` handler that shows the existing
  in-app banner ([in_app_banner.dart](../../mobile/lib/core/notifications/in_app_banner.dart)) instead of
  nothing.
- Fix `openMessageConversation` to resolve group-vs-DM from the **server** (or fetch the thread) when
  the local list is unavailable, rather than defaulting to DM.
- Move controller construction out of the field initialiser
  ([:25-28](../../mobile/lib/features/attendance/screens/attendance_scanner_screen.dart#L25-L28)) and add
  `AppLifecycleState` handling so the camera stops on background and restarts on resume.

**Security note (good, keep).** The QR HMAC design is correct: signature over
`session_id:challenge_id:expires_at` with `hmac.compare_digest`, a 10 s TTL, and 2 s skew tolerance
([qr.py:46-96](../../backend/app/features/attendance/qr.py#L46-L96)); `verify_challenge_token` returns
`False` when the secret is unconfigured rather than accepting. Do not weaken any of this.

**Tests.** Extend [attendance_test.dart](../../mobile/test/features/attendance/attendance_test.dart) with:
eligibility-request failure → retry, **not** "not available for your account"; closed session → no
"Scan again"; limited permission → permission prompt, not a crash; deep link during `AsyncLoading`
→ scanner after auth settles, not `/login`. Backend: assert the 409 detail/code contract that the
client now depends on (an API-snapshot-guarded change — see the gate in
[CLAUDE.md](../../CLAUDE.md)).

---

### #9 Activity time mismatch (6:00 PM shows as 10:00 PM) — **Confirmed (code). Exact root cause found.**

**This is not a timezone architecture problem.** Everything except client rendering is correct:

- **Write** — `.toUtc().toIso8601String()` at
  [activities_provider.dart:159-160](../../mobile/lib/features/activities/providers/activities_provider.dart#L159-L160)
  and [create_activity_screen.dart:151-152](../../mobile/lib/features/activities/screens/create_activity_screen.dart#L151-L152).
- **Storage** — `DateTime(timezone=True)` at
  [activities.py:21-22](../../backend/app/models/activities.py#L21-L22). Repo-wide, **all 80 datetime
  columns are `timezone=True`; there are zero naive columns**, and `datetime.utcnow()` appears
  **zero** times in the backend (38 uses of `datetime.now(UTC)`).
- **Serialization** — `ORJSONResponse` ([main.py:103](../../backend/app/main.py#L103)) emits
  `2026-09-16T22:00:00+00:00`.

**The bug.** `DateTime.parse` on a string carrying an offset returns a DateTime with
`isUtc == true` ([activities_provider.dart:43-45](../../mobile/lib/features/activities/providers/activities_provider.dart#L43-L45)).
`DateFormat.format()` renders a DateTime's **own** wall-clock fields and ignores `isUtc`. Five call
sites format `startTime`/`endTime` **without `.toLocal()`**, so 22:00 UTC prints as "10:00 PM" —
exactly the reported 4-hour offset (EDT = UTC−4):

| File | Line |
|---|---|
| [activity_detail_screen.dart](../../mobile/lib/features/activities/screens/activity_detail_screen.dart#L244) | 244 |
| [activity_detail_screen.dart](../../mobile/lib/features/activities/screens/activity_detail_screen.dart#L250) | 250 |
| [activities_featured_card.dart](../../mobile/lib/features/activities/widgets/activities_featured_card.dart#L174) | 174 |
| [activities_featured_card.dart](../../mobile/lib/features/activities/widgets/activities_featured_card.dart#L178) | 178 |
| [activities_compact_card.dart](../../mobile/lib/features/activities/widgets/activities_compact_card.dart#L97) | 97 |

The two shared helpers are timezone-blind — they format whatever they are handed:
[activities_screen.dart:90-96](../../mobile/lib/features/activities/screens/activities_screen.dart#L90-L96),
plus a **duplicate** `_formatTimeRange` at
[activity_detail_screen.dart:502-506](../../mobile/lib/features/activities/screens/activity_detail_screen.dart#L502-L506).

**Proof of the inconsistency:** the *same* activity renders **correctly** on the dashboard, because
[campus_home_previews.dart:58](../../mobile/lib/features/campus_hub/widgets/campus_home_previews.dart#L58)
*does* call `.toLocal()`, and correctly in the edit form
([create_activity_screen.dart:58,61](../../mobile/lib/features/activities/screens/create_activity_screen.dart#L58-L61)).
Dashboard shows 6:00 PM, Activities tab and detail screen show 10:00 PM.

**Fix — structural, not five patches.** Patching the five sites leaves the next call site free to
reintroduce it (`isUtc` is inspected **nowhere** in the app).

1. Add a shared `mobile/lib/shared/util/app_date_format.dart` with `formatDate`, `formatTime`,
   `formatTimeRange`, `formatRelative` — each calling `.toLocal()` **internally, exactly once**.
2. Route all activity, campus-hub, notification, connection, and message formatting through it;
   delete the two private `_formatTimeRange` copies and the per-screen `_formatDate`/`_timeAgo`
   duplicates.
3. Make the model layer the boundary instead of each widget: have `Activity.fromJson` (and peers)
   store `DateTime.parse(...).toLocal()` so a UTC-flagged DateTime never escapes the parser. Pick
   **one** of (2) or (3) as the invariant and document it — mixing both is how this class of bug
   returns.
4. Add a lint-level guard: a unit test that asserts no `DateFormat(...).format(` call site receives a
   `isUtc == true` DateTime, or simpler, a repo grep test asserting `DateFormat` is only used inside
   `app_date_format.dart`.

**Also fix (same family, lower severity).**
[connections_screen.dart:86-92](../../mobile/lib/features/connections/screens/connections_screen.dart#L86-L92)
— the `≥7 days` branch formats without `.toLocal()`, so a request created between 20:00 and 23:59
local shows the wrong calendar day.

**Backend defect found while tracing.**
[activities/service.py:127-130](../../backend/app/features/activities/service.py#L127-L130) compares
`end <= start` where `start` may be an **aware** value loaded from the DB and `end` a **naive** value
from a PATCH body. `ActivityUpdate` has no `model_validator`
([activities/schema.py:23-32](../../backend/app/features/activities/schema.py#L23-L32)), so a client
sending `"2026-09-16T18:00:00"` with no offset triggers
`TypeError: can't compare offset-naive and offset-aware datetimes` → unhandled **500**. Unreachable
from the current mobile client (which always sends `Z`) but unguarded. Fix by requiring
`AwareDatetime` on every datetime field in request schemas repo-wide — there is currently **no
Pydantic timezone normalization anywhere**.

**Tests.** Golden/widget test with `TZ` fixed to `America/New_York`: create at 18:00, assert the
detail screen, the Activities card, and the dashboard preview all render "6:00 PM". Backend test for
the naive-PATCH 422 (instead of 500).

---

### #10 Authentication/session persistence — **Confirmed (code), but not the reported cause**

**Exists.** The architecture is correct and should be preserved. The backend issues **no tokens of
its own**; every request carries a Supabase access token verified in
[supabase_jwt.py](../../backend/app/security/supabase_jwt.py) with a pinned alg allowlist
(`RS256/ES256/HS256`, [:18](../../backend/app/security/supabase_jwt.py#L18)), `require: [exp, sub, role]`,
audience `authenticated`, derived issuer, 10 s leeway, and a 1-hour JWKS cache
([:98-134](../../backend/app/security/supabase_jwt.py#L98-L134)). The session persists to the platform
keystore, not SharedPreferences
([secure_session_storage.dart:23-50](../../mobile/lib/core/storage/secure_session_storage.dart#L23-L50)),
with PKCE verifiers likewise. The Dio interceptor refreshes once on 401, replays the request, and
single-flights concurrent refreshes so refresh tokens cannot rotate against each other
([api_client.dart:90-135](../../mobile/lib/core/api/api_client.dart#L90-L135)). `autoRefreshToken` and
`persistSession` are left at their defaults (`true`).

**Actual configured lifetimes: not determinable from this repo.** There is **no `supabase/config.toml`**
— `supabase/` contains only `migrations/20260510000000_messages_rls.sql`. No `JWT_EXPIRY`, no refresh
rotation or reuse-interval setting exists in any file. These are dashboard-managed in the hosted
project. The only in-repo claim is a comment asserting a "~1h access token"
([secure_session_storage.dart:12-13](../../mobile/lib/core/storage/secure_session_storage.dart#L12-L13)).
**Recording the real values is a Part 5 measurement item — do not change lifetimes before reading
them.**

**Root cause of the reported symptom.** Not lifetimes. Three concrete defects:

1. **`signOut()` on any transient bootstrap failure** —
   [auth_provider.dart:99](../../mobile/lib/features/auth/providers/auth_provider.dart#L99). A cold-start
   timeout at launch destroys a valid session and forces re-authentication. **This is the bug.**
2. **Only `signedOut` is handled** from `onAuthStateChange`
   ([auth_provider.dart:81-86](../../mobile/lib/features/auth/providers/auth_provider.dart#L81-L86));
   `tokenRefreshed`, `signedIn`, `userUpdated` are ignored, and `_AuthRouterNotifier` does not
   listen to Supabase's own auth stream at all.
3. **Non-token 401s trigger a pointless refresh + replay.** `'User not bootstrapped'`
   ([dependencies.py:102-106](../../backend/app/dependencies.py#L102-L106)) and the inactive-account 401
   ([:53-54](../../backend/app/dependencies.py#L53-L54)) are both 401s that a token refresh cannot fix.

**Fix.**

- Distinguish *"the session is invalid"* (401/403 with a token-related reason → sign out) from
  *"the backend is unreachable"* (timeout, connection error, 5xx → **keep the session**, surface a
  retry). Reuse `_UnreachableInterceptor`'s classification
  ([api_client.dart:50-54](../../mobile/lib/core/api/api_client.dart#L50-L54)) — it already distinguishes
  exactly this.
- Retry bootstrap with backoff on unreachable, rather than signing out; the offline banner already
  exists to communicate the state.
- Have the backend return a machine-readable reason on 401 so the client can branch without string
  matching (server logs already record the real reason —
  [dependencies.py:36-40](../../backend/app/dependencies.py#L36-L40) — the client just needs a stable
  code).
- Do **not** attach a refresh/replay to a 401 whose code says "not bootstrapped".

**Security.** Two hardening notes worth recording but not urgent: `_email_verified` **defaults to
`True`** when no claim is present ([supabase_jwt.py:79-90](../../backend/app/security/supabase_jwt.py#L79-L90));
and `verify_iss` is `bool(_issuer())`, so an HS256 deployment with `SUPABASE_URL` unset performs
**no issuer check**. Also, [render.yaml:23](../../render.yaml#L23) still declares `JWT_SECRET_KEY`, which
no longer exists in `config.py` — dead config to remove.

---

### #11 Login screen flashes at startup — **Confirmed (code)**

**Exists.** No splash, no bootstrap route, no `AsyncLoading` branch in the redirect. See **S3**.
`LoginScreen` does read `authNotifierProvider.isLoading`
([login_screen.dart:59](../../mobile/lib/features/auth/screens/login_screen.dart#L59)) but only to disable
its own submit button — it renders the full form regardless.

**Expected.** `Launch → Splash/Brand → Restore session → App | Login`. The login screen is never used
as a loading state, and a returning user with a valid session never sees it.

**Design.**

1. Add `/splash` and set `initialLocation: '/splash'`.
2. Give the router a **three-state** auth view instead of a boolean. Add
   `AuthPhase { restoring, authenticated, unauthenticated }` to `_AuthRouterNotifier`, derived from
   `AsyncValue` (`isLoading && !hasValue → restoring`). In `redirect`, **return `null` while
   `restoring`** if the current location is `/splash`, and redirect everything else to `/splash`.
3. The splash screen renders the LC brand mark
   (`assets/images/lclogo.webp`, already bundled) plus a quiet progress indicator, and — because of
   S2 — a "still connecting…" message after ~5 s and a retry after ~20 s. A 60-second blank splash is
   not better than a wrong login screen.
4. Drain the pending-deep-link queue (from #8) once the phase settles.

**Edge cases.** Session exists but bootstrap fails → splash shows retry, session preserved (#10);
session exists but account suspended → `/suspended` (already handled); no session → straight to
`/login` with no splash dwell beyond one frame; cold start during an OS-initiated relaunch from a
notification tap → deep link queued, not lost.

**Accessibility.** The splash must announce its state (`Semantics(liveRegion: true)`) — a silent
spinner is invisible to a screen-reader user. Respect `MediaQuery.disableAnimations`.

**Tests.** Extend [flow_no_dead_ends_test.dart](../../mobile/test/features/auth/flow_no_dead_ends_test.dart):
stored session + slow bootstrap → splash then `/home`, and **never** `/login`; no session → `/login`;
bootstrap error → splash with retry and session intact.

---

### #12 Messages can take noticeable time to send — **Confirmed (code) + needs measurement**

**Exists — and the client transport logic is excellent. Do not rewrite it.**
[chat_send_logic.dart:16-38](../../mobile/lib/features/messages/widgets/chat_send_logic.dart#L16-L38)
inserts optimistically with a `local:<clientMessageId>` id and never waits for the server. The
escalation ladder ([chat_screen.dart:62-73](../../mobile/lib/features/messages/screens/chat_screen.dart#L62-L73)):
WS send → 6 s no-ack → REST `POST /messages/threads/{id}` with the same `client_message_id` → 20 s
retry → 60 s deadline. The server persists **before** publishing and returns
`message.ack{duplicate}` ([gateway.py:223-250](../../backend/app/features/realtime/gateway.py#L223-L250)),
arbitrated by the partial unique index `uq_messages_sender_client`
([messaging.py:62-68](../../backend/app/models/messaging.py#L62-L68)). In-flight sends are requeued to the
**front** of the outbox on reconnect ([realtime_client.dart:219-243](../../mobile/lib/core/realtime/realtime_client.dart#L219-L243)),
safe precisely because the server is idempotent. Half-open sockets are detected after two silent
heartbeat intervals ([:192-215](../../mobile/lib/core/realtime/realtime_client.dart#L192-L215)). Push is
fire-and-forget behind a 3 s reconnect grace, never awaited in the request path
([runtime.py:161-167,236-264](../../backend/app/features/realtime/runtime.py#L161-L167)).

#### What the user is actually timing

Because the insert is optimistic, **the bubble appears instantly regardless of network conditions.**
So "messages take noticeable time to send" cannot mean time-to-appear — it can only mean the user is
watching the **status tick** (clock → ✓). What they are timing is **time-to-ack**.

This reframing matters because time-to-ack is governed by two things only: the server's synchronous
work before it emits the ack, and the client's own escalation constants. Throughput, worker count,
and fan-out cost are **not** in this path.

Correction to a common misreading: `_sink` does silently drop typing and read frames when the socket
is not `ready` ([realtime_client.dart:314-318](../../mobile/lib/core/realtime/realtime_client.dart#L314-L318)),
but `sendMessage` does **not** drop the send —
[realtime_client.dart:290-306](../../mobile/lib/core/realtime/realtime_client.dart#L290-L306) enqueues it
to the outbox for the next `auth.ok`. A message is never lost to a not-ready socket; it is *delayed*
by the handshake, and the 6 s ack timer runs against it anyway.

#### The real finding: ~11 serial database round trips to accept one DM

`_on_send` ([gateway.py:223-250](../../backend/app/features/realtime/gateway.py#L223-L250)) opens a fresh
session and performs every authorization read **sequentially** before it inserts. Traced for a DM
addressed by `match_id` — which is what the mobile client always sends for a DM
([messages_screen.dart:145](../../mobile/lib/features/messages/screens/messages_screen.dart#L145) passes
`thread.addressingId`):

| # | Call | Query | Note |
|---|---|---|---|
| 1 | `recheck_account` ([service.py:49-55](../../backend/app/features/realtime/service.py#L49-L55)) | `SELECT users` | mid-session suspension check |
| 2 | `resolve_conversation` ([conversations.py:121-131](../../backend/app/shared/conversations.py#L121-L131)) | `db.get(Conversation, ref)` | **guaranteed miss for every DM** — `ref` is a match id |
| 3 | → `conversation_for_match_id` | `db.get(Match, ref)` | |
| 4 | → `ensure_dm_conversation` ([:38](../../backend/app/shared/conversations.py#L38)) | `SELECT conversations` | get-or-create |
| 5 | `is_active_member` ([:220](../../backend/app/shared/conversations.py#L220)) | `SELECT conversation_members` | |
| 6 | `active_member_ids` ([:232](../../backend/app/shared/conversations.py#L232)) | `SELECT conversation_members` | inside the block check |
| 7 | `users_are_blocked` ([policies.py:30-39](../../backend/app/shared/policies.py#L30-L39)) | `SELECT blocks` | **in a `for` loop over members** |
| 8 | `active_members_with_mute` ([:153](../../backend/app/shared/conversations.py#L153)) | `SELECT conversation_members` | **duplicates #6's rows** |
| 9 | `persist_message_idempotent` `flush()` | `INSERT messages` | |
| 10 | `commit()` | `COMMIT` | |
| 11 | `refresh(message)` | `SELECT messages` | only to read back `created_at` |

A `staff_dm` adds a 12th (`staff_thread_is_open`). Every one of these is a serial await on one
connection — no batching, no pipelining, nothing concurrent.

**The cost is entirely a function of database RTT:**

| DB RTT | Time-to-ack (≈11 × RTT) | Verdict |
|---|---|---|
| 2–5 ms (co-located) | 20–55 ms | imperceptible |
| 70–80 ms (cross-region) | **770–880 ms** | matches the report exactly |
| 150 ms (distant region) | **~1.6 s** | matches the report exactly |

So **the report can be fully explained without cold start at all.** This is the branch that Part 5
item 1 must resolve, and it makes Part 5 item 2 (confirm the Supabase region relative to
`region: oregon`) the single highest-value measurement in this document.

#### Decision tree after measurement

| Measurement outcome | Conclusion | Act on |
|---|---|---|
| Time-to-ack is high on **first send after idle only**, then drops | Cold start (S2) dominates | Keep the instance warm (paid plan or health pinger). Do the free client wins below anyway. |
| Time-to-ack is **consistently** high, warm or cold, and server-side send time tracks it | **The RTT budget above is the cause** | Collapse the query path (P2/P3 below). No infrastructure change. |
| Time-to-ack is high but **server-side send time is low** | Transport, not the server | Client escalation + readiness work (P1 below). |
| Time-to-ack is low but users still complain | They are reacting to the **6 s tick stall** on reconnect, or to #23's weak tick contrast | P1 + #23 |

Instrument all four in one pass — they are not mutually exclusive, and the likely real answer is
"cold start explains the worst reports, the RTT budget explains the median."

#### Design principles to apply

1. **Do the minimum synchronous work needed to durably accept the message; defer everything else.**
   Fan-out, push, and receipts are already deferred correctly. Authorization is not — it is 8 reads
   in the critical path.
2. **Push invalidation instead of re-reading.** A control-event plane already exists for exactly
   this: `apply_control_event` handles `user.suspended`, `pair.revoked`, `member.revoked`, and
   `conversation.revoked` ([event_bus.py:173-208](../../backend/app/features/realtime/event_bus.py#L173-L208)).
   Authorization state that is *actively invalidated* does not need to be re-read per message.
3. **Make perceived latency independent of transport health.** Idempotency is already guaranteed, so
   transports can be **raced** rather than failed over on a timer.
4. **Measure at the boundary the user feels** (time-to-ack), not the layer that is easy to
   instrument.
5. **Preserve persist-before-publish.** The ack must never precede the commit; that ordering is a
   locked decision (`architecture_review/PHASE_0_1_STATUS.md`) and is what makes the client's
   requeue-on-reconnect safe.

#### Improvements, tiered

**P1 — client-side, free, do regardless of the measurement.**

- **Race the transports instead of waiting 6 s.** When `sendMessage` enqueues to the outbox (socket
  not `ready`), fire the REST send **immediately in parallel** rather than after the ack timeout. The
  partial unique index makes double-delivery a no-op that returns `duplicate: true`, and
  `escalateToRest` already calls `rt.cancelPendingSend` on success. This removes a fixed 6-second
  stall from every send made during a reconnect — which, because the socket is torn down on **every**
  background ([realtime_client.dart:330-340](../../mobile/lib/core/realtime/realtime_client.dart#L330-L340)),
  is every first message after reopening the app.
- **Make the ack timeout adaptive.** Replace the fixed 6 s with `max(1.5s, p95_ack_rtt × 3)` from a
  rolling in-memory window. A healthy ack is tens of milliseconds; 6 s is three orders of magnitude
  of slack.
- **Surface connection state.** `OfflineBanner` and `_OutboxBanner`
  ([chat_input.dart:95-157](../../mobile/lib/features/messages/widgets/chat_input.dart#L95-L157)) exist;
  show "connecting…" while `RealtimeStatus != ready` so a slow send reads as a known state rather
  than a hang.
- **Overlap the socket connect with bootstrap.** The client connects on auth + foreground
  ([realtime_client.dart:412-448](../../mobile/lib/core/realtime/realtime_client.dart#L412-L448)); the
  handshake can start alongside `POST /auth/bootstrap` instead of after it.

**P2 — server-side, mechanical, no design change. Removes 4 of 11 round trips.**

- **Drop `refresh(message)`** (#11). Use `INSERT ... RETURNING created_at` (or `eager_defaults=True`
  on the mapper) so the server default comes back with the insert. −1 RTT, zero risk.
- **Remove the duplicate member read** (#8 re-queries #6's rows). Have the block check reuse the
  single `active_members_with_mute` result. −1 RTT.
- **Skip the guaranteed miss** (#2). For a DM the client sends a match id, so `db.get(Conversation,
  ref)` always misses. Either have the client address DMs by `conversation_id` (the model already
  treats `conversation_id` as the universal container —
  [messaging.py:82-88](../../backend/app/models/messaging.py#L82-L88) — and this is the documented
  post-cutover direction), or resolve both shapes in one query with a `UNION`/join instead of
  try-then-fallback. −1 to −2 RTTs.
- **Fold `users_are_blocked` into the member query** rather than looping per member. Today
  `_BLOCKABLE_KINDS` is only 2-person DMs so N=1, but it is an N+1 shape that will bite if group
  blocking is ever added. −0 RTTs now, removes a latent cliff.

**P3 — the structural win. Takes the send path from ~11 round trips to 2.**

- **Cache the authorization decision per `(Connection, conversation)` at subscribe time**, and
  validate sends against that cache instead of re-reading. `conversation.subscribe` already loads and
  caches the member list for typing fan-out ("no DB hit per keystroke") — **the pattern exists; it is
  simply not applied to `message.send`.** Extend the cached entry to hold the resolved
  `Conversation`, the member list with mute flags, and the account-OK flag.
- **Invalidate it from the control-event plane, not by TTL.** `user.suspended`, `member.revoked`,
  `pair.revoked`, and `conversation.revoked` are already published and already handled per
  connection. A revocation therefore reaches the cache actively, which means caching authorization
  here **does not weaken it** — the security property is preserved by push invalidation rather than
  by polling. Add a conservative TTL (say 60 s) purely as a backstop against a missed event.
- Net synchronous path becomes: validate from cache (0 RTT) → `INSERT ... RETURNING` (1) →
  `COMMIT` (1) → ack. **~11 → 2.** That is a 5× cut in the critical path that holds at *any* database
  RTT, and it is pure design improvement — no new infrastructure, no protocol change, no weakening of
  authorization or of persist-before-publish.
- Requires care on one point: the cache must be keyed per connection (not per user), dropped on
  `conversation.unsubscribe` and on disconnect, and must never be consulted for a conversation the
  connection has not subscribed to — a send to an unsubscribed conversation must still take the full
  read path.

**Also worth fixing while in here.** `persist_message_idempotent`'s `IntegrityError` branch calls
`await db.rollback()` ([messages/service.py:222-264](../../backend/app/features/messages/service.py#L222-L264)),
which also discards any uncommitted `ensure_dm_conversation` work from the same request. A retry of
the very first message in a brand-new DM can therefore roll back the conversation provisioning.
Worth a regression test; P3 removes the interaction entirely by taking provisioning out of the send
path.

#### Explicitly do not

- **Do not add `--workers`.** With `REDIS_URL` unset it breaks realtime fan-out
  ([manager.py:107-111](../../backend/app/features/realtime/manager.py#L107-L111)), the push presence
  check ([runtime.py:236-264](../../backend/app/features/realtime/runtime.py#L236-L264)), and attendance
  QR check-in ([challenges.py:33-55](../../backend/app/features/attendance/challenges.py#L33-L55)).
  `architecture_review/DECISION_LOG.md:19` fixes the order: Redis first, then workers.
- **Do not add Redis for this.** Nothing in the RTT budget above is fan-out cost; Redis would not
  remove a single one of the 11 round trips.
- **Do not replace the WS protocol or the send ladder.** The idempotency, requeue, and half-open
  detection are the reason P1's transport race is safe in the first place.
- **Do not ack before commit** to shorten the path.

#### Instrumentation to add (prerequisite for the decision tree)

- **Client:** dispatch → ack duration, tagged with transport (`ws_ack` vs `rest_201`), socket status
  at dispatch, and whether it was outbox-queued. Also `connect → auth.ok` duration on resume.
- **Server:** per-send wall time inside `_on_send`, split into authorization reads vs insert+commit,
  plus a count of queries executed. The `X-Request-ID` middleware
  ([request_context.py](../../backend/app/shared/request_context.py)) already gives correlation for the
  REST path; the WS path needs the equivalent on the frame's `request_id`.
- **Database:** confirm the Supabase region and measure actual RTT from the API instance. One
  `SELECT 1` timing loop settles which column of the cost table above applies.

### #13 Notifications page slow to load — **Partially confirmed; queries are fine**

**Exists.** The backend query is already good: one statement, two LEFT OUTER JOINs, no N+1, `limit`
capped at 100 ([notifications/service.py:82-95](../../backend/app/features/notifications/service.py#L82-L95)).
The payload is small and structured (no pre-rendered text, no message bodies)
([schema.py:24-37](../../backend/app/features/notifications/schema.py#L24-L37)).

**Findings, in order of real impact.**

1. **S2 dominates.** A cold start is 30–60 s; no index will help that.
2. **`notificationsListProvider` is `FutureProvider.autoDispose` with nothing keeping it alive**
   ([notifications_provider.dart:85-90](../../mobile/lib/features/notifications/providers/notifications_provider.dart#L85-L90)).
   Every open of the inbox is a cold fetch behind a skeleton — no cached first paint, ever.
3. **Missing indexes.** The migration
   ([e1f2a3b4c5d6_add_notifications.py:33-35](../../backend/alembic/versions/e1f2a3b4c5d6_add_notifications.py#L33-L35))
   creates three *single-column* indexes and nothing since has touched the table. There is **no
   composite `(user_id, created_at DESC)`** for the list query and **no partial index on
   `read_at IS NULL`** for the unread count — even though the messages table has exactly that
   pattern ([d4e5f6a7b8c9_add_unread_index.py:20-26](../../backend/alembic/versions/d4e5f6a7b8c9_add_unread_index.py#L20-L26)).
   At beta volumes this is not the cause, but it is the right shape and cheap.
4. **No pagination.** `limit` only — no cursor, no `has_more`
   ([router.py:24](../../backend/app/features/notifications/router.py#L24)). There is no way to page past
   the newest 100 rows, ever.
5. **Refetch per push.** `_onEvent` calls `ref.invalidate(notificationsListProvider)` on **every**
   inbound notification ([:66-71](../../mobile/lib/features/notifications/providers/notifications_provider.dart#L66-L71)).
   With the inbox open, ten notifications means ten full `GET /notifications`.
6. **Ordering has no tiebreaker** (`created_at DESC` alone), so rows sharing a timestamp — which is
   the norm for the attendance fan-out, which inserts one row per member in a single commit
   ([attendance/notifications.py:72-75](../../backend/app/features/attendance/notifications.py#L72-L75)) —
   come back in nondeterministic order across calls. This will produce visibly jumping rows once
   pagination lands.

**Fix.** Add the composite and partial indexes; add `(created_at DESC, id DESC)` ordering and keyset
pagination mirroring `list_thread`
([messages/service.py:267-301](../../backend/app/features/messages/service.py#L267-L301)); make the list
provider `keepAlive` with stale-while-revalidate (render cached rows immediately, refresh behind
them); on a live event **insert the new row locally** from the WS payload — which already carries the
full serialized notification ([ws_protocol.dart](../../mobile/lib/core/realtime/ws_protocol.dart)) —
instead of refetching the page.

---

### #14 Read/unread state not visually clear — **Confirmed (code). Unread styling is unreachable.**

**Exists.** The unread chrome is fully implemented — tinted tile background
([notifications_screen.dart:118](../../mobile/lib/features/notifications/screens/notifications_screen.dart#L118)),
bold title ([:129](../../mobile/lib/features/notifications/screens/notifications_screen.dart#L129)), and a
blue dot ([:141-147](../../mobile/lib/features/notifications/screens/notifications_screen.dart#L141-L147)).

**Root cause — one line.** [:68](../../mobile/lib/features/notifications/screens/notifications_screen.dart#L68)
passes `treatAsRead: true` for **every** tile, and
[:115](../../mobile/lib/features/notifications/screens/notifications_screen.dart#L115) computes
`final unread = !treatAsRead && !notification.read;` → **always `false`**. So on the only screen that
lists notifications, unread styling is structurally unreachable. The comment at
[:66-67](../../mobile/lib/features/notifications/screens/notifications_screen.dart#L66-L67) explains why:
it was a workaround for a **real race** — `markAllRead()` and the list refetch run concurrently
(`initState` post-frame at [:27-29](../../mobile/lib/features/notifications/screens/notifications_screen.dart#L27-L29)),
so rows can come back already `read: true` and the styling would flash off.

**The product model is also part of the problem.** Opening the inbox marks **everything** read
server-side (`POST /notifications/read` → `mark_all_read`
([service.py:127-133](../../backend/app/features/notifications/service.py#L127-L133))). There is **no
per-notification read endpoint**. So even with styling restored, the state is destroyed on entry.

**Three sources of truth exist** for notification read state: `notifications.read_at`, the per-row
`read` bool in the payload, and the `notificationCountProvider` integer — with the row flag currently
discarded.

**Expected.** Unread rows are visually distinct on entry and **stay** distinct for that viewing
session. Opening an individual notification marks that one read, removes its styling, and decrements
the counter by one. Every representation stays consistent.

**Design.**

1. **Snapshot-on-entry.** On mount, capture the set of unread ids *before* marking anything read, and
   render styling from the snapshot. This kills the race the `treatAsRead` hack was working around
   **and** gives the user time to perceive what was new — the two goals are compatible.
2. **Add `POST /notifications/{id}/read`** and call it on row tap; decrement the counter by one
   locally, then reconcile from `unread-count`.
3. **Keep mark-all-read, but move it off mount** — a "Mark all read" action in the app bar, or a
   mark-all on *leaving* the screen. Marking everything read simply because the screen mounted is
   what makes the state unobservable.
4. Collapse to **one** client source of truth: the counter notifier owns the number, the row flag
   comes from the server, and the snapshot governs styling. Reconcile on `reconnected` and
   `AppLifecycleState.resumed` — the machinery already exists
   ([:41-44,92-99](../../mobile/lib/features/notifications/providers/notifications_provider.dart#L41-L44)).

**Edge cases.** Two devices: device A reads, device B's counter corrects on resume/reconnect (same
deferred trade-off already documented for messages in
`docs/features/notifications/unread_counts.md` §7). A notification arriving *while* the inbox is open
must appear unread even though the screen already marked everything read — the snapshot approach
handles this naturally. `markAllRead` failing: the optimistic `state = 0` must be reconciled, not
left at zero.

**Accessibility.** Unread must not be signalled by **colour alone** (the tinted background plus a
blue dot are both colour). Add the state to the semantics label ("Unread: …") and keep the bold
weight as a non-colour cue.

**Tests.** Extend [notification_count_provider_test.dart](../../mobile/test/features/notifications/notification_count_provider_test.dart)
and add a widget test: three unread → three styled rows on entry; tap one → that row unstyles and
the counter drops by exactly one; the other two stay styled.

---

### #15 Notifications UX needs a broader review — **Confirmed (design)**

**Exists.** [notifications_screen.dart](../../mobile/lib/features/notifications/screens/notifications_screen.dart)
is a flat `ListView` of `ListTile`s with 12 hard-coded type icons
([:178-191](../../mobile/lib/features/notifications/screens/notifications_screen.dart#L178-L191)), a pinned
"Connection requests" row ([:81-104](../../mobile/lib/features/notifications/screens/notifications_screen.dart#L81-L104)),
relative timestamps, three skeleton rows for loading, a local `_Message` widget for both empty and
error (rather than the shared `AppEmptyState`/`AppErrorState`), and no grouping, no sections, no
pagination.

**Gaps found beyond the report.**

- **Message and attendance notifications never reach the inbox as rich rows.** The generic push
  payload carries **no id** (`{'type':'notification','notif_type':...}`,
  [push.py:149](../../backend/app/features/notifications/push.py#L149)), so tapping can only open the
  inbox. Attendance rows are inserted with **no `session_id`, no `group_id`, no `actor_id`**
  ([attendance/notifications.py:72-75](../../backend/app/features/attendance/notifications.py#L72-L75)) —
  so the row cannot deep-link to its own session.
- **Live and fetched timestamps disagree.** `_publish_live` computes `created_at` in Python
  ([attendance/notifications.py:90-104](../../backend/app/features/attendance/notifications.py#L90-L104))
  rather than reading the DB value, so the WS frame's timestamp differs from what
  `GET /notifications` later returns for the same row.
- The attendance fan-out inserts in-app rows **without** the `is_active` / `status` / `deleted_at`
  filters it applies to device tokens ([:37-50](../../backend/app/features/attendance/notifications.py#L37-L50))
  — deactivated users get inbox rows.
- `AvatarWidget(cacheScope: notification.actorName)`
  ([notifications_screen.dart:120](../../mobile/lib/features/notifications/screens/notifications_screen.dart#L120))
  scopes by display **name** instead of actor id.

**Design.** Add `session_id` / target ids to notification rows and payloads so every row deep-links;
read `created_at` from the DB for the live frame; apply the same account filters to inbox inserts;
group by day (Today / Yesterday / Earlier) with sticky headers; adopt the shared `AppEmptyState` /
`AppErrorState` instead of the local `_Message`; add keyset pagination (from #13); absolute time on
long-press or in the detail; and add the unread treatment from #14.

---

### #16 Keyboard/focus behaviour — **Confirmed (code). Root cause found.**

**Exists.** `DismissKeyboardOnTap`
([dismiss_keyboard.dart:12-26](../../mobile/lib/shared/widgets/dismiss_keyboard.dart#L12-L26)) is a correct,
well-reasoned widget using `HitTestBehavior.translucent` so inner taps still win. It is used in
**exactly 2 places**: [chat_screen_body.dart:68](../../mobile/lib/features/messages/widgets/chat_screen_body.dart#L68)
and [login_screen.dart:81](../../mobile/lib/features/auth/screens/login_screen.dart#L81).

**The measurements that explain every reported symptom:**

- **24 files contain a `TextField`/`TextFormField`. 2 of them dismiss the keyboard on tap.**
- **`unfocus`, `FocusScope`, and `primaryFocus` appear ZERO times outside `dismiss_keyboard.dart`.**
  There is no unfocus on navigation, no unfocus on route change, no `NavigatorObserver`, and nothing
  in `app_router.dart` or `nav_shell.dart` touches focus.
- **`FocusNode`, `requestFocus`, and `resizeToAvoidBottomInset` appear ZERO times** in `mobile/lib`.
  So the `TextInputAction.next` keys wired across the auth screens have **no programmatic target** —
  they rely entirely on default `FocusScope` traversal.
- `autofocus: true` at 2 sites:
  [create_group_sheet.dart:127](../../mobile/lib/features/groups/widgets/create_group_sheet.dart#L127) and
  [onboarding_shared_widgets.dart:139](../../mobile/lib/features/onboarding/widgets/onboarding_shared_widgets.dart#L139).

**Root cause of "keyboard remains after onboarding / appears on the dashboard".** Onboarding does
not navigate — it **completes via a router redirect**. `_finishSetup` calls `refreshProfile()`
([student_onboarding_screen.dart:137-161](../../mobile/lib/features/onboarding/screens/student_onboarding_screen.dart#L137-L161)),
which changes `authNotifierProvider`, which fires `refreshListenable`, and the redirect at
[app_router.dart:153-155](../../mobile/lib/core/router/app_router.dart#L153-L155) swaps `/onboarding` for
`/home`. **A redirect-driven route swap does not dismiss the keyboard**, and nothing in the app calls
`unfocus()`. If any onboarding field holds focus when the student taps Finish — the bio field
typically does — the keyboard **persists onto the dashboard**, over a screen with no input at all.
That is the reported symptom exactly, and it explains why it looks like the dashboard "inherits
stale keyboard state".

**Design — systematic, not per-screen patches.**

1. **Unfocus on every route change.** Add a `NavigatorObserver` (or a `GoRouter` redirect-side hook)
   that calls `FocusManager.instance.primaryFocus?.unfocus()` on push, pop, **and** replace. This
   single change fixes the onboarding→dashboard case and every future one, including redirect-driven
   swaps that a per-screen `dispose()` cannot catch.
2. **App-level tap-to-dismiss.** Move `DismissKeyboardOnTap` into the `MaterialApp.router` builder in
   [main.dart:56-59](../../mobile/lib/main.dart#L56-L59), beside `AppConnectivityChrome`, instead of
   wrapping 24 screens. `HitTestBehavior.translucent` means it cannot steal taps from interactive
   children, so app-wide is safe — and it is strictly better than the current 2-of-24 coverage.
   Remove the two now-redundant per-screen wrappers.
3. ~~**Explicit `FocusNode` chains on multi-field forms.**~~ **Corrected during implementation —
   not needed.** This review claimed the `TextInputAction.next` keys had "no programmatic target".
   They do: Flutter's `EditableText` calls `widget.focusNode.nextFocus()` for
   `TextInputAction.next` (and unfocuses for `.done`), resolving through the ambient focus
   traversal order. Adding explicit nodes would have been pure churn with no behaviour change, so
   it was deliberately skipped. What *was* missing is item 4 below — fields that set no
   `textInputAction` at all, whose return key genuinely does nothing.
4. **Set `textInputAction` where it is missing** — `create_activity_screen` (4 fields, whose `_Field`
   at [activity_form_fields.dart:102-133](../../mobile/lib/features/activities/widgets/activity_form_fields.dart#L102-L133)
   has no such parameter), `compose_campus_post_screen`, `edit_profile_screen`, onboarding.
5. **Chat input:** with `maxLines: 4`
   ([chat_input.dart:32-50](../../mobile/lib/features/messages/widgets/chat_input.dart#L32-L50)) the soft
   keyboard shows a newline key, so `onSubmitted` (send-on-enter) is effectively unreachable on most
   keyboards. Decide deliberately: either keep multiline and drop the dead `onSubmitted`, or add an
   explicit send action. Also decide whether focus is retained after send (currently OS default).
6. Dispose the leaked `TextEditingController` created inside `_promptForCustom`
   ([onboarding_shared_widgets.dart:131](../../mobile/lib/features/onboarding/widgets/onboarding_shared_widgets.dart#L131)).

**Cross-platform.** iOS and Android differ materially here and both need device testing: iOS keeps
the keyboard across a `pushReplacement` more readily; Android's `windowSoftInputMode` interacts with
`resizeToAvoidBottomInset` (never set in this app, so every `Scaffold` uses the default `true`);
iOS `isLimited`-style permission and keyboard-accessory-bar heights differ. Test on a physical device
of each, not just simulators.

**Tests.** Extend [dismiss_keyboard_test.dart](../../mobile/test/shared/widgets/dismiss_keyboard_test.dart)
for the app-level wrapper; add a widget test asserting focus is cleared across a redirect-driven
route change (the onboarding→home case specifically); add form-traversal tests on the auth screens.

---

### #17 Excessive loading/refetching — **Confirmed (code)**

**Exists.** See **S4**. Specifics for the reported profile-image case:

- **No disk image cache.** `Image.network` is RAM-only, so **every cold app start re-downloads every
  avatar.**
- **The `loadingBuilder` shows the grey person silhouette while loading**
  ([avatar_widget.dart:38-41](../../mobile/lib/core/widgets/avatar_widget.dart#L38-L41)) — so the visible
  behaviour is *silhouette → face*, on every screen, which is precisely "the same unchanged profile
  image appears to reload repeatedly".
- The backend is **not** at fault: avatar URLs are **stable and cacheable**. The `?v=<ts>` is stamped
  once at upload and persisted in the DB column
  ([storage.py:44-46](../../backend/app/shared/storage.py#L44-L46)), not regenerated per request, and paths
  are deterministic (`profiles/{user_id}/avatar.jpg`). The only weak point is
  `cache-control: 3600` — with a versioned URL that should be long-lived/immutable.
- The comment at [avatar_widget.dart:32-34](../../mobile/lib/core/widgets/avatar_widget.dart#L32-L34)
  conflates two caches: the `ValueKey` rebuilds the **widget**; it does not bust the `ImageProvider`
  cache (keyed by URL + scale). The `?v=` is what actually busts it. Worth correcting so the next
  reader doesn't rely on the key.

**Design — a caching policy, not a package drop-in.**

| Data | Policy | Rationale |
|---|---|---|
| Avatars, group avatars, activity banners | **Disk cache, long TTL** (`cached_network_image`) | URLs are already content-versioned via `?v=`; raise object `Cache-Control` to `max-age=31536000, immutable` |
| Scholar headshots/résumés | **Never cache** | 300 s signed URLs from a private bucket, deliberately uncacheable ([storage.py:69-72](../../backend/app/shared/storage.py#L69-L72)) |
| Policy documents | Already `keepAlive` — correct ([policies_provider.dart:36](../../mobile/lib/features/policies/providers/policies_provider.dart#L36)) | Kilobytes of text that don't change between launches |
| Profile, threads, connections, activities, discovery | `keepAlive` + **stale-while-revalidate** | Already non-`autoDispose`; add cached-first-paint semantics |
| Notifications list, groups lists, directory | Convert `autoDispose` → `keepAlive` + SWR | These are the visible skeleton flashes |
| Announcements first page | **Keep `autoDispose`** | [campus_hub_provider.dart:194](../../mobile/lib/features/campus_hub/providers/campus_hub_provider.dart#L194) documents the deliberate choice: re-opening should show a fresh first page |
| Attendance active session, QR challenge, unread counts | **Never cache** | Correctness depends on freshness |
| Message history | Already cached to disk — correct | [chat_message_cache.dart](../../mobile/lib/features/messages/data/chat_message_cache.dart) |

Concretely:

1. Add `cached_network_image`; replace all 11 `Image.network` sites; give `AvatarWidget` a
   **skeleton/initials** placeholder instead of the silhouette so a load reads as "loading", not
   "no photo".
2. Raise the storage object `Cache-Control` for versioned public images.
3. Convert the identified `autoDispose` providers to `keepAlive` and add a shared SWR helper: emit
   cached data immediately, refresh in the background, and only show a skeleton when there is
   nothing cached.
4. **Fix the shotgun invalidation.** Replace the 4-invalidate fan-outs (e.g.
   [pending_invites.dart:44-47](../../mobile/lib/features/groups/widgets/pending_invites.dart#L44-L47)) with
   mutation-driven targeted updates; the codebase already does this well in places
   (`_updateOne`, prepend-on-create, remove-on-cancel in
   [activities_provider.dart:166-211](../../mobile/lib/features/activities/providers/activities_provider.dart#L166-L211);
   the avatar splice in [profile_provider.dart:264-267](../../mobile/lib/features/profile/providers/profile_provider.dart#L264-L267)) —
   extend that pattern rather than invalidating.
5. **Add request dedup** for identical concurrent GETs — the single-flight pattern already exists for
   token refresh ([api_client.dart:123-125](../../mobile/lib/core/api/api_client.dart#L123-L125)).
6. Fix `activitiesNotifierProvider`, which `ref.watch`es the filter
   ([activities_provider.dart:115-131](../../mobile/lib/features/activities/providers/activities_provider.dart#L115-L131))
   and therefore **refires `GET /activities` on every filter-chip tap** with no per-filter memoization.
7. Consider `StatefulShellRoute` so each tab keeps its own navigator and scroll position — this is
   what removes the "everything reloads when I switch tabs" feeling at the root. Evaluate against the
   `'!_debugLocked'` history documented at
   [app_router.dart:196-211](../../mobile/lib/core/router/app_router.dart#L196-L211).

**Where caching would be wrong.** Attendance session state, QR challenges, unread counts, suspension
status, signed scholar URLs, and the policy-acceptance gate — all correctness-critical and
deliberately excluded above.

---

### #18 Dashboard needs a high-fidelity polish pass — **Confirmed (design)**

**Exists.** [campus_hub_screen.dart](../../mobile/lib/features/campus_hub/screens/campus_hub_screen.dart)
composes 12 sections in order via 7 `part` files: greeting header, Blueprint card, attendance card,
spotlight carousel, quick actions, publisher CTA, urgent banner, latest updates, then (students only)
upcoming activities and suggested connections.

**The real obstacle is that there is no design system to polish against.**
[app_theme.dart](../../mobile/lib/core/theme/app_theme.dart) (119 lines) is the entire system: **12 colour
constants, no typography scale, no spacing constants, no radius constants.** Component themes
hardcode 7 font sizes; every screen then calls `GoogleFonts.dmSans(fontSize: N)` inline. Sizes
observed in the wild: 10, 11, 12, 12.5, 13, 14, 14.5, 15, 15.5, 16, 17, 18, 22 — including
non-integer one-offs. Radii used ad hoc: 10, 11, 12, 14, 16, 20, 24, 35, 48. `Theme.of(context).textTheme`
is used **nowhere** in feature code. There is one card shadow, and it is a private constant in one
file. Light mode only — no `darkTheme`, no `themeMode`.

**Loading vocabulary is split down the middle.** `app_skeleton.dart` offers 9 skeleton widgets and is
used in **10 files**; a raw `CircularProgressIndicator` appears in **43 files**. Many are legitimate
button spinners, but a dozen are full-section loaders where a skeleton already exists. Result:
**Campus Hub sub-pages spin while Activities/Groups/Connections/Messages/Profile skeleton** — two
loading languages in one app. Empty and error states are similarly split: `AppErrorState` is used in
18 files, but `notifications_screen`, `groups_panel`, and `group_detail_screen` each define their own
local equivalents.

**Design — tokens first, then polish.**

1. Extract `AppTypography` (a named scale: display/title/heading/body/label/caption with defined
   size+weight+lineHeight), `AppSpacing` (4/8/12/16/20/24), `AppRadii`, and `AppShadows` into
   `mobile/lib/core/theme/`. Snap every observed value to the nearest token — including the 12.5 /
   14.5 / 15.5 one-offs.
2. Populate `ThemeData.textTheme` properly and migrate feature code to `Theme.of(context).textTheme`,
   so a future type change is one edit.
3. **Standardise loading:** skeletons for content, spinners only for in-button/in-progress actions.
   Replace the dozen full-section `CircularProgressIndicator`s with the existing skeletons.
4. **Standardise empty/error:** delete the local `_Message`, `_PanelMessage`, `_ErrorRetry`, and
   `_EmptyState` duplicates in favour of `AppEmptyState`/`AppErrorState`.
5. Fix the dashboard specifically: consistent 20 px page gutters and section rhythm (currently
   `fromLTRB(20,4,20,8)` vs `(20,12,20,4)` between adjacent cards); align the section headers; and
   reduce visual competition between the Blueprint prompt (dark navy `0xFF1B3A5C`) and the attendance
   card (`AppColors.primary`) when both render at once, which is exactly the case for the Honors
   students this review is about.
6. **Pull-to-refresh currently misses three of its own sections** —
   [campus_hub_screen.dart:74-78](../../mobile/lib/features/campus_hub/screens/campus_hub_screen.dart#L74-L78)
   does not refresh `activitiesNotifierProvider`, `discoveryNotifierProvider`, or
   `myProfileNotifierProvider`, so sections 1, 9, and 11 stay stale. Add them (plus the two from S1).
7. **Preserve** what works: the `part`-file composition, the role-gated sections, the `?v=`-versioned
   avatar URLs, the `MediaQuery.withClampedTextScaling(1.4)` guard in
   [main.dart:56-58](../../mobile/lib/main.dart#L56-L58), and the existing a11y helpers in
   [a11y.dart](../../mobile/lib/shared/widgets/a11y.dart).

**Accessibility findings to fold in.** `AppSkeletonBox` is a **static** gradient with no shimmer and
no `Semantics` — screen readers announce nothing during load. `NavShell` hardcodes
`Semantics(selected: false)` for **every** tab
([nav_shell.dart:94-99](../../mobile/lib/shared/widgets/nav_shell.dart#L94-L99)), so a screen-reader user
is never told which tab is current. Contrast-check `textMuted` (`0xFF6B7280`) on
`background` (`0xFFF6F9FB`) at the 10–12 px sizes used for timestamps and captions.

---

### #19 Groups are hard to discover — **Confirmed (design), with a correction to the report**

**Correction.** Groups are **not** in Connections. `GroupsPanel` has exactly **one** consumer: the
**third segmented tab of the Discovery screen**
([discovery_screen.dart:35,128](../../mobile/lib/features/discovery/screens/discovery_screen.dart#L35)),
whose header reads **"Connect"** — which is why testers call it Connections.
`/connections` ([connections_screen.dart](../../mobile/lib/features/connections/screens/connections_screen.dart))
is a separate top-level pushed screen for **connection requests only**, with no group surface at all.
There is no `/groups` list route and no Groups tab.

**A harder bug found.** [discovery_screen.dart:108-115](../../mobile/lib/features/discovery/screens/discovery_screen.dart#L108-L115)
short-circuits any non-student role to `StaffStudentDirectory`, bypassing the segment tabs entirely.
**Staff accounts therefore cannot reach Groups at all** — even though the backend deliberately opens
groups to staff (`require_email_confirmed_user`, whose docstring at
[dependencies.py:114-123](../../backend/app/dependencies.py#L114-L123) says groups are "deliberately open
to staff as well as students"). Combined with #7's email-domain role inference, an Honors student on
an `@livingstone.edu` address loses Groups too.

**Design (confirmed decision: move Groups into Messages).**

1. Restructure `/messages` as the communication hub with a `Chats | Groups` segmented control,
   reusing the segment pattern already proven in `discovery_screen`.
2. **Chats** = the existing thread list (`_ThreadCard`), DMs and group conversations you are in.
   **Groups** = `PendingInvitesSection` + `YourGroupsSection` + search + category chips + discover +
   "Create Group" — i.e. the existing `GroupsPanel`, moved, not rewritten.
3. Remove the Groups tab from Discovery; keep `?tab=groups` as a redirect to the new location for one
   release so existing deep links resolve.
4. **This fixes staff access as a side effect** — Messages is not role-gated.
5. Keep `/groups/:groupId` (`GroupDetailScreen`) top level as it is.
6. Because #2 moves chat *out* of the shell, `/messages` stays a clean top-level tab hosting only
   list-like content — the two changes compose well and should ship together.

**Dependencies.** Do #2 (chat out of shell) first, then #19; doing #19 first means touching the same
route table twice. #17's `autoDispose` → `keepAlive` conversion matters here: the Groups panel fires
3 requests per visit today, and moving it into a tab that users hit constantly makes that worse if
not fixed first.

**Tests.** Navigation test for the `Chats | Groups` switch; a test asserting a **staff** account can
reach Groups; a redirect test for `/discover?tab=groups`.

---

### #20 Connections page feels crowded — **Partially confirmed**

**Exists.** `features/connections/` is 9 files / 1028 lines and is **already a focused
requests-only screen**: header (back, logo, "Connection Requests" + "Manage who you connect with",
refresh), an Incoming/Outgoing tab bar with count badges, and a `TabBarView` of request cards
([connections_screen.dart:48-83](../../mobile/lib/features/connections/screens/connections_screen.dart#L48-L83)).
It has `AppListSkeleton` loading, a retry error state, and per-tab empty states with good copy.

**Verdict.** Because groups are **not** here (#19), moving group functionality out of this page
cannot simplify it — the report's premise does not hold for `/connections`. **The crowded screen the
testers mean is almost certainly the Discovery/"Connect" screen**, which stacks: an
`AppShellHeader` with title + subtitle + two trailing icon buttons, three segment tabs, a search
field, a filter-chip row, and then — inside the Groups tab — pending invites, your groups, another
search field, another chip row, an "All Groups" heading with a Create action, and the list. That is
four levels of navigation chrome before content.

**Design.** Treat #20 as *"declutter Discovery"*, and let #19 do most of the work by removing the
Groups tab from it entirely. Then:

- Reduce Discovery to two segments (Students | Study Partners) with one search field and one chip row.
- Move the notification bell to one consistent location — it is currently mounted in **three**
  places ([campus_home_header.dart:22,75](../../mobile/lib/features/campus_hub/widgets/campus_home_header.dart#L22),
  [discovery_screen.dart:167](../../mobile/lib/features/discovery/screens/discovery_screen.dart#L167),
  [activities_header.dart:11](../../mobile/lib/features/activities/widgets/activities_header.dart#L11)).
- Small fix on `/connections`: the tab bar renders `SizedBox.shrink()` for **both** loading and error
  ([connections_screen.dart:54-62](../../mobile/lib/features/connections/screens/connections_screen.dart#L54-L62)),
  so it pops in after load — a layout jump. Render it disabled instead.
- Apply the #18 typography/spacing tokens.

---

### #21 Clearer sending/delivery/read states — **Partially confirmed**

**Exists.** Three of the four states are implemented and the plumbing is strong.
`MessageStatus { sending, sent, failed }`
([messages_provider.dart:62](../../mobile/lib/features/messages/providers/messages_provider.dart#L62))
renders as clock / single check / error+Retry
([chat_bubble.dart:201-227](../../mobile/lib/features/messages/widgets/chat_bubble.dart#L201-L227)), and
read renders as a coloured double check. Offline, reconnection, retries, ordering, and idempotency
are already handled well (see #12). `ConversationMember.last_read_message_id`
([messaging.py:50-52](../../backend/app/models/messaging.py#L50-L52)) is a proper monotonic per-member read
boundary, which is what makes group read state expressible at all.

**The gap is Delivered.** `delivered_at` does **not exist** anywhere in `backend/app` — no column, no
frame, no state. There is nothing for the client to source a third tick from.

**Design — extend the existing boundary pattern rather than adding a table.**

*Schema* — mirror the read boundary on the same row:

```
ALTER conversation_members ADD last_delivered_message_id UUID NULL
  REFERENCES messages(id) ON DELETE SET NULL
```

This reuses the proven monotonic-advance semantics of `last_read_message_id`
([realtime/service.py:87-150](../../backend/app/features/realtime/service.py#L87-L150) advances it
only forward) and costs one nullable column instead of a per-message-per-recipient table — which at
group scale would be `messages × members` rows for a purely cosmetic tick.

*Definition of Delivered* — **"the recipient's device has the message"**, which is exactly what the
existing fan-out already knows: `deliver_to_conversation` enqueues to each live connection's outbox
([manager.py:193-218](../../backend/app/features/realtime/manager.py#L193-L218)). Advance the boundary when
a recipient's client **acknowledges receipt**, not when the server enqueues — an enqueue to a
half-open socket is not delivery, and the client already has half-open detection for exactly this
reason. Add a `messages.delivered` inbound frame (client → server, carrying
`through_message_id`), symmetric with the existing `messages.read`
([ws_protocol.dart](../../mobile/lib/core/realtime/ws_protocol.dart)), and a `messages.delivery` outbound
receipt symmetric with `messages.receipt`.

*Client* — add `delivered` to `MessageStatus`; tick vocabulary becomes clock → ✓ → ✓✓ grey →
✓✓ primary. Send a delivered boundary on `message.created` for messages not sent by me. Extend the
chat cache serialization.

**Edge cases.** Multiple devices: delivered = **any** device has it; read = any device read it (both
are already per-member, not per-device, which is the right granularity). Delivery to a muted member
still counts. Offline recipient: the boundary advances when they reconnect and `/sync` returns the
backlog — so "delivered" legitimately arrives long after "sent". Ordering: boundaries advance
monotonically, so an out-of-order ack can never regress a tick. Idempotency: re-sending the same
boundary is a no-op.

**Also fix.** `ReadReceipt` handling currently ignores the frame's `through_message_id` and flips
**all** of my messages read (`markMineRead`,
[chat_send_logic.dart:236-245](../../mobile/lib/features/messages/widgets/chat_send_logic.dart#L236-L245)).
That is wrong for a partial read and will be visibly wrong once delivery ticks exist. Honour the
boundary.

**Group semantics decision to record.** For a group, "read" means *all* members or *any* member?
`Message.read_at` is a single column and cannot express per-member state for groups
([messaging.py:48-49](../../backend/app/models/messaging.py#L48-L49) says so explicitly), so today group
bubbles can **never** show a read tick. Recommend: show ✓✓ when **all** active members have passed
the boundary, and expose per-member detail on long-press (the "read by" list mature apps show).

---

### #22 Do not equate push reachability with presence — **Already correct (backend); presence does not exist**

**Exists — and the codebase already respects the warning.** The relationship is the **inverse** of
the concern: "offline" is derived from `manager.user_socket_count(recipient_id) == 0`
([runtime.py:163,245](../../backend/app/features/realtime/runtime.py#L163)), and device tokens are consulted
**only after** that decision, to find *where* to send
([push.py:105](../../backend/app/features/notifications/push.py#L105)). **Presence gates push; push never
implies presence.** Nothing in the app displays a user as online.

**There is no presence feature at all.** An exhaustive grep finds `last_seen` only as
`Connection.last_seen`, a `time.monotonic()` float used **solely** by the idle reaper
([manager.py:38,267-280](../../backend/app/features/realtime/manager.py#L38)). No presence table, no
persisted `last_active_at` for any user, no presence frame in the protocol. The one honest limitation
is documented in code
([runtime.py:236-241](../../backend/app/features/realtime/runtime.py#L236-L241)): cross-instance presence
is not tracked, so a user connected only on another instance may receive a redundant push —
harmless, and moot on a single instance.

**Recommendation: do not add presence yet, and record why.** "Online" is a high-cost, low-trust
signal — it needs cross-instance state (Redis, which is deliberately deferred), it invites privacy
complaints on a campus social app, and it degrades badly on mobile where the socket is intentionally
torn down on background
([realtime_client.dart:389-407](../../mobile/lib/core/realtime/realtime_client.dart#L389-L407)) — so a user
with the app in their pocket would read as "offline" while being perfectly reachable. Showing
"Online" that is wrong half the time is worse than showing nothing.

**If presence is later wanted, the correct derivation** is a throttled `users.last_active_at`
(`timestamptz`), written on WS auth and at most once per heartbeat interval, plus an explicit
per-user privacy toggle defaulting to **off** — modelled on the existing
`Profile.show_profile_to_verified_only` / `is_hidden` pattern
([core.py:98-100](../../backend/app/models/core.py#L98-L100)). Present it as **"Active recently"** /
**"Active today"** rather than a binary dot, which is both more truthful on mobile and less
surveillance-flavoured. Never derive it from device-token existence. Requires Redis for
cross-instance correctness → strictly after the Redis/worker milestone.

---

### #23 Read receipts should be clearly visible — **Partially confirmed**

**Exists.** Read receipts **do** work end to end: `messages.read` (client → server) advances the
boundary and bulk-sets `Message.read_at`
([realtime/service.py:87-150](../../backend/app/features/realtime/service.py#L87-L150)), then
broadcasts `messages.receipt`; `sendRead()` fires on chat open and on every inbound message
([chat_send_logic.dart:207-215](../../mobile/lib/features/messages/widgets/chat_send_logic.dart#L207-L215));
the bubble renders a primary-coloured `done_all`.

**Two real gaps.**

1. **Visually too weak.** The tick is a **12 px icon in `AppColors.textMuted`/`primary`** at
   [chat_bubble.dart:220-226](../../mobile/lib/features/messages/widgets/chat_bubble.dart#L220-L226), with
   no size or contrast distinction between `check` (sent) and `done_all` (read). At 12 px the
   difference between one and two small ticks is genuinely hard to see — which is exactly what the
   report says.
2. **Absent from the conversation list.** `_ThreadCard`
   ([messages_screen.dart:131-241](../../mobile/lib/features/messages/screens/messages_screen.dart#L131-L241))
   shows an unread bubble and a bold preview for **incoming** unread, plus a live `typing…`
   indicator — but **no outgoing state** when the last message is mine. Mature messengers show the
   tick on the row.

**Design.** Bump the tick to ~14 px with a clearer contrast step; consider distinct colours for
sent/delivered/read rather than grey/grey/primary. Add a leading state glyph to `_ThreadCard`'s
preview line when `latest.senderId == me`, reusing the same `_status` vocabulary so the bubble and the
row can never disagree. `MessageThread` already carries `latestMessage`, so the data is present — no
API change needed.

**Privacy.** Read receipts are currently unconditional and non-optional. Record this as a deliberate
product choice (or add a per-user toggle) — a campus social app where "seen" is always visible and
cannot be disabled is a legitimate user concern, and the reciprocity rule (if you disable receipts
you stop seeing others') is the conventional answer.

**Accessibility.** The tick states are conveyed by icon shape **and** colour with no text
alternative. Add semantics ("Sent", "Delivered", "Read at 4:12 PM") — this is also the cheapest way to
make #21's four states testable.

---

## Part 3 — Additional problems found during the review

Not in any report; recorded because they are real.

**Correctness / data**
1. `AttendanceSession.started_by_id` — `nullable=False` with `ondelete='SET NULL'`
   ([attendance.py:33-35](../../backend/app/models/attendance.py#L33-L35)). Contradictory; raises on real
   user deletion.
2. Attendance sessions **never auto-close without a read** — no scheduler; a lapsed session holds the
   partial unique index and blocks the next session (409). See #7.
3. `ScholarProfessionalProfile._get_or_create` has an **unhandled insert race**
   ([scholars/service.py:66-75](../../backend/app/features/scholars/service.py#L66-L75)) — `user_id` is
   UNIQUE, and two concurrent first-reads raise `IntegrityError`. Contrast the correct handling in
   `ensure_dm_conversation` ([conversations.py:38](../../backend/app/shared/conversations.py#L38)).
4. `ActivityUpdate` naive-vs-aware comparison → unhandled **500**. See #9.
5. `persist_message_idempotent`'s `IntegrityError` rollback discards uncommitted
   `ensure_dm_conversation` work from the same request
   ([messages/service.py:222-264](../../backend/app/features/messages/service.py#L222-L264)).
6. Staff DMs have **no pair-uniqueness constraint** — deliberate check-then-create, documented as
   "an acceptable trade-off" ([conversations.py:91-99](../../backend/app/shared/conversations.py#L91-L99)).
   Concurrent first-messages can create duplicate staff threads. Worth a partial unique index.
7. `unread_summary`'s documented query joins through `matches`
   (`docs/features/notifications/unread_counts.md` §3). Verify group conversations are counted — if
   the live implementation still keys on `match_id`, group unread is silently zero.

**Security / privacy**
8. `_email_verified` **defaults to `True`** when no claim is present
   ([supabase_jwt.py:79-90](../../backend/app/security/supabase_jwt.py#L79-L90)).
9. `verify_iss` is `bool(_issuer())` — an HS256 deployment without `SUPABASE_URL` performs **no
   issuer check** ([supabase_jwt.py:73-76](../../backend/app/security/supabase_jwt.py#L73-L76)).
10. `GET /attendance/honors/status` has **no `Depends` at all**
    ([attendance/router.py:29-31](../../backend/app/features/attendance/router.py#L29-L31)) — the feature
    flag is publicly readable. Low impact, but unintended.
11. `SenderIdMismatch` / `ThirdPartyAuthError` FCM tokens are logged but **never pruned**; only
    `UnregisteredError` is ([push.py:266-270](../../backend/app/features/notifications/push.py#L266-L270)).
12. Attendance is the **only** push path with no presence check — every active Honors student with a
    token gets a push regardless of whether they are connected
    ([admin_router.py:86](../../backend/app/features/attendance/admin_router.py#L86)).

**Infrastructure / config**
13. `HONORS_ATTENDANCE_ENABLED`, `ATTENDANCE_QR_SIGNING_SECRET`, and `REDIS_URL` are **absent from
    [render.yaml](../../render.yaml)**. The first two **are set in the Render dashboard**
    (owner-confirmed, 2026-09-16) and `REDIS_URL` is intentionally unset
    (`architecture_review/DECISION_LOG.md:19`) — so nothing is broken today. The defect is that the
    two live values exist only as dashboard state: unreviewable, undiffable, and lost on a service
    re-create. See #7.
14. `JWT_SECRET_KEY` is still declared in [render.yaml:23](../../render.yaml#L23) but no longer exists in
    `config.py` — dead config.
15. `docs/architecture/realtime-messaging.md` is marked **SUPERSEDED** but still documents Supabase
    Realtime and RLS-based reads as if current. It contradicts
    `architecture_review/PHASE_0_1_STATUS.md`. Retire or clearly quarantine it — an agent or new
    developer reading it will implement the wrong architecture.
16. Push notification tokens are **not chunked at 500** on the message path, unlike the campus-post
    and attendance paths ([push.py:256-278](../../backend/app/features/notifications/push.py#L256-L278)).
    Fine at per-user token counts; inconsistent.
17. `asyncio.create_task` is used fire-and-forget for pushes with **no reference retained**
    ([runtime.py:161-167](../../backend/app/features/realtime/runtime.py#L161-L167)) — the task can be
    garbage-collected mid-flight and its exception is never observed.
18. **A new environment cannot be built from the migration chain.** `alembic upgrade head` against
    an empty database fails:

    ```
    DuplicateColumnError: column "auth_user_id" of relation "users" already exists
    [SQL: ALTER TABLE users ADD COLUMN auth_user_id UUID]
    ```

    The cause is that `3ffad56200ff_initial_schema.py` does not define the schema column by column
    — it calls `Base.metadata.create_all` (lines 26-32), which builds the **current** models,
    `auth_user_id` included. `a1b2c3d4e5f6_add_auth_user_id` then tries to add a column that the
    "initial" migration already created. Every migration after it that ALTERs a table the models
    already describe has the same latent conflict.

    Nothing is broken today: existing environments migrated incrementally, and `render.yaml` runs
    `alembic upgrade head` against an already-provisioned database. What is broken is **rebuilding
    from scratch** — disaster recovery, a new staging environment, and any contributor starting
    from an empty database. It also means `tests/db` (which builds from `create_all`, see
    `tests/db/conftest.py:80`) cannot catch a bad migration, so migrations are effectively
    untested: verify each one against a scratch database that has been stamped at the previous
    head.

    **Addressed in two parts, deliberately split.**

    *Done — risk removed.* The adaptive initial revision had the right instinct and was simply
    never finished: "a fresh database gets the current schema" has to be paired with "and is
    recorded as already at head", or Alembic tries to migrate it forward from the beginning.
    `scripts/bootstrap_db.py` completes that pairing. It inspects the database and either
    `create_all` + `stamp head` (empty) or `upgrade head` (already managed), and **refuses** the
    ambiguous third state — tables present with no `alembic_version` — rather than guessing, since
    either choice is destructive in a different way. Skipping the historical revisions on an empty
    database is correct, not a shortcut: each one either reshapes a table the models already
    describe or backfills rows that do not exist yet. `render.yaml` now runs this single step
    instead of `alembic upgrade head && init_db.py`, which was also the wrong order —
    the migration ran first and failed before `create_all` could build anything.

    `tests/db/test_migrations.py` covers what the rest of the suite structurally cannot: that the
    bootstrap path produces a schema matching the models (via `compare_metadata`), and that the
    newest revision applies **and reverses** without drift. It runs Alembic in a **subprocess** —
    not in-process — because `alembic/env.py` overwrites any caller-supplied URL with
    `settings.database_url`, and `settings` is an `lru_cache`d singleton built at import, so
    setting `os.environ` from inside the test process has no effect. Writing it the obvious way
    stamped and downgraded the local dev database instead of the throwaway one.

    *Outstanding — cleanup.* Squash the chain into a real baseline with explicit DDL, so
    `alembic upgrade head` is conventionally correct from empty. **Sequencing matters:** a baseline
    built from current models includes any migration not yet deployed, so stamping production at it
    would mark changes as applied that are not. Deploy the outstanding revision first, then squash
    in a deliberate window, and record it in `architecture_review/DECISION_LOG.md`.

**Client**
19. No `FirebaseMessaging.onMessage` and no `onBackgroundMessage` handler anywhere. See #8.
20. `NavShell` hardcodes `Semantics(selected: false)` for every tab. See #18.
21. `AppSkeletonBox` has no shimmer and no semantics. See #18.
22. Leaked `TextEditingController` in `_promptForCustom`. See #16.
23. Deep-linked `/activities/:activityId` hard-casts `state.extra as Activity`
    ([app_router.dart:278-283](../../mobile/lib/core/router/app_router.dart#L278-L283)) — a cold deep link
    with no `extra` throws. Same fragility class as `GroupChatArgs`.

---

## Part 4 — Prioritized implementation plan

Dependency-ordered. **Do not reorder across phase boundaries**: later items assume earlier ones.

### Phase 0 — Foundations two phases depend on (do first)

| # | Work | Why first |
|---|---|---|
| 0.1 | **S1 eligibility contract**: `Eligible/NotEligible/Unknown`, remove blanket `catch → false`, add invalidation + resume/reconnect refetch | #6, #7, #8 all reduce to this |
| 0.2 | **S3 auth phase + `/splash`** + pending-deep-link queue | #11 directly; #8's silent link loss; #10 shares the file |
| 0.3 | **Declare the two dashboard-only env vars** in `render.yaml` (`sync: false`); remove dead `JWT_SECRET_KEY` | Drift protection only — both are already set in Render, so nothing is broken today. Zero-risk, no behaviour change; not a prerequisite for #7 |
| 0.4 | **Shared date-format module** with internal `.toLocal()` | #9's structural fix; touched by #13/#15/#21 |

### Phase 1 — Critical bugs (user-visible breakage)

| # | Work | Depends on |
|---|---|---|
| 1.1 | **#9** route the 5 activity sites + the connections site through 0.4; delete duplicate helpers; `AwareDatetime` on request schemas; fix the `ActivityUpdate` 500 | 0.4 |
| 1.2a | **#6 backend** add `is_complete` + `missing_fields` to `ScholarProfessionalProfileRead`; required-field set + thresholds as one constant | — |
| 1.2b | **#6 client** apply 0.1; render from `is_complete`; remove the card from the dashboard when complete; delete the dashboard `_StatusRow`; keep the permanent Profile entry row; guard `entry` against asserting "incomplete" on error | 0.1, **1.2a** |
| 1.3 | **#7** apply 0.1; invalidate `activeAttendanceProvider` from the WS handler; hold the countdown locally (stop the 1 Hz `ref.read`); render checked-in state; add the auto-close sweep | 0.1, 0.3 |
| 1.4 | **#8** typed error codes; carry `session_id`; handle `isLimited`; add `mounted` guards; QR-parse feedback; foreground `onMessage`; fix `openMessageConversation`'s group-vs-DM default | 0.1, 0.2 |
| 1.5 | **#10** stop `signOut()` on unreachable; classify 401 reasons; retry bootstrap with backoff | 0.2 |
| 1.6 | **#14** snapshot-on-entry; `POST /notifications/{id}/read`; move mark-all off mount | — |
| 1.7 | **#16** router-level unfocus + app-level `DismissKeyboardOnTap` | — |

### Phase 2 — Reliability & performance

| # | Work | Depends on |
|---|---|---|
| 2.1 | **Measure** before deciding anything infrastructural (Part 5) | Phase 1 |
| 2.2 | **#17** add `cached_network_image`; replace all 11 sites; skeleton placeholder; raise object `Cache-Control` | — |
| 2.3 | **#17** `autoDispose` → `keepAlive` + SWR helper; request dedup; per-filter memoization; replace shotgun invalidation with targeted updates | 2.2 |
| 2.4 | **#13** composite + partial notification indexes; keyset pagination + `(created_at, id)` ordering; insert-from-WS instead of refetch | 2.3 |
| 2.5 | **#12 P1 (client, free)** race WS+REST instead of a fixed 6 s wait; adaptive ack timeout; show "connecting…"; overlap socket connect with bootstrap | 0.2 |
| 2.6 | **#12 instrumentation** time-to-ack by transport, server-side send-time split, DB RTT probe | 2.1 |
| 2.7 | **#12 P2 (server, mechanical)** `INSERT ... RETURNING` instead of `refresh`; drop the duplicate member read; remove the guaranteed DM conversation-lookup miss; de-loop the block check | 2.6 |
| 2.8 | **#12 P3 (structural)** cache the send authorization per `(Connection, conversation)` at subscribe; invalidate via the existing control-event plane; ~11 → 2 round trips | 2.7 |
| 2.9 | Additional-findings fixes: #1–#7, #11, #17 from Part 3 (incl. the `ensure_dm_conversation` rollback interaction, which 2.8 removes structurally) | — |
| 2.10 | **Only if 2.1/2.6 say so**: provision Redis (`REDIS_URL` on every instance) **then** scale workers — never the reverse. Note Redis removes **none** of #12's 11 round trips | 2.1, 2.6 |
| 2.11a | **Fresh-environment bootstrap + migration tests** — `bootstrap_db.py` inspects and takes the right path; `test_migrations.py` asserts no model/migration drift and that the head revision reverses. Touches no existing revision | — |
| 2.11b | **Squash the chain into a baseline** — cleanup. Only *after* the outstanding revision is deployed, else stamping production marks undeployed changes as applied | 2.11a, a deploy |

> **On 2.5's placement.** 2.5 intentionally has no dependency on 2.1 or 2.6. Racing the transports
> and making the ack timeout adaptive are wins whether the cause turns out to be cold start, the
> round-trip budget, or both — so there is nothing to learn first. 2.7 and 2.8 *do* wait on 2.6,
> because their value depends on how much of the latency is really server-side. See Adopted
> decision 3.

### Phase 3 — Messaging improvements

| # | Work | Depends on |
|---|---|---|
| 3.1 | **#2** chat routes out of the shell (+ legacy redirect) | — |
| 3.2 | **#19** Messages as hub with `Chats \| Groups`; remove the Discovery Groups tab; fixes staff access | 3.1, 2.3 |
| 3.3 | **#1** `ChatDraftStore` | 3.1 |
| 3.4 | **#21** `last_delivered_message_id` + `messages.delivered`/`messages.delivery` frames; honour `through_message_id` in read receipts | — |
| 3.5 | **#23** stronger tick styling + state on the conversation row | 3.4 |
| 3.6 | **#4** reactions: table, endpoints, two frames, aggregate in the page query, UI | 3.4 (protocol version bumped once) |
| 3.7 | **#5** editing: `edited_at` + `message_edits`, `PATCH`, `message.edited` frame, 15-min window, retention runbook step | 3.6 |
| 3.8 | **#22** record the no-presence decision; revisit only after 2.7 | 2.7 |

### Phase 4 — UI/UX polish

| # | Work | Depends on |
|---|---|---|
| 4.1 | **#18** extract `AppTypography`/`AppSpacing`/`AppRadii`/`AppShadows`; populate `textTheme` | — |
| 4.2 | **#18** standardise loading (skeleton vs spinner) and empty/error (delete local duplicates) | 4.1 |
| 4.3 | **#18** dashboard pass: rhythm, alignment, card-colour competition, complete pull-to-refresh | 4.1, 0.1 |
| 4.4 | **#15** notification grouping, deep-linkable rows (needs target ids on rows + payloads), shared states | 1.6, 2.4 |
| 4.5 | **#20** declutter Discovery; single bell location; fix the popping tab bar | 3.2, 4.1 |
| 4.6 | **#3** avatar preview viewer | 4.1, 2.2 |
| 4.7 | A11y sweep: tab `selected`, skeleton semantics, tick semantics, unread not colour-only, contrast audit | 4.1 |

---

## Part 4b — Master checklist (work top to bottom)

Part 4 explains *why* the order is what it is. **This is the list to actually work from.** It is
strictly sequential: anything above a line can be done without anything below it. Every one of the
23 beta reports appears exactly once, so nothing is dropped and nothing is fixed twice.

Notation: **[be]** backend · **[fe]** mobile · **[cfg]** config/ops · **[msr]** measurement ·
**[snap]** will move the OpenAPI snapshot (regenerate deliberately).

### Phase 0 — Foundations (nothing else should start first)

- [x] **0.1** [fe] Eligibility contract: `Eligible` / `NotEligible` / `Unknown`; delete blanket
      `catch → false`; add invalidation + resume/reconnect refetch — *unblocks #6, #7, #8*
- [x] **0.2** [fe] `/splash` + three-state auth phase + pending-deep-link queue — *#11; unblocks #8, #10*
- [x] **0.3** [cfg] Declare `HONORS_ATTENDANCE_ENABLED` + `ATTENDANCE_QR_SIGNING_SECRET` in
      `render.yaml`; remove dead `JWT_SECRET_KEY` — *drift protection only; already set in Render*
- [x] **0.4** [fe] `app_date_format.dart` with `.toLocal()` applied internally, exactly once — *unblocks #9*

### Phase 1 — Critical bugs

- [x] **1.1** [fe][be][snap] **#9 timezone** — route the 5 activity sites + `connections_screen` through
      0.4; delete both duplicate `_formatTimeRange` copies; `AwareDatetime` on request schemas; fix the
      `ActivityUpdate` naive-vs-aware 500
- [x] **1.2a** [be][snap] **#6 completeness** — `is_complete` + `missing_fields` on
      `ScholarProfessionalProfileRead`; required-field set as one constant *(confirm thresholds first)*
- [x] **1.2b** [fe] **#6 card** — render from `is_complete`; **remove from dashboard when complete**;
      delete the dashboard `_StatusRow`; keep the permanent Profile entry row; apply 0.1
- [x] **1.3** [fe][be] **#7 attendance card** — apply 0.1; invalidate `activeAttendanceProvider` from the
      WS `honors_attendance_open` handler; hold the countdown locally; render checked-in state; add the
      session auto-close sweep
- [x] **1.4** [fe][be][snap] **#8 attendance deep link** — typed error codes; carry `session_id`; handle
      `isLimited`/`provisional`; add the two missing `mounted` guards; QR-parse feedback; foreground
      `onMessage` handler; fix `openMessageConversation`'s group-vs-DM default
- [x] **1.5** [fe][be] **#10 session** — stop `signOut()` on unreachable; classify 401 reasons; retry
      bootstrap with backoff
- [x] **1.6** [fe][be][snap] **#14 unread** — snapshot-on-entry; `POST /notifications/{id}/read`; move
      mark-all off mount
- [x] **1.7** [fe] **#16 keyboard** — router-level unfocus on push/pop/replace; app-level
      `DismissKeyboardOnTap` in the `MaterialApp` builder; `FocusNode` chains; dispose the leaked controller

### Phase 2 — Reliability & performance

- [x] **2.0** [cfg] **Co-locate the API with the database** (Part 5 item 2) — was API in Oregon, DB
      in Ohio, ~50–70 ms on every round trip, paid ~6 times on a single message send. **Done:** the
      API now runs in Render's Ohio region, which also halves the NC client's own hop.
      `render.yaml` updated to `region: ohio` so a service re-create cannot silently revert it —
      the region only applies at creation, which is also why the move required deleting the service
      and adding it back rather than an edit. The two Next.js portals stay **Oregon**, declared as
      such: they serve a handful of staff rather than students, and declaring an unmoved service
      `ohio` would make a future re-create relocate it by accident.
      *Not yet measured:* the before/after latency is 2.1, which still needs production access.
- [ ] **2.1** [msr] Run Part 5 items 1–4 and 7 *(items 2, 3 and 5 resolved)* — **unblocked by 2.6
      from the next deploy.** A first capture (`docs/renderlogs.md`, pre-instrumentation) settled
      the *correctness* questions — zero 5xx across 236 requests, admin-portal CORS passing against
      Ohio, `HONORS_ATTENDANCE_ENABLED` set, WebSocket + offline push + stale-token pruning all
      working — but carried no timings, so it answered nothing about latency. Capture again once
      the duration logging is deployed.

- [x] **2.2** [fe] **#17 images** — `cached_network_image` across all 11 sites; skeleton (not silhouette)
      placeholder; raise object `Cache-Control` to immutable
- [x] **2.3** [fe] **#17 data** — `cacheFor` (TTL-bounded `keepAlive`) on the group, directory and
      participant providers; `AsyncValue.cached` so a revalidation no longer replaces content with a
      skeleton; `DedupeGetInterceptor` collapses concurrent identical GETs.
      **Two items deliberately not done:** per-filter memoization of `activitiesNotifierProvider`
      (a different filter is genuinely different data — `cached` rendering fixes the blanking, and
      splitting the notifier from its optimistic `join`/`leave` mutations is a Phase-3-sized
      refactor for no correctness gain), and "replace shotgun invalidation" — on inspection the
      4-way fan-out in `pending_invites.dart` is *correct*: accepting an invite really does change
      invites, my-groups, discovery state and the inbox. The review mislabelled it.
- [x] **2.4** [be][snap] **#13 notifications** — composite `(user_id, created_at DESC)` + partial unread
      index; keyset pagination + `(created_at, id)` ordering; insert-from-WS instead of refetch
- [x] **2.5** [fe] **#12 P1** — race WS+REST instead of a fixed 6 s wait; adaptive ack timeout;
      "connecting…" state; overlap socket connect with bootstrap · *deliberately **not** gated on 2.1*
- [~] **2.6** [msr] **#12 instrumentation** — **HTTP half done.** `RequestIdMiddleware` now logs
      `METHOD /path -> status in N.Nms` to `lc_connect.access`, at WARNING past `SLOW_REQUEST_MS`
      (default 1000) so slow requests are findable by level filter rather than by reading
      everything. The query string is deliberately excluded: a path id makes a request
      diagnosable, a query string can carry a token or a search term someone typed, and these
      lines end up pasted into bug reports. Production logs previously carried method, path and
      status and **no duration**, which is exactly what made 2.1 unanswerable.
      *Still to do:* time-to-ack by transport (WebSocket vs REST) and a DB RTT probe.

- [x] **2.7** [be] **#12 P2** — `eager_defaults` removes the post-commit `refresh`; authorization now
      returns the member list it already read (was queried twice); `resolve_conversation` matches
      both id shapes in one query instead of a guaranteed miss for every DM; the block check is a
      single set-based query. **~11 → ~6 round trips per send.**
- [ ] **2.8** [be] **#12 P3** — cache send authorization per `(Connection, conversation)` at subscribe;
      invalidate via the existing control-event plane. **Now justified by measurement** (Part 5
      item 2): at 50–70 ms RTT the ~4 authorization round trips it removes are worth ~200–280 ms
      per message. Still do it **after** the region decision — co-locating drops the same 4 trips
      to ~8–20 ms total, which may make the security trade not worth making at all.
- [ ] **2.9** [be][fe] Part 3 additional findings 1–7, 11, 17
- [ ] **2.10** [cfg] **Only if 2.1/2.6 justify it**: Redis first, *then* workers — never the reverse
- [x] **2.11a** [be] **Fresh-environment bootstrap + migration tests** (Part 3 finding 18) —
      `scripts/bootstrap_db.py` makes a new environment buildable; `tests/db/test_migrations.py`
      makes migrations tested. No existing revision or production state touched.
- [ ] **2.11b** [be] **Squash the chain into a baseline** — cleanup, not risk reduction. Must come
      **after** the outstanding revision is deployed, or stamping production marks undeployed
      changes as applied. Record in `DECISION_LOG.md`.

### Phase 3 — Messaging

> **Batch 1 is complete and hardened.** Sequenced step by step in
> [`docs/features/messaging/phase3_design.md`](../features/messaging/phase3_design.md) §8, which also
> carries the two prerequisites the review missed (the abuse-budget ban on unknown frames, and the
> unversioned message cache) and every deviation from the design with its reason.
>
> §9 of the same document records the hardening pass over the batch — six real defects, including an
> unbounded unsupported-frame reply path introduced by the batch itself, delivery acknowledgements
> that were quadratic in group size, and a delivered tick that was not durable across a page load.
> §9.8 leaves one decision open: drafts and cached message bodies sit in a directory iOS and Android
> include in cloud backups.

- [x] **3.1** [fe] **#2** chat routes out of the `ShellRoute` + legacy `/messages/:id` redirect —
      conversations are `/chat/:matchId` and `/chat/group/:conversationId`; the ten inline path
      literals across seven features now live in `features/messages/utils/chat_routes.dart`, and
      `appRoutes()` was extracted so the table's *shape* is assertable without an initialised
      Supabase client (`test/core/router/route_table_test.dart`)
- [x] **3.2** [fe] **#19** Messages becomes the hub: `Chats | Groups`; Discovery's Groups tab removed;
      `?tab=groups` redirects — *staff can now reach Groups at all*
- [x] **3.3** [fe] **#1** `ChatDraftStore` — debounced, flushed on `dispose` **and** on `paused`,
      30-day prune, cleared on send. Logout cleared *nothing* before this (drafts or cached message
      bodies); both go now
- [x] **3.4** [be][fe][snap] **#21** `last_delivered_message_id` (migration `f2b3c4d5e6a7`),
      `mark_delivered`, the `messages.delivered` / `messages.delivery` pair, `PROTOCOL_VERSION` → 2 —
      and the read receipt **now honours `through_message_id`**, which it never did: it flipped every
      message of mine to read regardless of the boundary named
- [x] **3.5** [fe] **#23** one shared `OutgoingState` + `MessageStatusIcon` at 14px with real
      contrast steps, used by both the bubble and the conversation row so they cannot disagree;
      group messages get a `GET /messages/{id}/read-by` list on long-press instead of a tick
- [ ] **3.6** [be][fe][snap] **#4** reactions — `message_reactions` table, two endpoints, two frames,
      aggregate in the page query, chip UI *(`PROTOCOL_VERSION` is already at 2 — bump to 3 here, and
      gate the new frames on `RealtimeClient.supportsProtocol`)* — **Batch 2, after TestFlight**
- [ ] **3.7** [be][fe][snap] **#5** editing — `edited_at` + `message_edits`, `PATCH /messages/{id}`,
      `message.edited` frame, 15-min window, retention-runbook step — **Batch 2, after TestFlight**
- [x] **3.8** [doc] **#22** record the no-presence decision — `ADR-009` (presence is not a product
      feature, with the derivation to use if it is ever revisited) and `ADR-010` (read receipts
      unconditional in v1, with the reciprocity rule that matters if a toggle is added).
      Revisit only after 2.10.

### Phase 4 — UI/UX polish

- [x] **4.1** [fe] **#18** extract `AppTypography` / `AppSpacing` / `AppRadii` / `AppShadows`;
      populate `textTheme` — **done.** Four token files in `core/theme/`, and `app_theme.dart` now
      builds every component theme from them (it previously hardcoded seven font sizes and five
      radii). The survey that shaped the scale: 24 font sizes in use including six half-steps,
      15 radii, 12 `BoxShadow` literals with no two agreeing, and
      `Theme.of(context).textTheme` used in **zero** feature files.
      Ten type roles rather than a fashionable five, because the integer sizes cluster into ten
      groups with real jobs (~90 uses each at 13 and 14, 86 at 12, 47 at 11) — collapsing those
      would be redesigning dense surfaces, not tokenising them.
      `test/core/theme/design_tokens_test.dart` is the tripwire: roles stay on the scale, no
      fractional sizes, no two roles share a size, nothing below 10, every role sets a line
      height and carries no colour, and the component themes are actually wired to the tokens
      rather than the tokens being documentation.
      *Call sites are not migrated* — that happens as 4.2/4.3/4.5/4.6/4.7 touch each surface.

- [x] **4.2** [fe] **#18** standardise loading and empty/error — **done.** The review's framing was
      only half right: the local `_EmptyState` classes in messages, connections and activities were
      **already** calling the shared widgets. What was duplicated was the *scroll adapter* around
      them — `ListView` + `AlwaysScrollableScrollPhysics` + a proportional spacer, copied three
      times, and load-bearing (a `RefreshIndicator` over a non-scrollable child cannot be pulled,
      so an empty list could never be refreshed). That is now `AppScrollableEmptyState`.
      The genuine duplicates were elsewhere: `_Message` (notifications), `_PanelMessage` (groups)
      and `_ErrorRetry` (group detail) each hand-rolled a *compact* inline failure because
      `AppErrorState` is a full-screen block — a real need, met once as `AppInlineMessage`.
      Loading: the Campus Hub sub-pages were the only content lists in the app that spun while
      every other list showed placeholders; they use `AppHubPanelSkeleton` now (given a `count`),
      with profile-shaped screens on `AppProfileSkeleton` and the recipient picker on the thread
      skeleton. Action spinners (scan processing, the export modal) are deliberately untouched —
      the rule is skeletons for content, spinners for in-progress actions.

- [x] **4.3** [fe] **#18** dashboard pass — **done.** Three parts, one of them a functional bug
      rather than polish.
      *Pull-to-refresh did not refresh the dashboard.* Three sections were missed: "Upcoming
      activities" and "Suggested connections" read `activitiesNotifierProvider` and
      `discoveryNotifierProvider`, and the greeting header reads the profile. A pull refreshed the
      middle of the screen and left the top and bottom stale — worse than not offering the gesture,
      because it looks like it worked. All nine section providers are refreshed now, and
      `pull_to_refresh_test.dart` asserts each one by name: the failure mode is "a section was
      added and the handler was not updated", which happened three times.
      *Card-colour competition.* The Blueprint prompt was a saturated `#1B3A5C` card with white
      text sitting directly above the attendance card, itself a saturated `AppColors.primary`
      surface with white text — two adjacent dark blue cards, each shouting, neither reading as
      more urgent, which is the same as neither being urgent. It happens precisely for the Honors
      students this review is about. **Emphasis now follows urgency:** attendance is time-bounded
      (a session is open, with a countdown, and missing it cannot be undone), so it keeps the
      saturated treatment; the Blueprint prompt is a standing task with no deadline and becomes a
      quiet tinted card, still branded by its navy icon and title. Contrast measured rather than
      assumed: navy on the tint is 10.36:1 and the subtitle 9.19:1.
      *Vertical rhythm.* Eleven paddings across seven dashboard files used ten different vertical
      values — 0, 2, 4, 6, 8, 10, 12, 18, 24 — of which 2, 6, 10 and 18 were not on any grid. All
      snapped to `AppSpacing`, and the gutter is now the named token rather than a repeated `20`.
      The section header's existing `(24, 12)` turned out to already be the right rhythm, so it
      became the anchor the others were snapped to.

- [ ] **4.4** [be][fe][snap] **#15** notification grouping + deep-linkable rows (needs target ids on rows
      *and* payloads) + shared states
- [x] **4.5** [fe] **#20** declutter Discovery; one bell; fix the popping tab bar — **done**, with
      one finding sharper than the review's.
      *The bell:* the review counted three mountings. The count was the less interesting half — one
      of them was a **different implementation.** Campus Hub had a private `_HomeBell`: a bare
      `IconButton` with a hand-rolled badge, no tooltip and no semantics label. So on the app's
      *landing* screen a screen reader announced nothing about unread notifications, while the
      identical-looking control on Discovery and Activities announced "Notifications, 3 unread".
      All three now use `NotificationsBellButton`. Three mountings are kept deliberately — each is
      a top-level tab, so that is reachability, not clutter; what mattered was that they be the
      same control. `bell_consistency_test.dart` asserts only one widget owns
      `push('/notifications')`.
      *The popping tab bar:* rendered `SizedBox.shrink()` for both loading **and** error, so it
      appeared once the request finished and shoved the list down — a layout jump on every visit,
      and on a slow connection one the user was already reading through. It is always present now,
      with counts filled in when they arrive and no badge until then (a zero would be worse than
      nothing). Pinned by a test comparing its position before and after load.
      *Discovery's chrome:* already halved by 3.2, which removed the Groups segment and with it a
      second search field and a second chip row. What remains is one header, two segments, one
      search and one chip row.

- [x] **4.6** [fe] **#3** avatar preview viewer — **done.** `showAvatarPreview` plus an opt-in
      `previewHeroTag` on `AvatarWidget`: full-screen, Hero-animated from the thumbnail,
      pinch-zoomable to 4x, dismissed by the close button, a tap anywhere, or the system back
      gesture. Tagged on identity (`avatar:<userId>`), never the URL, which changes with every
      upload.
      **Attached at two sites, not twenty**, and the reasoning is the substance of this item:
      the public profile (80px) and the group detail header (88px) — the only large avatars whose
      tap was unused. The review also listed the own profile and the chat header; both were
      wrong on inspection. The own-profile avatar's tap **already opens the image picker** to
      change your photo, advertised by a camera badge, and that is the more useful action; the
      chat header is 38px and sits in a row that navigates. Dense list rows are excluded for the
      same reason — a row's job is to reach the person.
      Scholar headshots are out of reach **by construction**: they never use `AvatarWidget`, so an
      expiring 300-second signed URL cannot be routed into a viewer that outlives it, or into the
      image cache. Noted in the helper's own doc so it stays true.
      Also: no preview when there is no photo — a full-screen silhouette offers nothing, and an
      avatar that opens *sometimes* is worse than one that never does.

- [x] **4.7** [fe] **#18** a11y sweep — **done, and two of the four findings were wrong.**
      *Real:* the skeletons were **silent** — a screen-reader user heard nothing while a screen
      loaded, indistinguishable from an empty screen. Now one announcement per *group*
      (`AppSkeletonSemantics`), not per box, since a list skeleton is twenty boxes. They also
      **shimmer** now, respecting `MediaQuery.disableAnimations`; a static grey block reads as
      content that failed rather than content arriving.
      *Real:* `AppErrorState` and the three hand-rolled inline errors wrapped their Retry button in
      the message's `Semantics`, which announced the message twice **and hid the button** — the one
      control a failed state exists to offer. The live region is on the text alone now.
      *Wrong:* "`NavShell` hardcodes `Semantics(selected: false)`, so a screen-reader user is never
      told which tab is current." Checked by dumping the semantics tree with the original code:
      `BottomNavigationBar` sets the flag itself on the outer `Tab N of M` node, which is what
      assistive technology reads, and it was already correct. The hardcoded value sat on an inner
      node that gets merged away. Passing the real value only stops the code stating something
      false; `nav_shell_connect_badge_test.dart` now guards the behaviour at the level that matters.
      *Wrong:* "contrast-check `textMuted` at 10–12px." Measured, `textMuted` **passes** (4.57:1,
      narrowly) and the **semantic colours** are the failures — `primary` 4.04, `error` 3.56, and
      `green` **2.40**, which fails even the large-text floor while marking "checked in" and
      "Published". `test/core/theme/contrast_test.dart` pins every ratio so none may regress, and
      records the three candidates that pass AA (`#3B77AA`, `#CD3A3A`, `#0B815A`).
      **Open decision:** whether to adopt them — it changes brand colour, so it is not mine to make.


### Coverage check

All 23 reports are accounted for above: #9→1.1 · #6→1.2a/b · #7→1.3 · #8→1.4 · #10→1.5 · #14→1.6 ·
#16→1.7 · #11→0.2 · #17→2.2/2.3 · #13→2.4 · #12→2.5–2.8 · #2→3.1 · #19→3.2 · #1→3.3 · #21→3.4 ·
#23→3.5 · #4→3.6 · #5→3.7 · #22→3.8 · #18→4.1/4.2/4.3/4.7 · #15→4.4 · #20→4.5 · #3→4.6.

---

## Part 5 — Measure before deciding (do not guess)

These are the points where an architectural decision must not be made without data.

1. **Cold-start vs steady-state, separated per stage (blocks #12, #13, 2.10).** Coarse "cold vs
   warm" is not enough — #12 has two independent candidate causes that produce the same symptom.
   Capture p50/p95 for `POST /auth/bootstrap`, `GET /notifications`, `GET /programs/me`, and WS
   `connect → auth.ok`, each split **first-request-after-idle vs warm**; and for sends specifically,
   capture the four series in #12's instrumentation list (client time-to-ack by transport,
   server-side authorization time vs insert+commit time, query count per send). Then read #12's
   decision tree. If cold start dominates, the fix is keeping the instance warm (paid plan or a
   health pinger). If the round-trip budget dominates, the fix is #12 P2/P3. In **neither** case is
   the answer workers, Redis, or more CPU. Render logs plus the existing `X-Request-ID` middleware
   ([request_context.py](../../backend/app/shared/request_context.py)) give most of the REST half already.
2. ~~**Database region and measured RTT.**~~ **RESOLVED 2026-09-17 — and it is the single most
   important finding in this document.**

   **The API and the database are on opposite coasts.** Render runs in `region: oregon`
   (`us-west-2`, [render.yaml:5](../../render.yaml#L5)); the Supabase primary is **East US (Ohio),
   `us-east-2`**, on `t4g.nano` compute. Cross-country RTT is roughly **50–70 ms**, and it is paid
   on *every* round trip of *every* query in the app.

   Applied to #12's cost table, this lands squarely in the bad column. A message send makes ~6
   serial round trips after the reductions in 2.7 (`recheck_account` → `resolve_conversation` →
   `active_members_with_mute` → `is_active_member` → `any_blocked_between` → INSERT → COMMIT),
   so:

   | | round trips | pure network |
   |---|---|---|
   | before 2.7 | ~11 | **550–770 ms** |
   | after 2.7 | ~6 | **300–420 ms** |
   | co-located (2–5 ms RTT) | ~6 | **12–30 ms** |

   That is the report, explained, with no cold start required — and it is why #12's decision tree
   points at the round-trip budget rather than at spin-up.

   **The geography is worse than it looks.** Livingstone College is in Salisbury, North Carolina.
   Today a request goes NC → Oregon (~70 ms) → Ohio (~60 ms) and back. Moving the **API** to
   Render's Ohio region would co-locate it with the database *and* halve the client's own hop, so
   it fixes two legs at once and needs no data migration — a service region cannot be changed in
   place, so it means creating the service in Ohio and cutting over. That is worth more than every
   index, cache, and query change in this document combined, and it should be evaluated before
   any further #12 work.
3. ~~**Role misclassification (blocks #7).**~~ **RESOLVED 2026-09-17 — ruled out.** The query
   returned **no rows**: every active `presidential_scholars` member has `role = 'student'`, so the
   email-domain inference in [email_roles.py:36-54](../../backend/app/shared/email_roles.py#L36-L54) is
   not misclassifying anyone today. #7's remaining causes are therefore the two client-side ones
   already fixed in 1.3 (error-to-hidden collapse, and the realtime notification not refreshing
   attendance state). Worth re-running if a student ever reports it again, since the inference is
   re-applied on **every** bootstrap and a changed campus address would silently flip a role.
4. **Actual Supabase token lifetimes (blocks #10 recommendations).** Read JWT expiry, refresh-token
   rotation, and reuse interval from the Supabase dashboard and **record them in the doc**. They
   exist in no file in this repo. Do not change them before reading them.
5. ~~**`HONORS_ATTENDANCE_ENABLED` and `ATTENDANCE_QR_SIGNING_SECRET`** — confirm what is set in the
   Render dashboard.~~ **Resolved 2026-09-16:** both confirmed set in Render. Ruled out as a cause of
   #7; the remaining work is declaring them in `render.yaml` for drift protection (#0.3), which needs
   no further measurement.
6. **Group unread correctness (Part 3 #7).** Verify whether `unread_summary` counts group
   conversations or only match-keyed DMs.
7. **Notification and message table sizes.** Row counts decide whether 2.4's indexes matter now or
   are just hygiene. Capture `EXPLAIN ANALYZE` for `list_notifications` at real volume.
8. **Keyboard behaviour on physical devices (blocks #16 sign-off).** iOS and Android differ on
   keyboard persistence across redirect-driven route swaps; simulators do not reproduce it reliably.
9. **Image cache hit rate after 2.2.** Measure avatar requests per session before and after; the
   claim "the same image reloads repeatedly" should become measurable and then zero.

---

## Part 6 — Testing, validation, and regression requirements

**The repo's existing gate is the baseline and must stay green.** Per [CLAUDE.md](../../CLAUDE.md), run
`/verify`, or manually:

```bash
# backend/
.venv/bin/pytest --ignore=tests/db     # unit + OpenAPI snapshot (no Postgres)
.venv/bin/pytest tests/db              # integration (needs Postgres / TEST_DATABASE_URL)
.venv/bin/ruff check .
# mobile/
flutter analyze && flutter test
# repo
python scripts/check_line_limits.py
```

**The OpenAPI snapshot is the regression tripwire.** Every API change in this plan — #4 reactions,
#5 `PATCH /messages/{id}`, #8 typed error codes, #13 pagination, #14 `POST /notifications/{id}/read`,
#15 target ids — **will** fail the snapshot test. That is correct behaviour. Regenerate deliberately
with `UPDATE_SNAPSHOTS=1 .venv/bin/pytest` **only** for intended changes, and never as a way to make
a red suite green. A pure refactor (#9's backend part, the Part 3 fixes) must leave it
**byte-identical**.

**Per-phase requirements:**

| Phase | New tests | Regression focus |
|---|---|---|
| 0 | Eligibility `Unknown` → retry (not hidden); splash → `/home` never via `/login`; deep link queued through `AsyncLoading` | [flow_no_dead_ends_test.dart](../../mobile/test/features/auth/flow_no_dead_ends_test.dart), [policy_consent_gate_test.dart](../../mobile/test/features/auth/policy_consent_gate_test.dart) — the redirect gate is load-bearing for suspension, policy, and onboarding |
| 1 | `TZ=America/New_York` golden: 18:00 renders "6:00 PM" on **all three** surfaces; naive PATCH → 422 not 500; blueprint/attendance error → retry; scanner failure matrix; notification unread snapshot; focus cleared across redirect | [activities_test.dart](../../mobile/test/features/activities/activities_test.dart), [attendance_test.dart](../../mobile/test/features/attendance/attendance_test.dart), [blueprint_bond_test.dart](../../mobile/test/features/scholars/blueprint_bond_test.dart), [notification_count_provider_test.dart](../../mobile/test/features/notifications/notification_count_provider_test.dart), [dismiss_keyboard_test.dart](../../mobile/test/shared/widgets/dismiss_keyboard_test.dart) |
| 2 | Cached-first-paint (no skeleton when cache exists); request dedup; keyset pagination stability under equal timestamps; index presence assertions; **send path: query-count assertion per send (guards the ~11 → 2 reduction against regression), authorization-cache invalidation on each control event (`user.suspended`, `member.revoked`, `pair.revoked`, `conversation.revoked`), send to an unsubscribed conversation still takes the full read path, WS+REST race yields exactly one row with `duplicate: true` on the loser** | [test_notifications_inbox.py](../../backend/tests/db/test_notifications_inbox.py), [pull_to_refresh_test.dart](../../mobile/test/features/shared/pull_to_refresh_test.dart); re-run [test_attendance_load.py](../../backend/tests/db/test_attendance_load.py) |
| 3 | Draft persist/restore/clear; no nav bar in chat + legacy redirect; staff can reach Groups; delivery boundary monotonic + idempotent; reaction toggle idempotent under concurrency; edit inside/outside window; edit forbidden for group admins; `message_edits` written | [chat_send_test.dart](../../mobile/test/features/messages/chat_send_test.dart), [messages_test.dart](../../mobile/test/features/messages/messages_test.dart), [unread_provider_test.dart](../../mobile/test/features/messages/unread_provider_test.dart), [realtime_client_test.dart](../../mobile/test/core/realtime/realtime_client_test.dart), [ws_protocol_test.dart](../../mobile/test/core/realtime/ws_protocol_test.dart), [test_group_messaging.py](../../backend/tests/db/test_group_messaging.py), [test_message_delete.py](../../backend/tests/db/test_message_delete.py), [test_dm_parity.py](../../backend/tests/db/test_dm_parity.py) |
| 4 | Token-snap assertions; one loading vocabulary per surface; a11y: tab `selected`, skeleton semantics, tick semantics, unread not colour-only | [auth_layout_regression_test.dart](../../mobile/test/features/auth/auth_layout_regression_test.dart), [skeleton_a11y_test.dart](../../mobile/test/shared/widgets/skeleton_a11y_test.dart) |

**Manual / device validation** (cannot be automated here): physical iOS **and** Android for #16;
notification taps from **background and terminated** states for #8; camera permission denied /
limited / permanently-denied for #8; two devices for #14/#21/#23 read-and-delivery sync; airplane-mode
send → reconnect for #12/#21; a real cold start for every S2-affected path.

**Line limits.** Several targets are already close to the 600-line hard cap —
[public_profile_screen.dart](../../mobile/lib/features/profile/screens/public_profile_screen.dart) at 564,
[admin/router.py](../../backend/app/features/admin/router.py) at 599,
[attendance/service.py](../../backend/app/features/attendance/service.py) at 546. #19's Messages hub and
#4/#5's chat additions must land as new `part` files / new modules, not as growth in place.

---

## Report index

Quick lookup from a beta report number to its verdict.

| # | Report | Verdict | Phase |
|---|---|---|---|
| 1 | Message drafts not preserved | Confirmed (code) | 3.3 |
| 2 | Bottom nav inside conversations | Confirmed (design) | 3.1 |
| 3 | Profile-picture viewing limited | Confirmed (code) | 4.6 |
| 4 | Message reactions missing | Confirmed (code) | 3.6 |
| 5 | Sent-message editing missing | Confirmed (code) | 3.7 |
| 6 | Blueprint card sometimes missing | Confirmed (code) | 1.2 |
| 7 | Attendance card sometimes missing | Confirmed (code) | 1.3 |
| 8 | Attendance notification errors | Confirmed (code) | 1.4 |
| 9 | Activity time mismatch (6 PM → 10 PM) | Confirmed (code) | 1.1 |
| 10 | Session persistence | Confirmed (code) — **not** a lifetime issue | 1.5 |
| 11 | Login screen flashes at startup | Confirmed (code) | 0.2 |
| 12 | Slow message sending | Confirmed (code) — ~11 serial DB round trips per send; cold-start split needs measurement | 2.5–2.8 |
| 13 | Slow Notifications page | Partially confirmed — queries are fine | 2.4 |
| 14 | Read/unread not visually clear | Confirmed (code) — styling unreachable | 1.6 |
| 15 | Notifications UX review | Confirmed (design) | 4.4 |
| 16 | Keyboard/focus behaviour | Confirmed (code) | 1.7 |
| 17 | Excessive loading/refetching | Confirmed (code) | 2.2, 2.3 |
| 18 | Dashboard polish | Confirmed (design) | 4.1–4.3 |
| 19 | Groups hard to discover | Confirmed (design) — **not** in Connections | 3.2 |
| 20 | Connections page crowded | Partially confirmed — wrong screen named | 4.5 |
| 21 | Sending/delivery/read states | Partially confirmed — Delivered missing | 3.4 |
| 22 | Push ≠ presence | **Already correct** — no presence feature exists | 3.8 |
| 23 | Read receipts visibility | Partially confirmed — too weak, absent from list | 3.5 |

**Reviewed but deliberately not changed:** the WebSocket protocol and send ladder, message
idempotency, keyset pagination, the QR HMAC scheme, Supabase-only auth, keystore session storage,
single-instance-without-Redis (see `architecture_review/DECISION_LOG.md`), and the `announcements`
provider's intentional `autoDispose`. Part 1's S2 section explains why "add workers" is the wrong
first move.
