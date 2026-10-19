"""add scholar professional profile review status

Revision ID: f9a0b1c2d3e4
Revises: e8f9a0b1c2d3
Create Date: 2026-10-19

Wave C: Honors admin must approve a Blueprint Bond profile before employer partners see it.
Statuses: draft → pending_review → approved | changes_requested; admin may revoke.
Existing rows that already opted into employer visibility are backfilled to approved so we do
not silently hide scholars who were live before this gate shipped.
"""

from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

from alembic import op

revision = 'f9a0b1c2d3e4'
down_revision = 'e8f9a0b1c2d3'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'scholar_professional_profiles',
        sa.Column('review_status', sa.String(length=30), nullable=False, server_default='draft'),
    )
    op.add_column('scholar_professional_profiles', sa.Column('review_note', sa.Text(), nullable=True))
    op.add_column(
        'scholar_professional_profiles',
        sa.Column('submitted_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        'scholar_professional_profiles',
        sa.Column('reviewed_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        'scholar_professional_profiles',
        sa.Column('reviewed_by_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
    )
    op.create_index(
        'ix_scholar_professional_profiles_review_status',
        'scholar_professional_profiles',
        ['review_status'],
    )
    # Preserve visibility for scholars who were already discoverable under the old consent-only rule.
    op.execute(
        """
        UPDATE scholar_professional_profiles
        SET review_status = 'approved',
            reviewed_at = COALESCE(reviewed_at, NOW())
        WHERE employer_visibility_consent IS TRUE
          AND review_status = 'draft'
        """
    )


def downgrade() -> None:
    op.drop_index('ix_scholar_professional_profiles_review_status', table_name='scholar_professional_profiles')
    op.drop_column('scholar_professional_profiles', 'reviewed_by_id')
    op.drop_column('scholar_professional_profiles', 'reviewed_at')
    op.drop_column('scholar_professional_profiles', 'submitted_at')
    op.drop_column('scholar_professional_profiles', 'review_note')
    op.drop_column('scholar_professional_profiles', 'review_status')
