"""add campus_post_reads

Revision ID: e7f8a9b0c1d2
Revises: d6e7f8a9b0c1
Create Date: 2026-07-29

Per-user read markers for campus posts (announcements). Campus posts are shared rows, so read
state can't live on the post — this join table records that a user has read a given post. The
unread badge = visible announcements with no row here for the user. Additive + reversible.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision = 'e7f8a9b0c1d2'
down_revision = 'd6e7f8a9b0c1'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'campus_post_reads',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('post_id', UUID(as_uuid=True), sa.ForeignKey('campus_posts.id', ondelete='CASCADE'), nullable=False),
        sa.Column('read_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint('user_id', 'post_id', name='uq_campus_post_read'),
    )
    op.create_index('ix_campus_post_reads_user_id', 'campus_post_reads', ['user_id'])
    op.create_index('ix_campus_post_reads_post_id', 'campus_post_reads', ['post_id'])


def downgrade() -> None:
    op.drop_index('ix_campus_post_reads_post_id', table_name='campus_post_reads')
    op.drop_index('ix_campus_post_reads_user_id', table_name='campus_post_reads')
    op.drop_table('campus_post_reads')
