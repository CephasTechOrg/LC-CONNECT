# Groups — API Contract (DRAFT, P0)

The endpoints and payloads the mobile group UI will be built against. **Draft** until
reconciled with the actual screens — if your UI needs a different shape, this doc changes,
not your UI.

All routes are under `/api/v1`, require `require_verified_student`, and 404 (never 403) when
a group isn't visible to you — same "don't reveal existence" rule as profiles.

---

## Core objects

```jsonc
// GroupSummary — list/discovery card
{
  "id": "uuid",
  "name": "Dorm B — House 4",
  "avatar_url": "https://… | null",
  "category": "housing",              // club | housing | class | interest
  "visibility": "public",             // public | unlisted | private
  "join_policy": "approval",          // open | approval | invite
  "member_count": 12,
  "max_members": 30,                  // nullable
  "my_status": "active"               // null | requested | invited | active | banned
}

// GroupRead — detail view = GroupSummary + …
{
  "description": "House 4 residents",
  "owner_id": "uuid",
  "conversation_id": "uuid",          // the group chat
  "my_role": "member",                // null | member | admin | owner
  "created_at": "iso8601"
}

// GroupMemberRead
{ "user_id": "uuid", "profile": { /* ProfilePublic */ },
  "role": "member", "status": "active", "joined_at": "iso8601" }
```

---

## Group lifecycle

| Method | Path | Who | Notes |
|---|---|---|---|
| `POST` | `/groups` | any student | Creates group **+ its conversation**; creator becomes `owner`. Body: `name`, `category`, `visibility`, `join_policy`, `description?`, `max_members?` → **201** `GroupRead` |
| `GET` | `/groups/me` | member | Groups I belong to → `GroupSummary[]` |
| `GET` | `/groups/discover?q=&category=&limit=` | any student | **`public` only.** `unlisted` never listed; `private` never listed → `GroupSummary[]` |
| `GET` | `/groups/{id}` | visibility-gated | `public`/`unlisted` → anyone with the id; `private` → members only, else **404** → `GroupRead` |
| `PATCH` | `/groups/{id}` | admin/owner | name, description, category, visibility, join_policy, max_members |
| `POST` | `/groups/{id}/avatar` | admin/owner | multipart `file`; **reuses `sanitize_avatar`** (EXIF-stripped, re-encoded JPEG) |
| `DELETE` | `/groups/{id}` | **owner only** | archive/delete |

## Membership

| Method | Path | Who | Notes |
|---|---|---|---|
| `POST` | `/groups/{id}/join` | any student | `open` → joins (**201**, `status:"active"`). `approval` → creates request (**202**, `status:"requested"`). `invite` → **403**. Enforces **capacity transactionally** and rejects `banned`. |
| `GET` | `/groups/{id}/members` | member | `GroupMemberRead[]` |
| `GET` | `/groups/{id}/requests` | admin/owner | pending join requests |
| `POST` | `/groups/{id}/requests/{user_id}/approve` | admin/owner | → member becomes `active` (capacity re-checked) |
| `POST` | `/groups/{id}/requests/{user_id}/reject` | admin/owner | |
| `POST` | `/groups/{id}/invites` | admin/owner | body `{user_id}` → member row `status:"invited"` |
| `POST` | `/groups/{id}/invites/accept` | invited user | → `active` |
| `DELETE` | `/groups/{id}/members/me` | member | **Leave.** Owner must transfer ownership first (**409**). |
| `DELETE` | `/groups/{id}/members/{user_id}` | admin/owner | Remove. Admin **cannot** remove the owner (**403**). Closes their live socket. |
| `POST` | `/groups/{id}/members/{user_id}/ban` | admin/owner | `status:"banned"`; cannot rejoin |
| `PATCH` | `/groups/{id}/members/{user_id}` | owner (role), admin (limited) | `{role}` promote/demote; `{transfer_ownership:true}` is **owner-only** |

## Messaging (reuses the existing system)

Group chat is **not** a new messaging API — it's the same conversation endpoints and the same
WebSocket protocol, addressed by the group's `conversation_id`.

| Method | Path | Notes |
|---|---|---|
| `GET` | `/messages/threads` | Returns **DM *and* group** threads (see the shape change below) |
| `GET` | `/messages/threads/{conversation_id}` | Keyset history — unchanged semantics |
| `GET` | `/messages/threads/{conversation_id}/sync` | Reconnect catch-up — unchanged |
| `GET` | `/messages/unread-summary` | Now keyed by `conversation_id` (covers groups) |
| `WS` | `/ws` | Same frames; `conversation_id` = the group's conversation |

### ⚠️ Breaking shape change (mobile, lands in P2/P6)

`MessageThreadRead` becomes conversation-shaped with a group variant:

```jsonc
{
  "conversation_id": "uuid",   // ← was "match_id"
  "kind": "dm",                // "dm" | "group"
  "partner": { /* ProfilePublic */ } | null,   // dm only
  "group":   { /* GroupSummary */ }  | null,   // group only
  "latest_message": { /* MessageRead */ } | null,
  "unread_count": 3
}
```

The thread list must branch on `kind`: render **partner name + avatar** for a DM, **group name
+ group avatar** for a group.

---

## Errors

| Code | When |
|---|---|
| `404` | Group not visible to you (private/non-member) — never reveal existence |
| `403` | Visible, but you lack the role for this action |
| `409` | Capacity full · owner trying to leave without transferring · already a member |
| `422` | Validation |

---

## Not in this contract (deferred)

Shareable **invite links** (needs token hashing/expiry/revocation/limits/races) ·
**attachments/media** · group events/announcements/posts · audit log.
See [`architecture.md`](./architecture.md) §4.
