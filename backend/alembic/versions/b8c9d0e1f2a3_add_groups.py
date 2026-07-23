"""add groups table (P3)

Revision ID: b8c9d0e1f2a3
Revises: a7b8c9d0e1f2
Create Date: 2026-07-23

A campus Group is a domain entity that owns a Conversation(kind='group'). Additive; membership
reuses conversation_members.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = 'b8c9d0e1f2a3'
down_revision = 'a7b8c9d0e1f2'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'groups',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('name', sa.String(length=120), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('avatar_url', sa.Text(), nullable=True),
        sa.Column('category', sa.String(length=30), nullable=False),
        sa.Column('visibility', sa.String(length=20), nullable=False, server_default='public'),
        sa.Column('join_policy', sa.String(length=20), nullable=False, server_default='approval'),
        sa.Column('owner_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column(
            'conversation_id',
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey('conversations.id', ondelete='CASCADE'),
            nullable=False,
            unique=True,
        ),
        sa.Column('max_members', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_groups_category', 'groups', ['category'])
    op.create_index('ix_groups_visibility', 'groups', ['visibility'])
    op.create_index('ix_groups_owner_id', 'groups', ['owner_id'])


def downgrade() -> None:
    op.drop_table('groups')
