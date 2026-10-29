"""one unread notification per subject; indexes for message purge and boundaries

Revision ID: o9c0d1e2f3a4
Revises: n8b9c0d1e2f3
Create Date: 2026-10-29

- `uq_notifications_unread_subject`: at most one unread notification per (recipient, type,
  actor, subject). Two reactions arriving together used to both insert. Existing duplicates are
  collapsed first, keeping the newest unread row.
- `ix_messages_deleted_at` (partial) for the retention purge, and indexes on the two
  conversation_members boundary columns so a purged message's ON DELETE SET NULL does not scan
  the members table.

Reversible; the collapsed duplicate notifications are not restored by a downgrade.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = 'o9c0d1e2f3a4'
down_revision = 'n8b9c0d1e2f3'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        DELETE FROM notifications n
        USING notifications m
        WHERE n.read_at IS NULL AND m.read_at IS NULL
          AND n.subject_id IS NOT NULL
          AND n.user_id = m.user_id AND n.type = m.type
          AND n.actor_id = m.actor_id AND n.subject_id = m.subject_id
          AND (n.created_at, n.id) < (m.created_at, m.id)
        """
    )
    op.create_index(
        'uq_notifications_unread_subject',
        'notifications',
        ['user_id', 'type', 'actor_id', 'subject_id'],
        unique=True,
        postgresql_where=sa.text('read_at IS NULL AND subject_id IS NOT NULL'),
    )
    op.create_index(
        'ix_messages_deleted_at', 'messages', ['deleted_at'], postgresql_where=sa.text('deleted_at IS NOT NULL')
    )
    op.create_index('ix_conversation_members_last_read', 'conversation_members', ['last_read_message_id'])
    op.create_index('ix_conversation_members_last_delivered', 'conversation_members', ['last_delivered_message_id'])


def downgrade() -> None:
    op.drop_index('ix_conversation_members_last_delivered', table_name='conversation_members')
    op.drop_index('ix_conversation_members_last_read', table_name='conversation_members')
    op.drop_index('ix_messages_deleted_at', table_name='messages')
    op.drop_index('uq_notifications_unread_subject', table_name='notifications')
