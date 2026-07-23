"""add group_id + message_id report targets (P5)

Revision ID: d0e1f2a3b4c5
Revises: c9d0e1f2a3b4
Create Date: 2026-07-23

Lets users report a group or a specific message, alongside the existing user/activity targets.
Additive nullable columns.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = 'd0e1f2a3b4c5'
down_revision = 'c9d0e1f2a3b4'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('reports', sa.Column('group_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('groups.id', ondelete='SET NULL'), nullable=True))
    op.add_column('reports', sa.Column('message_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('messages.id', ondelete='SET NULL'), nullable=True))
    op.create_index('ix_reports_group_id', 'reports', ['group_id'])
    op.create_index('ix_reports_message_id', 'reports', ['message_id'])


def downgrade() -> None:
    op.drop_index('ix_reports_message_id', table_name='reports')
    op.drop_index('ix_reports_group_id', table_name='reports')
    op.drop_column('reports', 'message_id')
    op.drop_column('reports', 'group_id')
