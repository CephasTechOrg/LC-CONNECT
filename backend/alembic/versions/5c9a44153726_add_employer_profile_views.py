"""add employer_profile_views

Revision ID: 5c9a44153726
Revises: 538c95a4732b
Create Date: 2026-07-31

Blueprint Bond Phase 6: audit trail for approved employers viewing a scholar's professional view.
Additive + reversible.
"""

from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

from alembic import op

revision = '5c9a44153726'
down_revision = '538c95a4732b'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'employer_profile_views',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column(
            'employer_account_id',
            UUID(as_uuid=True),
            sa.ForeignKey('employer_accounts.id', ondelete='CASCADE'),
            nullable=False,
        ),
        sa.Column('scholar_user_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('viewed_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_employer_profile_views_employer_account_id', 'employer_profile_views', ['employer_account_id'])
    op.create_index('ix_employer_profile_views_scholar_user_id', 'employer_profile_views', ['scholar_user_id'])


def downgrade() -> None:
    op.drop_index('ix_employer_profile_views_scholar_user_id', table_name='employer_profile_views')
    op.drop_index('ix_employer_profile_views_employer_account_id', table_name='employer_profile_views')
    op.drop_table('employer_profile_views')
