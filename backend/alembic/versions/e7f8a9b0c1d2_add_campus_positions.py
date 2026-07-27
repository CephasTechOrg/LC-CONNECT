"""add campus_positions

Revision ID: e7f8a9b0c1d2
Revises: d6e7f8a9b0c1
Create Date: 2026-07-27

Campus Hub Phase 2: verified campus identity stored separately from social profiles.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = 'e7f8a9b0c1d2'
down_revision = 'd6e7f8a9b0c1'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'campus_positions',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('category', sa.String(length=30), nullable=False),
        sa.Column('official_title', sa.String(length=160), nullable=False),
        sa.Column('department', sa.String(length=160), nullable=False),
        sa.Column('office_location', sa.String(length=160), nullable=True),
        sa.Column('phone', sa.String(length=40), nullable=True),
        sa.Column('contact_email', sa.String(length=255), nullable=False),
        sa.Column('availability', sa.Text(), nullable=True),
        sa.Column('bio', sa.Text(), nullable=True),
        sa.Column('status', sa.String(length=20), server_default='pending', nullable=False),
        sa.Column('is_primary', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('is_active', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('verified_by_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('verified_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('review_note', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['verified_by_id'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_campus_positions_user_id', 'campus_positions', ['user_id'])
    op.create_index('ix_campus_positions_category', 'campus_positions', ['category'])
    op.create_index('ix_campus_positions_status', 'campus_positions', ['status'])
    op.create_index(
        'uq_campus_positions_primary_active',
        'campus_positions',
        ['user_id'],
        unique=True,
        postgresql_where=sa.text('is_primary = true AND is_active = true'),
    )


def downgrade() -> None:
    op.drop_index('uq_campus_positions_primary_active', table_name='campus_positions')
    op.drop_index('ix_campus_positions_status', table_name='campus_positions')
    op.drop_index('ix_campus_positions_category', table_name='campus_positions')
    op.drop_index('ix_campus_positions_user_id', table_name='campus_positions')
    op.drop_table('campus_positions')
