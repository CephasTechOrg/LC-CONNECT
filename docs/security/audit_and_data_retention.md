# Audit & Data-Retention Policy

What LC Connect **keeps**, what it **permanently deletes**, and how a moderator can **investigate**.
This is the authoritative reference for the deletion/retention behavior of every user-facing action —
written so policy, safety, and privacy questions have one honest answer.

**Guiding principle:** *preserve evidence where it matters, attribute actions where we can, and don't
hoard everything forever.* We deliberately do **not** retain all deleted content indefinitely (that's
a privacy liability); we **do** make sure moderation can't be defeated by deleting content.

---

## 1. Retention at a glance

| Action | Delete style | Retained? | Auditable? |
|---|---|---|---|
| **Send/delete a message** | **soft** (`messages.deleted_at`) | ✅ original body kept in DB, never re-served | ✅ yes |
| **Leave / remove / ban a member** | **soft** (`ConversationMember.status`) | ✅ row kept with `removed`/`banned` | ✅ yes |
| **Reject / decline an invite** | **soft** (status → `removed`) | ✅ | ✅ yes |
| **Report a message/user/group** | insert + **evidence snapshot** | ✅ message text copied into the report | ✅ **survives later deletion** |
| **Block a user** | insert (`blocks` row) | ✅ row persists until unblocked | ✅ yes |
| **Update a group/profile avatar** | **replace** (deterministic path) | ❌ old image overwritten (no orphan) | n/a |
| **Delete a group** | **hard** (cascade) | ❌ conversation, members, messages all removed | ⚠️ **no** (see §5) |

---

## 2. Messages — soft delete

"Delete for everyone" sets `messages.deleted_at`. The row and its **original `body` stay in the
database**; the API simply **stops serving the text** (deleted messages return `body=''`,
`deleted=true`) and the client shows a "This message was deleted" tombstone.

- **Who can delete:** the **sender** (their own message, anywhere) or a **group admin/owner** (any
  message in their group, for moderation). Everyone else → 403.
- **Why soft:** so a message can't be used to harass and then vanish beyond review. The text remains
  available to moderation via the database (and, for reported messages, on the report itself — §4).
- **Gap (deferred):** we record **when** a message was deleted (`deleted_at`) but **not who** deleted
  it (sender vs which admin). `deleted_by` attribution is a planned follow-up.

---

## 3. Membership changes — soft

Leaving, being removed, being banned, or rejecting/declining an invite **never deletes the
membership row** — it flips `ConversationMember.status` to `removed` or `banned`. So there is always a
record that a person *was* in a group and how they left. `banned` additionally blocks rejoining.

---

## 4. Reports — evidence snapshot (the safety guarantee)

Reporting is the one place we **actively preserve evidence**, because moderation must not be
defeatable by deleting the content afterwards.

When a message is reported, `create_report` **copies the message's text into the report**
(`reports.message_body`) and attributes it to the message's author (`reported_user_id`). Therefore:

- If the reported message is later **soft-deleted** → the report still holds the text. ✅
- If the reported message's **whole group is hard-deleted** (cascading the message away) → the
  report's `message_id` becomes `NULL`, **but `message_body` still holds the evidence**. ✅

Moderators read reports via `GET /admin/reports` (admin, AAL2), which exposes `group_id`,
`message_id`, and the snapshotted `message_body`. Reports are never auto-deleted.

---

## 5. Group deletion — hard delete (known limitation)

Deleting a group deletes its `Conversation`, and `messages.conversation_id` /
`conversation_members.conversation_id` are `ON DELETE CASCADE`. So **deleting a group permanently
removes the group, its members, and its entire message history.** This content is **not recoverable**
and **not auditable** after the fact.

This is a deliberate current limitation, mitigated by the report snapshot (§4): any message that was
**reported** before the group was deleted still has its evidence retained on the report. Un-reported
messages in a deleted group are gone.

**Deferred improvement:** soft-archive groups (mark deleted + hide, retain history) instead of a hard
cascade, so a delete can never erase evidence. Tracked in the groups docs.

---

## 6. Avatars — replace, no accumulation

Group and profile avatars are written to a **deterministic** storage path and the prior file is
removed before the new one is written, so there is **exactly one avatar per entity** and no orphaned
copies pile up in the bucket. Previous images are not retained (an avatar is not audit-relevant
content). URLs are public (with a cache-buster) — appropriate for display images.

---

## 7. How to investigate (moderator playbook)

| Question | Where to look |
|---|---|
| "What did this reported message say?" | `GET /admin/reports` → `message_body` (survives deletion) |
| "Who reported whom, and why?" | `reports`: `reporter_id`, `reported_user_id`, `reason`, `details`, `created_at` |
| "Did a moderator open / resolve this report?" | `admin_audit_logs`: actions `report.view`, `report.resolve` |
| "Why was this account suspended?" | `admin_audit_logs` action `user.suspend` → `after_data.reason` |
| "Was this person ever in the group / how did they leave?" | `conversation_members` row: `status` (`removed`/`banned`), `role`, `joined_at` |
| "Is a deleted message's original text recoverable?" | `messages` row: `body` is retained even when `deleted_at` is set — **unless** the group was hard-deleted |
| "Who deleted this message?" | ⚠️ not recorded yet (`deleted_by` deferred) — only `deleted_at` |
| "Can a user download their own data?" | `GET /account/export` (JSON; audited as `account.export`) |

---

## 8. Privacy posture & deferred work

We intentionally stop short of *total* retention:

- **No indefinite retention of all deleted content.** Soft-deleted messages persist for
  **`MESSAGE_SOFT_DELETE_RETENTION_DAYS`** (default **90**), then a daily cron job hard-deletes
  eligible rows via `scripts/purge_soft_deleted_messages.py`. Report snapshots (`message_body`)
  are unaffected.
- **Deferred, in priority order:**
  1. `deleted_by` attribution on message deletes.
  2. Soft-archive for group deletion (stop the hard cascade).
  3. ~~Retention window / auto-purge job for soft-deleted content.~~ ✅ (cron + script)

Each is a clean follow-up; none re-opens the safety hole now that reports self-preserve evidence.

---

## 9. Scheduled purge (operations)

**What:** Hard-delete `messages` rows where `deleted_at` is older than the retention window.

**Default window:** 90 days (`MESSAGE_SOFT_DELETE_RETENTION_DAYS`).

Schedule daily via platform cron — **full setup:** [`MESSAGE_RETENTION_CRON_RUNBOOK.md`](./MESSAGE_RETENTION_CRON_RUNBOOK.md).

**Script:**

```bash
cd backend
.venv/bin/python scripts/purge_soft_deleted_messages.py          # dry-run
.venv/bin/python scripts/purge_soft_deleted_messages.py --apply  # delete eligible rows
```

**Safety:** `reports.message_body` snapshots are **not** purged. If a message row is deleted,
`reports.message_id` becomes `NULL` but the copied text remains.
