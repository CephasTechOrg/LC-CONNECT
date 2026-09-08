"""add campus post link preview columns

Revision ID: f5a6b7c8d9e0
Revises: e4f5a6b7c8d9
Create Date: 2026-09-07

Server-stored Open Graph / meta preview for `campus_posts.external_url`
(opportunities link-preview V1). Nullable; existing rows unchanged until
backfill (Phase 2) or next create/update.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = 'f5a6b7c8d9e0'
down_revision = 'e4f5a6b7c8d9'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('campus_posts', sa.Column('link_preview_domain', sa.String(length=253), nullable=True))
    op.add_column('campus_posts', sa.Column('link_preview_site_name', sa.String(length=200), nullable=True))
    op.add_column('campus_posts', sa.Column('link_preview_title', sa.String(length=200), nullable=True))
    op.add_column('campus_posts', sa.Column('link_preview_description', sa.String(length=400), nullable=True))
    op.add_column('campus_posts', sa.Column('link_preview_image_url', sa.Text(), nullable=True))
    op.add_column('campus_posts', sa.Column('link_preview_fetched_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('campus_posts', sa.Column('link_preview_status', sa.String(length=20), nullable=True))


def downgrade() -> None:
    op.drop_column('campus_posts', 'link_preview_status')
    op.drop_column('campus_posts', 'link_preview_fetched_at')
    op.drop_column('campus_posts', 'link_preview_image_url')
    op.drop_column('campus_posts', 'link_preview_description')
    op.drop_column('campus_posts', 'link_preview_title')
    op.drop_column('campus_posts', 'link_preview_site_name')
    op.drop_column('campus_posts', 'link_preview_domain')
