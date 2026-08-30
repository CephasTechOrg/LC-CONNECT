"""add suspension_appeals

Revision ID: b1c2d3e4f5a6
Revises: a0b1c2d3e4f5
Create Date: 2026-08-30
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = 'b1c2d3e4f5a6'
down_revision = 'a0b1c2d3e4f5'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'suspension_appeals',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('message', sa.Text(), nullable=False),
        sa.Column('status', sa.String(length=20), server_default='open', nullable=False),
        sa.Column('admin_note', sa.Text(), nullable=True),
        sa.Column('reviewed_by_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('reviewed_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index('ix_suspension_appeals_user_id', 'suspension_appeals', ['user_id'])
    op.create_index('ix_suspension_appeals_status', 'suspension_appeals', ['status'])
    op.create_index('ix_suspension_appeals_created_at', 'suspension_appeals', ['created_at'])


def downgrade() -> None:
    op.drop_index('ix_suspension_appeals_created_at', table_name='suspension_appeals')
    op.drop_index('ix_suspension_appeals_status', table_name='suspension_appeals')
    op.drop_index('ix_suspension_appeals_user_id', table_name='suspension_appeals')
    op.drop_table('suspension_appeals')
