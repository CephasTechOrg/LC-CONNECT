"""add user policy acceptance

Revision ID: a6b7c8d9e0f1
Revises: f5a6b7c8d9e0
Create Date: 2026-09-13

Records that a user accepted the Terms of Service and Privacy Policy, and which version.

`server_default='0'` is the point of this migration as much as the columns are: every existing
account becomes "has not accepted", so the acceptance gate catches accounts created before it
shipped rather than silently treating them as agreed. Raising `CURRENT_POLICY_VERSION` later has
the same effect for everyone at once.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = 'a6b7c8d9e0f1'
down_revision = 'f5a6b7c8d9e0'
branch_labels = None
depends_on = None


def _existing_columns() -> set[str]:
    return {c['name'] for c in sa.inspect(op.get_bind()).get_columns('users')}


def upgrade() -> None:
    # Skip what is already there. On a *fresh* database `3ffad56200ff_initial_schema` builds the
    # schema with `Base.metadata.create_all`, which creates the current model shape — these two
    # columns included — so a blind ADD COLUMN would fail with DuplicateColumn. On the deployed
    # database, stamped long past that point, both are genuinely missing and get added. Same
    # inspect-first pattern that migration itself uses.
    existing = _existing_columns()
    if 'policies_accepted_version' not in existing:
        op.add_column(
            'users',
            sa.Column('policies_accepted_version', sa.Integer(), nullable=False, server_default='0'),
        )
    if 'policies_accepted_at' not in existing:
        op.add_column(
            'users',
            sa.Column('policies_accepted_at', sa.DateTime(timezone=True), nullable=True),
        )


def downgrade() -> None:
    existing = _existing_columns()
    if 'policies_accepted_at' in existing:
        op.drop_column('users', 'policies_accepted_at')
    if 'policies_accepted_version' in existing:
        op.drop_column('users', 'policies_accepted_version')
