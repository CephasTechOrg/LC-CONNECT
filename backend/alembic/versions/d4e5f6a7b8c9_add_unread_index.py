"""add partial index for unread-message counting

Revision ID: d4e5f6a7b8c9
Revises: c3d4e5f6a7b8
Create Date: 2026-07-23

Partial index on (match_id, sender_id) WHERE read_at IS NULL — keeps only unread rows,
so the unread-summary grouped query stays small and fast.
"""

from alembic import op

revision = 'd4e5f6a7b8c9'
down_revision = 'c3d4e5f6a7b8'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_index(
        'ix_messages_unread',
        'messages',
        ['match_id', 'sender_id'],
        unique=False,
        postgresql_where='read_at IS NULL',
    )


def downgrade() -> None:
    op.drop_index('ix_messages_unread', table_name='messages')
