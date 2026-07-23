"""Backfill DM conversations from existing matches (P1 of the groups plan).

The SQL lives here rather than inline in the migration so the **migration and the tests run
the identical statements** — the backfill is the part that must be provably correct.

Every statement is **idempotent** (re-running changes nothing), so the migration is safe to
re-apply and tests can call it repeatedly.

See docs/groups/implementation_phases.md → P1.
"""

from __future__ import annotations

# 1. One DM conversation per match. `conversations.match_id` is UNIQUE, so a match can never
#    end up with two conversations (this is how duplicate DMs stay impossible).
_CREATE_DM_CONVERSATIONS = """
INSERT INTO conversations (id, kind, match_id, created_at)
SELECT gen_random_uuid(), 'dm', m.id, m.created_at
FROM matches m
WHERE NOT EXISTS (SELECT 1 FROM conversations c WHERE c.match_id = m.id)
"""

# 2. Both sides of the match become active members of its conversation.
_CREATE_DM_MEMBERS = """
INSERT INTO conversation_members (id, conversation_id, user_id, role, status, muted, joined_at)
SELECT gen_random_uuid(), c.id, pair.user_id, 'member', 'active', false, m.created_at
FROM conversations c
JOIN matches m ON m.id = c.match_id
CROSS JOIN LATERAL (VALUES (m.user_a_id), (m.user_b_id)) AS pair(user_id)
WHERE c.kind = 'dm'
  AND NOT EXISTS (
      SELECT 1 FROM conversation_members cm
      WHERE cm.conversation_id = c.id AND cm.user_id = pair.user_id
  )
"""

# 3. Point every existing message at its conversation. `match_id` is left untouched.
_LINK_MESSAGES = """
UPDATE messages
SET conversation_id = c.id
FROM conversations c
WHERE c.match_id = messages.match_id
  AND messages.conversation_id IS NULL
"""

BACKFILL_STATEMENTS: tuple[str, ...] = (
    _CREATE_DM_CONVERSATIONS,
    _CREATE_DM_MEMBERS,
    _LINK_MESSAGES,
)
