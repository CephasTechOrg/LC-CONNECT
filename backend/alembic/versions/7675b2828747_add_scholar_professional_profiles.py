"""add scholar_professional_profiles

Revision ID: 7675b2828747
Revises: 5f045e1e9b50
Create Date: 2026-07-31

Blueprint Bond Phase 2: the professional extension a verified Presidential Scholar can complete —
headshot/résumé (private-bucket object paths, never public URLs), LinkedIn/Handshake, summary,
skills, career interests, and employer-visibility consent. One row per user. Additive + reversible.
"""

from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import ARRAY, UUID

from alembic import op

revision = '7675b2828747'
down_revision = '5f045e1e9b50'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'scholar_professional_profiles',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('headshot_path', sa.Text(), nullable=True),
        sa.Column('resume_path', sa.Text(), nullable=True),
        sa.Column('linkedin_url', sa.String(300), nullable=True),
        sa.Column('handshake_url', sa.String(300), nullable=True),
        sa.Column('summary', sa.Text(), nullable=True),
        sa.Column('skills', ARRAY(sa.String(60)), nullable=False, server_default='{}'),
        sa.Column('career_interests', ARRAY(sa.String(60)), nullable=False, server_default='{}'),
        sa.Column('employer_visibility_consent', sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column('consent_given_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('consent_version', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint('user_id', name='uq_scholar_professional_profile_user'),
    )
    op.create_index(
        'ix_scholar_professional_profiles_user_id', 'scholar_professional_profiles', ['user_id']
    )


def downgrade() -> None:
    op.drop_index('ix_scholar_professional_profiles_user_id', table_name='scholar_professional_profiles')
    op.drop_table('scholar_professional_profiles')
