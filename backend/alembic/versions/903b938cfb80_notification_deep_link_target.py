"""add notifications.target_type / target_id (deep-linkable rows)

Revision ID: 903b938cfb80
Revises: f2b3c4d5e6a7
Create Date: 2026-09-18

Beta report #15: tapping a notification could only ever open the inbox. Group and connection rows
already carried `group_id` / `actor_id`, but the attendance fan-out inserted rows with **no target
at all** — so a notification about an open session could not open that session, and the scanner had
to re-guess which session was meant from "whichever is currently active".

A generic `(target_type, target_id)` pair rather than a typed foreign key per notification kind,
because the targets live in different tables — attendance sessions, campus posts, activities — so
no single FK can cover them, and one nullable FK per kind means a migration every time a
notification type is added.

No foreign key, therefore no referential integrity: a target can dangle once a session closes or a
post is deleted. That is the right trade here. The client has to handle a vanished target anyway,
and "that session has closed" is a better outcome than a cascade quietly deleting rows out of
someone's notification history.

Both columns nullable with no backfill. Existing rows genuinely have no target — the group and
actor columns already carry what they need — and inventing one would be a guess.

Catalogue-only in PostgreSQL (nullable, no default), so no table rewrite regardless of size.

The revision id is random rather than following the `a1b2c3...` pattern of its neighbours: that
pattern has run out of obvious next values and two hand-picked ids in a row collided with
existing revisions, which Alembic reports as a cycle rather than as a duplicate.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = '903b938cfb80'
down_revision = 'f2b3c4d5e6a7'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('notifications', sa.Column('target_type', sa.String(length=30), nullable=True))
    op.add_column(
        'notifications',
        sa.Column('target_id', postgresql.UUID(as_uuid=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column('notifications', 'target_id')
    op.drop_column('notifications', 'target_type')
