"""add employer agreement acceptance

Revision ID: b7c8d9e0f1a2
Revises: a6b7c8d9e0f1
Create Date: 2026-09-13

Records that an employer account accepted the Employer Agreement, and which version.

Tracked separately from the users' policy acceptance: the employer agreement changes on its own
schedule. `server_default='0'` gates every existing employer account on next sign-in rather than
assuming agreement nobody actually gave — which matters more here than on the student side,
because this is what stands between an approved employer account and student résumés.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = 'b7c8d9e0f1a2'
down_revision = 'a6b7c8d9e0f1'
branch_labels = None
depends_on = None


def _existing_columns() -> set[str]:
    return {c['name'] for c in sa.inspect(op.get_bind()).get_columns('employer_accounts')}


def upgrade() -> None:
    # Inspect first: on a fresh database `3ffad56200ff_initial_schema` builds the whole schema with
    # `Base.metadata.create_all`, so these columns already exist and a blind ADD would fail.
    existing = _existing_columns()
    if 'agreement_accepted_version' not in existing:
        op.add_column(
            'employer_accounts',
            sa.Column('agreement_accepted_version', sa.Integer(), nullable=False, server_default='0'),
        )
    if 'agreement_accepted_at' not in existing:
        op.add_column(
            'employer_accounts',
            sa.Column('agreement_accepted_at', sa.DateTime(timezone=True), nullable=True),
        )


def downgrade() -> None:
    existing = _existing_columns()
    if 'agreement_accepted_at' in existing:
        op.drop_column('employer_accounts', 'agreement_accepted_at')
    if 'agreement_accepted_version' in existing:
        op.drop_column('employer_accounts', 'agreement_accepted_version')
