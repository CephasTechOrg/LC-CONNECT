"""add conversation_members.pinned_at and conversation_members.archived_at

Revision ID: n8b9c0d1e2f3
Revises: m7a8b9c0d1e2
Create Date: 2026-10-29

Per-member inbox arrangement: pin a chat to the top (up to three) or archive it out of the main
list. Additive + reversible.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = 'n8b9c0d1e2f3'
down_revision = 'm7a8b9c0d1e2'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('conversation_members', sa.Column('pinned_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('conversation_members', sa.Column('archived_at', sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    op.drop_column('conversation_members', 'archived_at')
    op.drop_column('conversation_members', 'pinned_at')
