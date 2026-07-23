"""add conversation-keyed keyset index on messages (P2 hardening)

Revision ID: a7b8c9d0e1f2
Revises: f6a7b8c9d0e1
Create Date: 2026-07-23

Since P2, paging/sync/unread filter on `conversation_id` and keyset-scan `(created_at, id)`.
This composite index is the conversation-keyed equivalent of `ix_messages_match_created_id`,
and also serves the unread boundary scan. Additive; the legacy match-keyed indexes stay for
rollback safety.
"""

from alembic import op

revision = 'a7b8c9d0e1f2'
down_revision = 'f6a7b8c9d0e1'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        'CREATE INDEX IF NOT EXISTS ix_messages_conversation_created_id '
        'ON messages (conversation_id, created_at DESC, id DESC)'
    )


def downgrade() -> None:
    op.execute('DROP INDEX IF EXISTS ix_messages_conversation_created_id')
