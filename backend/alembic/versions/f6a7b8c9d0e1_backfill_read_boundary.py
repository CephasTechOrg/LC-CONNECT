"""backfill last_read_message_id from existing read_at (P2 read-state parity)

Revision ID: f6a7b8c9d0e1
Revises: e5f6a7b8c9d0
Create Date: 2026-07-23

P2 moves unread from per-message `read_at` to the per-member `last_read_message_id` boundary.
This data-only migration seeds that boundary from existing `read_at` so already-read messages
stay read after the cutover. Idempotent (only fills NULL boundaries). No schema change.
"""

from alembic import op

from app.shared.conversation_backfill import READ_BOUNDARY_BACKFILL

revision = 'f6a7b8c9d0e1'
down_revision = 'e5f6a7b8c9d0'
branch_labels = None
depends_on = None


def upgrade() -> None:
    for statement in READ_BOUNDARY_BACKFILL:
        op.execute(statement)


def downgrade() -> None:
    # The boundary is derived data; clearing it is safe (read_at is still the source).
    op.execute('UPDATE conversation_members SET last_read_message_id = NULL')
