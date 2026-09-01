"""add campus_verified

Revision ID: e4f5a6b7c8d9
Revises: d3e4f5a6b7c8
Create Date: 2026-09-01

Admin-granted LC community badge (ADR-008 Phase 2). Separate from `is_verified`
(email OTP / account activation).
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision = 'e4f5a6b7c8d9'
down_revision = 'd3e4f5a6b7c8'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'users',
        sa.Column('campus_verified', sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.add_column('users', sa.Column('campus_verified_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('campus_verified_by_id', UUID(as_uuid=True), nullable=True))
    op.create_foreign_key(
        'fk_users_campus_verified_by_id_users',
        'users',
        'users',
        ['campus_verified_by_id'],
        ['id'],
        ondelete='SET NULL',
    )
    op.create_index('ix_users_campus_verified', 'users', ['campus_verified'], unique=False)
    op.alter_column('users', 'campus_verified', server_default=None)


def downgrade() -> None:
    op.drop_index('ix_users_campus_verified', table_name='users')
    op.drop_constraint('fk_users_campus_verified_by_id_users', 'users', type_='foreignkey')
    op.drop_column('users', 'campus_verified_by_id')
    op.drop_column('users', 'campus_verified_at')
    op.drop_column('users', 'campus_verified')
