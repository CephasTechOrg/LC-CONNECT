"""add campus_posts and campus_resources

Revision ID: a9b0c1d2e3f4
Revises: f8a9b0c1d2e3
Create Date: 2026-07-27

Campus Hub Phase 5: official posts and evergreen resources.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = 'a9b0c1d2e3f4'
down_revision = 'f8a9b0c1d2e3'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'campus_posts',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('author_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('kind', sa.String(length=20), nullable=False),
        sa.Column('title', sa.String(length=200), nullable=False),
        sa.Column('summary', sa.String(length=400), nullable=True),
        sa.Column('body', sa.Text(), nullable=False),
        sa.Column('audience', sa.String(length=20), server_default='all', nullable=False),
        sa.Column('category', sa.String(length=30), nullable=True),
        sa.Column('priority', sa.String(length=20), server_default='normal', nullable=False),
        sa.Column('status', sa.String(length=20), server_default='draft', nullable=False),
        sa.Column('publish_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('external_url', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['author_id'], ['users.id'], ondelete='RESTRICT'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_campus_posts_author_id', 'campus_posts', ['author_id'])
    op.create_index('ix_campus_posts_kind', 'campus_posts', ['kind'])
    op.create_index('ix_campus_posts_audience', 'campus_posts', ['audience'])
    op.create_index('ix_campus_posts_category', 'campus_posts', ['category'])
    op.create_index('ix_campus_posts_priority', 'campus_posts', ['priority'])
    op.create_index('ix_campus_posts_status', 'campus_posts', ['status'])
    op.create_index('ix_campus_posts_publish_at', 'campus_posts', ['publish_at'])
    op.create_index('ix_campus_posts_expires_at', 'campus_posts', ['expires_at'])

    op.create_table(
        'campus_resources',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('category', sa.String(length=30), nullable=False),
        sa.Column('title', sa.String(length=200), nullable=False),
        sa.Column('description', sa.Text(), nullable=False),
        sa.Column('location', sa.String(length=200), nullable=True),
        sa.Column('hours', sa.String(length=200), nullable=True),
        sa.Column('contact_email', sa.String(length=255), nullable=True),
        sa.Column('phone', sa.String(length=40), nullable=True),
        sa.Column('external_url', sa.Text(), nullable=True),
        sa.Column('sort_order', sa.Integer(), server_default='0', nullable=False),
        sa.Column('is_active', sa.Boolean(), server_default=sa.text('true'), nullable=False),
        sa.Column('updated_by_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['updated_by_id'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_campus_resources_category', 'campus_resources', ['category'])
    op.create_index('ix_campus_resources_is_active', 'campus_resources', ['is_active'])


def downgrade() -> None:
    op.drop_index('ix_campus_resources_is_active', table_name='campus_resources')
    op.drop_index('ix_campus_resources_category', table_name='campus_resources')
    op.drop_table('campus_resources')
    op.drop_index('ix_campus_posts_expires_at', table_name='campus_posts')
    op.drop_index('ix_campus_posts_publish_at', table_name='campus_posts')
    op.drop_index('ix_campus_posts_status', table_name='campus_posts')
    op.drop_index('ix_campus_posts_priority', table_name='campus_posts')
    op.drop_index('ix_campus_posts_category', table_name='campus_posts')
    op.drop_index('ix_campus_posts_audience', table_name='campus_posts')
    op.drop_index('ix_campus_posts_kind', table_name='campus_posts')
    op.drop_index('ix_campus_posts_author_id', table_name='campus_posts')
    op.drop_table('campus_posts')
