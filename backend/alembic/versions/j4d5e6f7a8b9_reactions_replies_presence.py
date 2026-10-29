"""one reaction per person, message replies, notification subject, presence

Revision ID: j4d5e6f7a8b9
Revises: i3c4d5e6f7a8
Create Date: 2026-10-29

Four additive changes for messaging, in one revision so they deploy and roll back together:

- message_reactions: one reaction per person per message (WhatsApp). Duplicates are collapsed to
  each person's newest before the constraint changes. **Lossy**: a downgrade restores the old
  constraint but not the collapsed rows — take a backup first.
- notifications.subject_id: the message a reaction notification is about, so de-duplication and
  retraction work per message rather than per chat.
- messages.reply_to_id: the message a reply quotes, SET NULL when the retention purge removes it,
  with a partial index so that purge is not a scan per row.
- user_presence + profiles.show_presence: "last seen" storage and its reciprocal privacy switch.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = 'j4d5e6f7a8b9'
down_revision = 'i3c4d5e6f7a8'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Keep each person's newest reaction per message; ties broken by id so the result is stable.
    op.execute(
        """
        DELETE FROM message_reactions r
        USING message_reactions n
        WHERE r.message_id = n.message_id
          AND r.user_id = n.user_id
          AND (r.created_at, r.id) < (n.created_at, n.id)
        """
    )
    op.drop_constraint('uq_message_reaction', 'message_reactions', type_='unique')
    op.create_unique_constraint(
        'uq_message_reaction_user', 'message_reactions', ['message_id', 'user_id']
    )

    op.add_column('notifications', sa.Column('subject_id', postgresql.UUID(as_uuid=True), nullable=True))

    op.add_column('messages', sa.Column('reply_to_id', postgresql.UUID(as_uuid=True), nullable=True))
    op.create_foreign_key(
        'messages_reply_to_id_fkey', 'messages', 'messages', ['reply_to_id'], ['id'], ondelete='SET NULL'
    )
    op.create_index(
        'ix_messages_reply_to_id',
        'messages',
        ['reply_to_id'],
        postgresql_where=sa.text('reply_to_id IS NOT NULL'),
    )

    op.create_table(
        'user_presence',
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('last_seen_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('user_id'),
    )
    op.add_column(
        'profiles',
        sa.Column('show_presence', sa.Boolean(), server_default=sa.text('true'), nullable=False),
    )


def downgrade() -> None:
    op.drop_column('profiles', 'show_presence')
    op.drop_table('user_presence')
    op.drop_index('ix_messages_reply_to_id', table_name='messages')
    op.drop_constraint('messages_reply_to_id_fkey', 'messages', type_='foreignkey')
    op.drop_column('messages', 'reply_to_id')
    op.drop_column('notifications', 'subject_id')
    # The collapsed duplicates are not restored; the old constraint holds for what remains.
    op.drop_constraint('uq_message_reaction_user', 'message_reactions', type_='unique')
    op.create_unique_constraint(
        'uq_message_reaction', 'message_reactions', ['message_id', 'user_id', 'emoji']
    )
