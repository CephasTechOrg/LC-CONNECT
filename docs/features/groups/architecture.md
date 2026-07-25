# Groups — Architecture & Decision Log

Why groups require a messaging change, the final model, and the reasoning behind every
decision (including which external-review suggestions we adopted, and which we rejected).

---

## 1. The problem

Messaging today is **hard-wired to 1:1**:

- `Message.match_id` → `Match(user_a_id, user_b_id)` — a container of *exactly two* users.
- Everything downstream assumes a singular **"partner"**: the thread list
  (`MessageThreadRead.partner`), unread ("the partner's unread messages"), offline push
  ("notify the partner"), typing ("route to the partner's channel").

A group is a container with **N members and no single partner**. So groups are not a bolt-on
— they require generalizing the message container.

**The good news:** the realtime gateway, unread engine, push pipeline and background-suspend
are already **conversation-keyed** (they operate on a `conversation_id`); they just assume
that id resolves to a 2-person match. Generalize the container and most of that machinery
works for groups unchanged.

---

## 2. Final architecture

Three layers, deliberately separated:

```
Group  ──owns──▶  Conversation  ──has──▶  ConversationMember (N)
(campus community)  (messaging container)      (role + status + read boundary)
                          │
                          └──has──▶ Message (conversation_id)

DM  =  Conversation(kind='dm')  linked to a Match   (2 members, no Group)
Group chat = Group ──▶ Conversation(kind='group')   (N members)
```

| Entity | Responsibility | Key fields |
|---|---|---|
| **`Conversation`** | Pure messaging container | `kind = dm \| group` |
| **`ConversationMember`** | Membership + per-member state | `role`, `status`, `joined_at`, `invited_by`, `last_read_message_id`, `muted` |
| **`Group`** | Campus **community** domain entity | `name`, `avatar_url`, `description`, `category`, `visibility`, `join_policy`, `owner_id`, `conversation_id`, `max_members` |
| **`Match`** | *unchanged* — the social relationship + DM identity | `user_a_id`, `user_b_id` |

---

## 3. Decision log

### D1 — Unify DMs and groups under `Conversation` ✅
**Chosen** over a parallel `Group` messaging system. A parallel system would fork every
future messaging feature (reactions, search, media, receipts) into two implementations, and
would duplicate unread/push/gateway logic permanently. One container = one code path.

### D2 — `Group` is a **separate domain entity** that owns a Conversation ✅
*(Adopted from external review — an improvement on our first proposal, which put group
fields directly on `Conversation`.)*

A campus group will plausibly grow to include events, announcements, posts, resources,
officers and rules — none of which belong on a messaging container. LC Connect already models
rich domain entities separately (`Activity` has title/category/location/time/capacity and is
not a chat), so this is consistent with the codebase's own direction.

### D3 — Per-member read boundary (`last_read_message_id`) ✅ *(biggest change)*
Today unread is computed from **per-message `Message.read_at`** — `mark_read()` stamps the
partner's messages up to a cursor, and `unread_summary()` counts rows where
`read_at IS NULL AND sender_id != me`.

**That model cannot express group unread.** `read_at` is a single column on the message — in a
group with N members it can't say *which* member has read it. Groups therefore **require** a
per-member boundary stored on `ConversationMember`.

We use **`last_read_message_id`** (not `last_read_at`) as the authority, ordered by our
existing keyset `(created_at, id)` — timestamps can collide, message ids can't. `read_at` may
be retained for DM receipts/display.

> ⚠️ This is the single largest impact on already-hardened code (the unread engine and the
> mobile `unreadProvider`). It gets the most test scrutiny — see P2.

### D4 — DM identity reuses `Match` (no new pair key) ✅
The external review suggested a deterministic `smaller_id:larger_id` pair key to prevent
duplicate DM conversations. **We already have this**: matches are created with a normalized
pair (`sorted([user_a, user_b])` in `app/features/connections/service.py`) and enforced by
`UniqueConstraint('user_a_id','user_b_id', name='uq_match_pair')`. A DM conversation is
created from / linked to its Match, inheriting that guarantee. No new key needed.

### D5 — Slim visibility + join policy (not a 4×4 matrix) ✅
- `visibility`: `public | unlisted | private`
- `join_policy`: `open | approval | invite`

The review proposed four visibilities including *campus-only*; the whole app is already
Livingstone-scoped, so that value is redundant. A "temporarily closed" state is a flag we can
add later if a real need appears.

### D6 — MVP join flows: **Open, Approval-required, direct admin invite** ✅
Shareable **invite links are deferred** — done properly they need token hashing, expiry,
revocation, usage limits, capacity/ban/eligibility checks and race protection. That's a slice
of its own, not a rider on the first release.

### D7 — Capacity must be enforced **transactionally** ✅
`app/features/activities/service.py` enforces capacity with a naive `count(*)` and no row
locking — two simultaneous joins can both pass the check. **Groups must not copy this
pattern** (and it's a latent bug in Activities worth fixing separately). Group joins will use
a locking/atomic strategy so `max_members` can't be exceeded under concurrency.

### D8 — Media/attachments deferred to their own slice ✅
Messages are text-only today (`Message.body`), and storage (`app/shared/storage.py`) is
avatar-only against a **public** bucket. Attachments need a message-type model, a **private**
bucket with **signed URLs**, magic-byte validation and EXIF stripping (reusing
`app/shared/image_processing.py`). Groups launch **text-first**; media lands afterwards for
DMs *and* groups together.

### D9 — Realtime: reuse vs generalize vs new
| | |
|---|---|
| **Reuse unchanged** | socket gateway + auth-first protocol, subscribe/unsubscribe model, reconnect/backoff, background-suspend, **multi-device fan-out** (`manager.deliver_to_user`), **per-send reauthorization** (`authorize_conversation` re-runs each send), **typing token-bucket rate limit** |
| **Generalize** | `authorize_conversation` → membership lookup on `ConversationMember` (2 or N); broadcast to **all members** not "the partner"; typing to all other members; thread-list gains a **group variant** (title+avatar instead of partner) |
| **New safeguards** | **push fan-out** to all *offline, non-sender, non-muted* members (today `schedule_offline_push` targets one partner); **revoke-on-removal** (`manager.revoke_pair` is DM-specific — removing a group member must close their subscription); dedup across fan-out |

### D10 — Permissions centralized, not scattered ✅
Authorization today is dependency-based (`require_verified_student`, `require_admin_aal2`),
plus a **centralized policy module** at `app/shared/policies.py` (`users_are_blocked`,
`assert_profile_visible`). Group permissions follow that established pattern — a single
policy surface for group actions (send, invite, approve, remove, promote, edit, delete,
transfer) rather than role checks sprinkled through routers.

**Invariants to enforce in the service layer:** a group always has an owner · the owner must
transfer ownership before leaving · an admin cannot remove the owner · a banned member cannot
rejoin · owner-only actions are not general admin actions.

### D11 — Minimal group moderation now; dashboard later ✅
Already built: `Block`, `Report` (`reported_user_id` / `activity_id` / `reason` / `status`),
and admin `suspend_user` + `remove_activity`. For groups we add **remove/ban** (via
`ConversationMember.status`) and **report targets** (nullable `group_id` / `message_id` on
`Report`). A full audit-log table and moderation dashboard are deferred — the architecture
doesn't block them.

---

## 4. Deliberately deferred

| Deferred | Why |
|---|---|
| Shareable invite links | Security-heavy (hashing, expiry, revocation, limits, races) — own slice |
| Media / attachments | Needs private bucket + signed URLs + sanitization — own slice, benefits DMs too |
| Audit-log table + moderation dashboard | Not MVP; architecture leaves room |
| `notification_level`, `muted_until`, `left_at` | `status` + a simple `muted` boolean covers MVP |
| Group events / announcements / posts | The `Group` entity exists precisely so these can be added without touching messaging |
| Fixing Activities' capacity race | Real bug, but separate from groups |

---

## 5. Impact map on existing systems

| System | Impact |
|---|---|
| `Match` | **Unchanged.** Stays as the social relationship + DM identity/dedup; gains an associated DM conversation. |
| `Message` | `match_id` → `conversation_id` (staged: add nullable → backfill → cut over → drop later). Highest-touch change. |
| **Unread** | **Most affected.** Per-message `read_at` + `unread_summary()` + mobile `unreadProvider` are DM-shaped; move to the per-member boundary (D3). |
| Realtime | `gateway`/`manager` already conversation-keyed; generalize authz + broadcast; add per-member revoke. |
| Push | `schedule_offline_push` becomes a fan-out over offline members. |
| `Activity` / `ActivityParticipant` | **Template** for the membership shape — but *not* for its capacity check (D7). |
| Mobile | `MessageThread.partner`, `chat_screen`, `unreadProvider`, `messages_screen` assume 1:1 → thread list needs a group variant. Wired in P6. |
| Avatars | Group avatars **reuse** `sanitize_avatar` as-is. |
