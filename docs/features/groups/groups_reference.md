# Groups — Behavior & Policy Reference

The single source of truth for **how groups actually work today**: their data model, every role and
permission, the join flows, messaging, notifications, moderation, and limits. For the *why* behind
the design see [`architecture.md`](./architecture.md); for exact request/response payloads see
[`api_contract.md`](./api_contract.md); for the build log see [`implementation_phases.md`](./implementation_phases.md).

> Status: **complete / production-ready.** Everything below is implemented and test-covered.

---

## 1. What a group is

A **group** is a campus community (club, housing, class, interest group). Structurally:

- A `Group` domain row (name, description, avatar, category, visibility, join policy, owner, cap).
- It **owns a `Conversation(kind='group')`** — the same messaging container DMs use. So group chat
  runs on the exact same engine as DMs (fan-out, typing, read receipts, push).
- Membership is `ConversationMember` rows (the same table DMs use): `(conversation_id, user_id,
  role, status, muted, last_read_message_id, …)`.

A **DM** is a `Conversation(kind='dm')` linked to a `Match`; a **group** is a
`Conversation(kind='group')` owned by a `Group`. One model, two kinds.

**Addressing:** clients address a DM by its `match_id` and a group by its `conversation_id`; the
backend resolves either.

---

## 2. Group properties

| Property | Values | Notes |
|---|---|---|
| **category** | `club` · `housing` · `class` · `interest` | Filter facet in discovery. |
| **visibility** | `public` · `unlisted` · `private` | See table below. |
| **join_policy** | `open` · `approval` · `invite` | How people get in. |
| **max_members** | `null` or `2…500` | Per-group cap; `null` = the global cap. |
| **owner** | one user | Always exactly one; changed only via transfer. |

### Visibility

| Visibility | In discovery? | Viewable by link? | Non-member access |
|---|---|---|---|
| `public` | ✅ yes | ✅ yes | can view + (per policy) join |
| `unlisted` | ❌ no | ✅ yes (with the id) | can view; entry via invite/link |
| `private` | ❌ no | ❌ no | **404** — existence is never revealed |

Chosen at creation (and editable). Only `public` groups appear in `GET /groups/discover`.

### Join policy

| Policy | Tapping "join" does… |
|---|---|
| `open` | Instantly become an **active** member. |
| `approval` | Creates a **requested** membership; an admin approves/rejects. Admins are notified. |
| `invite` | No public join. Entry only via an admin invite the user accepts. |

---

## 3. Roles & permissions

Three roles, strictly ranked: **member (0) < admin (1) < owner (2)**. A group always has exactly one
owner. All permission logic lives in [`policies.py`](../../backend/app/features/groups/policies.py) —
the backend is authoritative and re-checks every action; the mobile UI mirrors these rules only to
decide what to show.

### Minimum role per action

| Action | Min role | Notes |
|---|---|---|
| Send a message | member | Any active member. |
| Invite a user | **admin** | **Connections-only** — you may only invite people you're matched with (backend-enforced). |
| Approve / reject a request | **admin** | |
| Remove a member | **admin** | Subject to the moderation-rank rule below. |
| Ban a member | **admin** | Banned users cannot rejoin. |
| Edit group (name/desc/visibility/policy/avatar/cap) | **admin** | |
| Change a member's role (promote/demote) | **admin** | Subject to the rank rule. |
| Delete the group | **owner** | Hard delete (see the audit doc). |
| Transfer ownership | **owner** | Old owner steps down to admin. |

### The moderation-rank rule (`can_moderate`)

To remove, ban, or demote someone you must **strictly outrank** them, and the **owner is never a
valid target**:

- an **admin** can act on **members**, but not on other admins or the owner;
- an **owner** can act on **admins** and members;
- promoting a member to admin, or demoting an admin, requires you to outrank them (so only the owner
  can demote an admin).

---

## 4. Member lifecycle

A `ConversationMember.status` is one of:

| Status | Meaning |
|---|---|
| `active` | A full member. |
| `requested` | Asked to join an `approval` group; awaiting an admin. |
| `invited` | Invited to a group; awaiting their accept/decline. |
| `removed` | Left, was removed, rejected, or declined an invite. **Can rejoin** (if allowed). |
| `banned` | Removed with a ban. **Cannot rejoin.** |

The row is **never deleted** on leave/remove/ban — the status changes (soft). This preserves an audit
trail (see the audit doc).

**Transitions:**

```
                 open join ─────────────► active
requested ──approve──► active     ──reject──► removed
invited   ──accept───► active     ──decline─► removed
active    ──leave────► removed
active    ──remove───► removed     ──ban───► banned
member    ──promote──► admin       ──demote─► member   (owner only for admins)
owner     ──transfer─► admin (old) ; target ► owner
```

Owners must **transfer ownership before leaving** (a group always keeps exactly one owner).

---

## 5. Capacity & the global cap

- Each group may set its own `max_members` (2…500).
- A **global hard cap** (`settings.group_max_members`, default **500**) applies to **every** group —
  including those that set no `max_members` of their own. Effective cap = `min(own, global)`; a group
  can never exceed 500.
- Enforced under a **row lock** (`SELECT … FOR UPDATE`) so concurrent joins can't overshoot; every
  add-a-member path (join, approve, accept-invite) goes through it. A full group returns **409**.
- Setting `max_members` above the global cap is rejected at create/edit with a **400**.

Rationale: every message fans out to all members (O(members) per send), so an unbounded group is an
unbounded cost + abuse vector.

---

## 6. Messaging in a group

Group chat is the DM engine, generalized:

- **Fan-out:** a sent message is delivered **live over WebSocket to every active member**. Typing
  indicators fan out the same way.
- **Push:** offline members get a push notification — **except muted members** (see mute).
- **Per-sender identity:** incoming group bubbles show the **sender's name + avatar** (resolved from
  the member list), shown once per run of consecutive messages, WhatsApp-style.
- **Unread:** uses the per-member `last_read_message_id` boundary (a single `read_at` can't express
  which of N members has read a message). The unified inbox and badge read from this.
- **Removal cuts off live access:** removing/banning a member immediately closes their live
  subscription so they stop receiving the group's messages.
- **Mute:** a member can mute a group (`PATCH /groups/{id}/members/me {muted}`). Muted members still
  receive messages **live**; they just don't get **push**. Personal — never affects anyone else.
- **Delete a message:** "delete for everyone" (soft) — the sender anywhere, or a group admin/owner on
  any message in their group. See the audit doc.

---

## 7. Notifications

Membership events raise an in-app notification (persistent + live via WebSocket + a badge counter):

| Event | Recipient | Type |
|---|---|---|
| Invited to a group | the invitee | `group_invite` |
| Join request (approval group) | the group's **admins/owner** | `group_join_request` |
| Request approved | the requester | `group_request_approved` |
| Request rejected | the requester | `group_request_rejected` |
| Promoted to admin | the member | `group_made_admin` |
| Demoted from admin | the member | `group_removed_admin` |
| Removed / banned | the member | `group_removed` |

(Connection events — `connection_request`, `connection_accepted` — share the same center.) The badge
seeds from `GET /notifications/unread-count`, increments live, and clears when the center is opened.

---

## 8. Avatars

- Stored at a **deterministic** path per group; a new upload **replaces** the old (no duplicates /
  no storage leak).
- URLs are **public** with a cache-buster — correct for display images. (A private group's avatar is
  therefore fetchable by anyone holding the exact URL, same as profile pictures.)
- Uploaded bytes are **sanitized** (validated + EXIF/GPS stripped) before storage, same as profile
  photos. Admin+ only. Can be set at creation or later from the group's info screen.

---

## 9. Moderation & safety

- **Report** a message, a group, or a user (`POST /reports`). Reporting a message **snapshots its
  text and author into the report** so the evidence survives later deletion (see the audit doc).
- **Delete** a message for everyone — sender or group admin/owner (soft delete → tombstone).
- **Remove / ban** members (admins, per the rank rule); banned users can't rejoin.
- **Blocks** (app-wide) also apply: blocked users can't DM, and a block drops any shared live
  conversation.

---

## 10. Endpoint map

All under `/groups` (see [`api_contract.md`](./api_contract.md) for payloads). "Gate" = who may call it.

| Method & path | Purpose | Gate |
|---|---|---|
| `POST /groups` | Create a group | verified student |
| `GET /groups/me` | My active groups | member |
| `GET /groups/invites` | My pending invites (incl. private) | verified student |
| `GET /groups/discover` | Public discovery (`q`, `category`, `limit`) | verified student |
| `GET /groups/{id}` | Group detail | visible to caller |
| `PATCH /groups/{id}` | Edit settings | admin+ |
| `POST /groups/{id}/avatar` | Upload avatar | admin+ |
| `DELETE /groups/{id}` | Delete group (hard) | owner |
| `POST /groups/{id}/join` | Join / request | visible to caller |
| `GET /groups/{id}/members` | List members | member |
| `GET /groups/{id}/requests` | Pending requests | admin+ |
| `POST /groups/{id}/requests/{uid}/approve` | Approve | admin+ |
| `POST /groups/{id}/requests/{uid}/reject` | Reject | admin+ |
| `POST /groups/{id}/invites` | Invite a connection | admin+ (connections-only) |
| `POST /groups/{id}/invites/accept` | Accept an invite | invitee |
| `POST /groups/{id}/invites/decline` | Decline an invite | invitee |
| `DELETE /groups/{id}/members/me` | Leave | member (non-owner) |
| `PATCH /groups/{id}/members/me` | Mute / unmute | member |
| `PATCH /groups/{id}/members/{uid}` | Change role | admin+ (rank rule) |
| `POST /groups/{id}/transfer` | Transfer ownership | owner |
| `DELETE /groups/{id}/members/{uid}` (`?ban=`) | Remove / ban | admin+ (rank rule) |

---

## 11. Limits at a glance

| Limit | Value |
|---|---|
| Members per group | **500** (global hard cap; per-group cap may be lower) |
| Group name | 2–120 chars |
| Description | ≤ 2000 chars |
| Avatar | validated image, ≤ configured MB, EXIF-stripped |

---

## 12. Deliberately deferred

Not built yet (documented so it's a decision, not an oversight):

- **Group deletion is a hard delete** — soft-archive is deferred (see the audit doc).
- **`deleted_by` attribution** on message deletes — deferred.
- **Retention window** (auto-purge of soft-deleted content) — deferred.
- Offline **push** for membership/connection notifications (in-app center already delivers them).
- Multi-worker fan-out (Redis), notification grouping, quiet hours.
