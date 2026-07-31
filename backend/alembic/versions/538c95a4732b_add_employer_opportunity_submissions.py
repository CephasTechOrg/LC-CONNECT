"""add employer_opportunity_submissions, campus_posts source/eligible_program_slug

Revision ID: 538c95a4732b
Revises: 60d27337c593
Create Date: 2026-07-31

Blueprint Bond Phase 5: employer opportunity submission + the existing-feed publication path.
`campus_posts.source` ('campus'|'employer') drives the source badge; `eligible_program_slug`
layers a Blueprint Bond-only visibility gate on top of the existing `audience` check (NULL for
every ordinary post — no behavior change for anything that isn't an approved employer opportunity).
Additive + reversible.
"""

from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

from alembic import op

revision = '538c95a4732b'
down_revision = '60d27337c593'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('campus_posts', sa.Column('source', sa.String(20), nullable=False, server_default='campus'))
    op.add_column('campus_posts', sa.Column('eligible_program_slug', sa.String(60), nullable=True))

    op.create_table(
        'employer_opportunity_submissions',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column(
            'organization_id',
            UUID(as_uuid=True),
            sa.ForeignKey('employer_organizations.id', ondelete='CASCADE'),
            nullable=False,
        ),
        sa.Column(
            'submitted_by_id',
            UUID(as_uuid=True),
            sa.ForeignKey('employer_accounts.id', ondelete='CASCADE'),
            nullable=False,
        ),
        sa.Column('title', sa.String(200), nullable=False),
        sa.Column('description', sa.Text(), nullable=False),
        sa.Column('category', sa.String(30), nullable=False),
        sa.Column('external_url', sa.Text(), nullable=True),
        sa.Column('status', sa.String(20), nullable=False, server_default='pending'),
        sa.Column('review_note', sa.Text(), nullable=True),
        sa.Column('reviewed_by_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('reviewed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            'published_post_id', UUID(as_uuid=True), sa.ForeignKey('campus_posts.id', ondelete='SET NULL'), nullable=True
        ),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index(
        'ix_employer_opportunity_submissions_organization_id',
        'employer_opportunity_submissions',
        ['organization_id'],
    )
    op.create_index(
        'ix_employer_opportunity_submissions_submitted_by_id',
        'employer_opportunity_submissions',
        ['submitted_by_id'],
    )
    op.create_index('ix_employer_opportunity_submissions_status', 'employer_opportunity_submissions', ['status'])


def downgrade() -> None:
    op.drop_index('ix_employer_opportunity_submissions_status', table_name='employer_opportunity_submissions')
    op.drop_index('ix_employer_opportunity_submissions_submitted_by_id', table_name='employer_opportunity_submissions')
    op.drop_index('ix_employer_opportunity_submissions_organization_id', table_name='employer_opportunity_submissions')
    op.drop_table('employer_opportunity_submissions')
    op.drop_column('campus_posts', 'eligible_program_slug')
    op.drop_column('campus_posts', 'source')
