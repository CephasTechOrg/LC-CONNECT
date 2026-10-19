"""add scholar internships and projects JSON columns

Revision ID: e8f9a0b1c2d3
Revises: 3deac238d378
Create Date: 2026-10-19

Blueprint Bond Wave B: optional structured experience (internships) and projects on the
professional profile. JSONB lists — optional for completeness; employers see them when present.
"""

from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

from alembic import op

revision = 'e8f9a0b1c2d3'
down_revision = '3deac238d378'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'scholar_professional_profiles',
        sa.Column('internships', JSONB(), nullable=False, server_default=sa.text("'[]'::jsonb")),
    )
    op.add_column(
        'scholar_professional_profiles',
        sa.Column('projects', JSONB(), nullable=False, server_default=sa.text("'[]'::jsonb")),
    )


def downgrade() -> None:
    op.drop_column('scholar_professional_profiles', 'projects')
    op.drop_column('scholar_professional_profiles', 'internships')
