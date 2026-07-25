"""add activity banner

Revision ID: b4c5d6e7f8a9
Revises: a3b4c5d6e7f8
Create Date: 2026-07-24

Adds activities.banner_url (optional event cover image). Additive + reversible.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = 'b4c5d6e7f8a9'
down_revision = 'a3b4c5d6e7f8'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('activities', sa.Column('banner_url', sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column('activities', 'banner_url')
