"""add employer_opportunity_submissions.closes_at

Revision ID: m7a8b9c0d1e2
Revises: l6f7a8b9c0d1
Create Date: 2026-10-29

Employer opportunities had no closing date, so they never left the feed. New submissions carry
one (30 days by default) and it becomes the post's `expires_at`. Existing rows stay null and fall
under the 60-day rule for undated opportunities. Additive + reversible.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = 'm7a8b9c0d1e2'
down_revision = 'l6f7a8b9c0d1'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'employer_opportunity_submissions', sa.Column('closes_at', sa.DateTime(timezone=True), nullable=True)
    )


def downgrade() -> None:
    op.drop_column('employer_opportunity_submissions', 'closes_at')
