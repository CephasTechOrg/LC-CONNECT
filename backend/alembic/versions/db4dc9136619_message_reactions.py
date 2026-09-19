"""add message_reactions (report #4)

Revision ID: db4dc9136619
Revises: 5f84eb1b9c13
Create Date: 2026-09-18

A table, not a JSON column on `messages`. The reason is concurrency: a blob cannot carry a unique
constraint, so two people reacting at the same instant would read-modify-write the same row and one
would lose. Toggling would also rewrite a hot row on every tap.

`UNIQUE (message_id, user_id, emoji)` is what makes a toggle idempotent — a double-tap cannot
create two rows, and the loser of a race catches IntegrityError and treats it as success, the same
arbiter pattern as message idempotency.

`(message_id, emoji)` serves the aggregate the message page runs: one grouped query over the whole
page's message ids, never one per message. With the API and database in the same region that is
~8-20ms; per-message it would have been fifty round trips.

`emoji` is `VARCHAR(8)` against a server-side allowlist rather than an enum table (a join on the
hottest read in the app) or free text (an abuse surface, and an unbounded per-message aggregate).

Both foreign keys CASCADE, including the one to `users` — deliberately unlike `messages.sender_id`.
A reaction is not a record of anything, so deleting an account should take its reactions with it,
where deleting an account must not delete its messages: those are half of someone else's
conversation.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = 'db4dc9136619'
down_revision = '5f84eb1b9c13'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'message_reactions',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            'message_id',
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey('messages.id', ondelete='CASCADE'),
            nullable=False,
        ),
        sa.Column(
            'user_id',
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey('users.id', ondelete='CASCADE'),
            nullable=False,
        ),
        sa.Column('emoji', sa.String(length=8), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint('message_id', 'user_id', 'emoji', name='uq_message_reaction'),
    )
    op.create_index('ix_message_reactions_message_id', 'message_reactions', ['message_id'])
    op.create_index('ix_message_reactions_user_id', 'message_reactions', ['user_id'])
    op.create_index(
        'ix_message_reactions_message_emoji', 'message_reactions', ['message_id', 'emoji']
    )


def downgrade() -> None:
    op.drop_index('ix_message_reactions_message_emoji', table_name='message_reactions')
    op.drop_index('ix_message_reactions_user_id', table_name='message_reactions')
    op.drop_index('ix_message_reactions_message_id', table_name='message_reactions')
    op.drop_table('message_reactions')
