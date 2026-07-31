"""add admin_memberships

Revision ID: fca355e2d5c0
Revises: 7675b2828747
Create Date: 2026-07-31

Blueprint Bond Phase 3: the scoped admin permission system. `User.role == 'admin'` stays the base
gate (unchanged, still MFA-enforced); this table layers *which* scope(s) — super_admin,
school_admin, honors_admin, content_admin, auditor — an admin account actually holds. Additive +
reversible; no data migration (the very first Super Admin is seeded by the rewritten
`backend/scripts/create_admin.py`, not by this migration).
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision = 'fca355e2d5c0'
down_revision = '7675b2828747'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'admin_memberships',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('role', sa.String(30), nullable=False),
        sa.Column('status', sa.String(20), nullable=False, server_default='active'),
        sa.Column('invited_by_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('invited_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('revoked_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint('user_id', 'role', name='uq_admin_membership_user_role'),
    )
    op.create_index('ix_admin_memberships_user_id', 'admin_memberships', ['user_id'])
    op.create_index('ix_admin_memberships_role', 'admin_memberships', ['role'])
    op.create_index('ix_admin_memberships_status', 'admin_memberships', ['status'])


def downgrade() -> None:
    op.drop_index('ix_admin_memberships_status', table_name='admin_memberships')
    op.drop_index('ix_admin_memberships_role', table_name='admin_memberships')
    op.drop_index('ix_admin_memberships_user_id', table_name='admin_memberships')
    op.drop_table('admin_memberships')
