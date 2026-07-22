"""Add messages.client_message_id (idempotency) + keyset pagination index."""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = 'b2c3d4e5f6a7'
down_revision: str | None = 'a1b2c3d4e5f6'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column('messages', sa.Column('client_message_id', sa.UUID(), nullable=True))
    # Idempotency: partial-unique so existing rows (NULL) are exempt, new sends dedupe.
    op.create_index(
        'uq_messages_sender_client',
        'messages',
        ['sender_id', 'client_message_id'],
        unique=True,
        postgresql_where=sa.text('client_message_id IS NOT NULL'),
    )
    # Keyset pagination + reconnect sync: newest-first within a conversation.
    op.create_index(
        'ix_messages_match_created_id',
        'messages',
        ['match_id', sa.text('created_at DESC'), sa.text('id DESC')],
    )


def downgrade() -> None:
    op.drop_index('ix_messages_match_created_id', table_name='messages')
    op.drop_index('uq_messages_sender_client', table_name='messages')
    op.drop_column('messages', 'client_message_id')
