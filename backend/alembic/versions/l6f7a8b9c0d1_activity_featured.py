"""add activities.featured_until and activities.featured_by

Revision ID: l6f7a8b9c0d1
Revises: k5e6f7a8b9c0
Create Date: 2026-10-29

Lets an admin pin an activity as the featured one until a date. Without a pin the server picks
it by score, so every student sees the same featured activity (the app used to choose locally,
and the choice changed with the category filter). Additive + reversible.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = 'l6f7a8b9c0d1'
down_revision = 'k5e6f7a8b9c0'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('activities', sa.Column('featured_until', sa.DateTime(timezone=True), nullable=True))
    op.add_column(
        'activities',
        sa.Column(
            'featured_by',
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey('users.id', ondelete='SET NULL'),
            nullable=True,
        ),
    )


def downgrade() -> None:
    op.drop_column('activities', 'featured_by')
    op.drop_column('activities', 'featured_until')
