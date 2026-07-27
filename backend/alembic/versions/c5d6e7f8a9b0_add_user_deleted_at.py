"""add user deleted_at

Revision ID: c5d6e7f8a9b0
Revises: b4c5d6e7f8a9
Create Date: 2026-07-26

Audit stamp for self-service account deletion. When a user deletes their account the row is
anonymized in place (email/profile scrubbed, status='deleted', is_active=False) rather than
hard-deleted — a hard delete would cascade away other people's messages, groups, and activities.
`deleted_at` records when it happened. Additive + reversible.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = 'c5d6e7f8a9b0'
down_revision = 'b4c5d6e7f8a9'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('users', sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    op.drop_column('users', 'deleted_at')
