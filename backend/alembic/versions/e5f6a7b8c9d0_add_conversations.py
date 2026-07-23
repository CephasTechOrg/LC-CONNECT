"""add conversations + conversation_members, backfill DMs from matches

Revision ID: e5f6a7b8c9d0
Revises: d4e5f6a7b8c9
Create Date: 2026-07-23

P1 of the groups plan — purely ADDITIVE:
- new `conversations` / `conversation_members` tables
- `messages.conversation_id` **nullable**; `messages.match_id` is left untouched
- backfills one DM conversation (+ its two members) per match and links every message

Nothing reads `conversation_id` yet (that is P2), so this migration cannot change behaviour.
Downgrade drops only the new structures — DMs keep working off `match_id`.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

from app.shared.conversation_backfill import BACKFILL_STATEMENTS

revision = 'e5f6a7b8c9d0'
down_revision = 'd4e5f6a7b8c9'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'conversations',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('kind', sa.String(length=20), nullable=False, server_default='dm'),
        sa.Column(
            'match_id',
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey('matches.id', ondelete='CASCADE'),
            nullable=True,
            unique=True,
        ),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_conversations_kind', 'conversations', ['kind'])

    op.create_table(
        'conversation_members',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            'conversation_id',
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey('conversations.id', ondelete='CASCADE'),
            nullable=False,
        ),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('role', sa.String(length=20), nullable=False, server_default='member'),
        sa.Column('status', sa.String(length=20), nullable=False, server_default='active'),
        sa.Column('invited_by', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('last_read_message_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('messages.id', ondelete='SET NULL'), nullable=True),
        sa.Column('muted', sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column('joined_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint('conversation_id', 'user_id', name='uq_conversation_member'),
    )
    op.create_index('ix_conversation_members_conversation_id', 'conversation_members', ['conversation_id'])
    op.create_index('ix_conversation_members_user_id', 'conversation_members', ['user_id'])
    op.create_index('ix_conversation_members_status', 'conversation_members', ['status'])

    op.add_column(
        'messages',
        sa.Column(
            'conversation_id',
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey('conversations.id', ondelete='CASCADE'),
            nullable=True,
        ),
    )
    op.create_index('ix_messages_conversation_id', 'messages', ['conversation_id'])

    # Data backfill — same statements the tests exercise.
    for statement in BACKFILL_STATEMENTS:
        op.execute(statement)


def downgrade() -> None:
    op.drop_index('ix_messages_conversation_id', table_name='messages')
    op.drop_column('messages', 'conversation_id')
    op.drop_table('conversation_members')
    op.drop_index('ix_conversations_kind', table_name='conversations')
    op.drop_table('conversations')
