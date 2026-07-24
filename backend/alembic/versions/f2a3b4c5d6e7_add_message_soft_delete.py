"""add message soft-delete

Revision ID: f2a3b4c5d6e7
Revises: e1f2a3b4c5d6
Create Date: 2026-07-24

Adds messages.deleted_at for "delete for everyone" (soft delete). Additive + reversible.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = 'f2a3b4c5d6e7'
down_revision = 'e1f2a3b4c5d6'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('messages', sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    op.drop_column('messages', 'deleted_at')
