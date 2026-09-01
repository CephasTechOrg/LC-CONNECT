"""add user contact_email

Revision ID: d3e4f5a6b7c8
Revises: c2d3e4f5a6b7
Create Date: 2026-09-01

Personal inbox for auth OTP delivery (ADR-008 Phase 1). Campus email stays on
`users.email` for identity and login; `contact_email` is where signup/recovery
codes are sent when student mail gateways block app mail.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = 'd3e4f5a6b7c8'
down_revision = 'c2d3e4f5a6b7'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('users', sa.Column('contact_email', sa.String(255), nullable=True))
    op.create_index('ix_users_contact_email', 'users', ['contact_email'], unique=False)


def downgrade() -> None:
    op.drop_index('ix_users_contact_email', table_name='users')
    op.drop_column('users', 'contact_email')
