"""retire the open_connection looking-for option

Revision ID: d9e0f1a2b3c4
Revises: c8d9e0f1a2b3
Create Date: 2026-09-13

The "Looking for" set is now labelled "I'm open to" and is campus-shaped. `open_connection`
("Open Connection") is dropped: it meant nothing concrete, and together with the old label it made
a student platform read like a dating app.

Any selections of it disappear with it: `user_looking_for.option_id` is ON DELETE CASCADE.
Renaming 'Events' to 'Campus events' is handled by `seed_lookup_data`, which now refreshes names
on rows it already created rather than only inserting missing ones.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = 'd9e0f1a2b3c4'
down_revision = 'c8d9e0f1a2b3'
branch_labels = None
depends_on = None

_RETIRED = ('open_connection',)


def upgrade() -> None:
    op.get_bind().execute(
        sa.text('DELETE FROM looking_for_options WHERE code = ANY(:codes)'),
        {'codes': list(_RETIRED)},
    )


def downgrade() -> None:
    # Re-creates the option but not anyone's selection of it — that information is gone.
    op.execute(
        "INSERT INTO looking_for_options (code, name) VALUES ('open_connection', 'Open Connection') "
        "ON CONFLICT DO NOTHING"
    )
