"""add conversation_members.last_delivered_message_id (per-member delivery boundary)

Revision ID: f2b3c4d5e6a7
Revises: e1a2b3c4d5e6
Create Date: 2026-09-17

Backs the third message tick (report #21). `MessageStatus` had sending / sent / read, and nothing
in the schema could source a "delivered" state: `delivered_at` existed nowhere.

The shape mirrors `last_read_message_id` on the same row, and for the same reason recorded in that
column's own comment — a single column on `messages` cannot express *who* has a message in an
N-member conversation. It is also deliberately not a `message_deliveries` table: that would be
messages x members rows to drive a tick, where a boundary is O(members).

Nullable with no backfill, on purpose. NULL means "nothing acknowledged yet", which is the honest
state for every existing row: delivery is advanced only by an explicit client acknowledgement, and
no client has ever sent one. Inventing a boundary from message history would claim deliveries that
were never confirmed.

`ON DELETE SET NULL` matches the read boundary: a hard-deleted message must not take the member row
with it, and losing the boundary degrades to "nothing acknowledged", which is safe.

The foreign key is declared **inline and unnamed**, the way `last_read_message_id` was
(`e5f6a7b8c9d0`), so PostgreSQL derives the same name it derives for the model's own unnamed FK.
Naming it explicitly here looked tidier and was wrong: `Base.metadata.create_all` produces the
server-derived name, so the downgrade could not find the constraint it was written to drop — caught
by `test_head_revision_downgrades_and_reapplies_without_drift`. Dropping the column takes its
constraint with it, so the downgrade needs nothing else.

Cheap by construction — adding a nullable column with no default is a catalogue-only change in
PostgreSQL, so there is no table rewrite regardless of size. The FK's validation scan is trivial
against an all-NULL column.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = 'f2b3c4d5e6a7'
down_revision = 'e1a2b3c4d5e6'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'conversation_members',
        sa.Column(
            'last_delivered_message_id',
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey('messages.id', ondelete='SET NULL'),
            nullable=True,
        ),
    )


def downgrade() -> None:
    op.drop_column('conversation_members', 'last_delivered_message_id')
