"""add employer_organizations and employer_accounts

Revision ID: 60d27337c593
Revises: fca355e2d5c0
Create Date: 2026-07-31

Blueprint Bond Phase 4: employer partner registration + approval. `EmployerAccount` is
deliberately NOT a `User` row — a fully separate identity, never touching `users`/Supabase-Auth
until an Honors Admin approves the organization (see docs/LC_CONNECT_BLUEPRINT_BOND_INTEGRATION_SPEC.md
§11.0 for the reasoning). Additive + reversible.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision = '60d27337c593'
down_revision = 'fca355e2d5c0'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'employer_organizations',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('name', sa.String(200), nullable=False),
        sa.Column('status', sa.String(20), nullable=False, server_default='pending'),
        sa.Column('review_note', sa.Text(), nullable=True),
        sa.Column('reviewed_by_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('reviewed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_employer_organizations_status', 'employer_organizations', ['status'])

    op.create_table(
        'employer_accounts',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column(
            'organization_id',
            UUID(as_uuid=True),
            sa.ForeignKey('employer_organizations.id', ondelete='CASCADE'),
            nullable=False,
        ),
        sa.Column('email', sa.String(255), nullable=False),
        sa.Column('display_name', sa.String(120), nullable=True),
        sa.Column('auth_user_id', UUID(as_uuid=True), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint('email', name='uq_employer_accounts_email'),
    )
    op.create_index('ix_employer_accounts_organization_id', 'employer_accounts', ['organization_id'])
    op.create_index('ix_employer_accounts_email', 'employer_accounts', ['email'])
    op.create_index('ix_employer_accounts_auth_user_id', 'employer_accounts', ['auth_user_id'])


def downgrade() -> None:
    op.drop_index('ix_employer_accounts_auth_user_id', table_name='employer_accounts')
    op.drop_index('ix_employer_accounts_email', table_name='employer_accounts')
    op.drop_index('ix_employer_accounts_organization_id', table_name='employer_accounts')
    op.drop_table('employer_accounts')
    op.drop_index('ix_employer_organizations_status', table_name='employer_organizations')
    op.drop_table('employer_organizations')
