"""add match disconnected_at

Revision ID: c8d9e0f1a2b3
Revises: b7c8d9e0f1a2
Create Date: 2026-09-13

Soft disconnect for connections.

The row is flagged rather than deleted because `messages.match_id` is ON DELETE CASCADE: deleting
a match would erase the entire DM for both people, which is more destructive than blocking. It
would also break thread addressing, since `/messages/threads/{match_id}` keys on this row.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = 'c8d9e0f1a2b3'
down_revision = 'b7c8d9e0f1a2'
branch_labels = None
depends_on = None


def _columns() -> set[str]:
    return {c['name'] for c in sa.inspect(op.get_bind()).get_columns('matches')}


def upgrade() -> None:
    if 'disconnected_at' not in _columns():
        op.add_column('matches', sa.Column('disconnected_at', sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    if 'disconnected_at' in _columns():
        op.drop_column('matches', 'disconnected_at')
