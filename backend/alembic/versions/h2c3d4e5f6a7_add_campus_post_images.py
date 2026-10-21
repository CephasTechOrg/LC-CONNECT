"""add campus_post_images

Revision ID: h2c3d4e5f6a7
Revises: g1a2b3c4d5e6
Create Date: 2026-10-21

Optional sanitized JPEGs on campus posts (announcements). Cover is sort_order 0; unique
(post_id, sort_order) with a 0–3 check so a post cannot store more than four images.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision = 'h2c3d4e5f6a7'
down_revision = 'g1a2b3c4d5e6'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'campus_post_images',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column(
            'post_id',
            UUID(as_uuid=True),
            sa.ForeignKey('campus_posts.id', ondelete='CASCADE'),
            nullable=False,
        ),
        sa.Column('sort_order', sa.Integer(), nullable=False),
        sa.Column('object_path', sa.String(400), nullable=False),
        sa.Column('public_url', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint('post_id', 'sort_order', name='uq_campus_post_image_sort'),
        sa.CheckConstraint('sort_order >= 0 AND sort_order <= 3', name='ck_campus_post_image_sort'),
    )
    op.create_index('ix_campus_post_images_post_id', 'campus_post_images', ['post_id'])


def downgrade() -> None:
    op.drop_index('ix_campus_post_images_post_id', table_name='campus_post_images')
    op.drop_table('campus_post_images')
