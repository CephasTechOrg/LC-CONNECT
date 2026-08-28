"""Drop retired password/OTP credential columns from users (#20).

Revision ID: a0b1c2d3e4f5
Revises: 5c9a44153726
Create Date: 2026-08-27

Prerequisite: architecture_review/AUTH_USER_LINKING_RUNBOOK.md gate OK
(`python scripts/link_auth_users.py` reports every live account has auth_user_id).

Auth is Supabase-only; these columns are unused and should not hold secrets.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = 'a0b1c2d3e4f5'
down_revision = '5c9a44153726'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_column('users', 'reset_otp_expires_at')
    op.drop_column('users', 'reset_otp_hash')
    op.drop_column('users', 'verify_otp_expires_at')
    op.drop_column('users', 'verify_otp_hash')
    op.drop_column('users', 'password_hash')


def downgrade() -> None:
    op.add_column('users', sa.Column('password_hash', sa.String(length=255), nullable=True))
    op.add_column('users', sa.Column('verify_otp_hash', sa.String(length=64), nullable=True))
    op.add_column(
        'users',
        sa.Column('verify_otp_expires_at', sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column('users', sa.Column('reset_otp_hash', sa.String(length=64), nullable=True))
    op.add_column(
        'users',
        sa.Column('reset_otp_expires_at', sa.DateTime(timezone=True), nullable=True),
    )
