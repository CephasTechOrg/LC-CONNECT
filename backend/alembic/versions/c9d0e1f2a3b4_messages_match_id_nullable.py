"""make messages.match_id nullable for group messages (P4)

Revision ID: c9d0e1f2a3b4
Revises: b8c9d0e1f2a3
Create Date: 2026-07-23

Group messages have a conversation_id but no match. `conversation_id` is the universal
container; `match_id` is now DM-only (and nullable). Existing DM rows are unaffected.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = 'c9d0e1f2a3b4'
down_revision = 'b8c9d0e1f2a3'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column('messages', 'match_id', existing_type=postgresql.UUID(as_uuid=True), nullable=True)


def downgrade() -> None:
    # Only safe if no group messages exist; NULLs would block the NOT NULL restore.
    op.execute('DELETE FROM messages WHERE match_id IS NULL')
    op.alter_column('messages', 'match_id', existing_type=postgresql.UUID(as_uuid=True), nullable=False)
