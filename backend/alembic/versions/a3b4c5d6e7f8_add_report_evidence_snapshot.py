"""add report evidence snapshot

Revision ID: a3b4c5d6e7f8
Revises: f2a3b4c5d6e7
Create Date: 2026-07-24

Snapshots the reported message's text into the report so evidence survives the message (or its
group) being deleted later. Additive + reversible.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = 'a3b4c5d6e7f8'
down_revision = 'f2a3b4c5d6e7'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('reports', sa.Column('message_body', sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column('reports', 'message_body')
