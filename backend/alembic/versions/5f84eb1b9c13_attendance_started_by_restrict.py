"""attendance_sessions.started_by_id: ON DELETE SET NULL → RESTRICT

Revision ID: 5f84eb1b9c13
Revises: 903b938cfb80
Create Date: 2026-09-18

Review Part 3 finding #1. The column was created `NOT NULL` with `ON DELETE SET NULL`, which is
incoherent — the cascade can never execute. A hard user deletion therefore failed with a not-null
violation rather than a foreign-key error naming the real obstacle, and the intent was unreadable
from the schema.

Of the two coherent options, `RESTRICT` suits the data. An attendance session is an audit record of
who opened a class:

* `SET NULL` would need the column nullable, and `started_by_id` nullable in the API response, and
  it trades away the record of who started the session.
* `CASCADE` would delete attendance history along with an instructor's account.
* `RESTRICT` keeps the record complete and refuses the delete with a clear reason.

It should never fire in practice: accounts are soft-deleted (`users.deleted_at`), which is why this
sat latent rather than breaking anything. The point is that the constraint now says what it means.

The constraint name is PostgreSQL's default for the inline foreign key created in `c2d3e4f5a6b7`.
"""

from alembic import op

revision = '5f84eb1b9c13'
down_revision = '903b938cfb80'
branch_labels = None
depends_on = None

_CONSTRAINT = 'attendance_sessions_started_by_id_fkey'


def upgrade() -> None:
    op.drop_constraint(_CONSTRAINT, 'attendance_sessions', type_='foreignkey')
    op.create_foreign_key(
        _CONSTRAINT,
        'attendance_sessions',
        'users',
        ['started_by_id'],
        ['id'],
        ondelete='RESTRICT',
    )


def downgrade() -> None:
    op.drop_constraint(_CONSTRAINT, 'attendance_sessions', type_='foreignkey')
    op.create_foreign_key(
        _CONSTRAINT,
        'attendance_sessions',
        'users',
        ['started_by_id'],
        ['id'],
        ondelete='SET NULL',
    )
