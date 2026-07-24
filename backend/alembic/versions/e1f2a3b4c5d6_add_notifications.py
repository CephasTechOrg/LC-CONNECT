"""add notifications

Revision ID: e1f2a3b4c5d6
Revises: d0e1f2a3b4c5
Create Date: 2026-07-24

In-app notifications (group invites, approvals, role changes, removals). Additive + reversible.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision = 'e1f2a3b4c5d6'
down_revision = 'd0e1f2a3b4c5'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'notifications',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('type', sa.String(length=40), nullable=False),
        sa.Column('group_id', UUID(as_uuid=True), sa.ForeignKey('groups.id', ondelete='CASCADE'), nullable=True),
        sa.Column('actor_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('read_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_notifications_user_id', 'notifications', ['user_id'])
    op.create_index('ix_notifications_group_id', 'notifications', ['group_id'])
    op.create_index('ix_notifications_created_at', 'notifications', ['created_at'])


def downgrade() -> None:
    op.drop_index('ix_notifications_created_at', table_name='notifications')
    op.drop_index('ix_notifications_group_id', table_name='notifications')
    op.drop_index('ix_notifications_user_id', table_name='notifications')
    op.drop_table('notifications')
