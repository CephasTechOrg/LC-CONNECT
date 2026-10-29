"""add scholar_professional_profiles.headshot_updated_at

Revision ID: k5e6f7a8b9c0
Revises: j4d5e6f7a8b9
Create Date: 2026-10-29

The headshot is a private object at a fixed path, read through a fresh signed URL every time, so
a client had nothing stable to cache it under and downloaded it again on every visit. This
timestamp changes only on upload and is the client's cache key. Existing headshots get their
row's `updated_at` as a starting value. Additive + reversible.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = 'k5e6f7a8b9c0'
down_revision = 'j4d5e6f7a8b9'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'scholar_professional_profiles',
        sa.Column('headshot_updated_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.execute(
        'UPDATE scholar_professional_profiles SET headshot_updated_at = updated_at '
        'WHERE headshot_path IS NOT NULL'
    )


def downgrade() -> None:
    op.drop_column('scholar_professional_profiles', 'headshot_updated_at')
