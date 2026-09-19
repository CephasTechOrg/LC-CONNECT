"""add messages.edited_at + message_edits (report #5)

Revision ID: dd7dc4d01780
Revises: db4dc9136619
Create Date: 2026-09-18

Two changes, and the second is the one that matters.

`messages.edited_at` is display state — it drives the small "edited" label next to a timestamp.

`message_edits` is the audit trail, and it is **required, not optional**. Without it an edit
destroys evidence, and this codebase already treats that as unacceptable: a delete is soft
precisely so the body survives for moderation, and a safety report snapshots the reported text. An
edit with no history would be the one way to make a message say something it never said, with
nothing left to check it against.

It is purged on the same schedule as soft-deleted bodies (`MESSAGE_SOFT_DELETE_RETENTION_DAYS`),
so it does not quietly become a permanent record of everything anyone ever rephrased. That adds a
step to `architecture_review/MESSAGE_RETENTION_CRON_RUNBOOK.md`.

`ON DELETE CASCADE` on `message_id`: the history exists to explain a message, so it has no meaning
once the message row is gone. Note that a *soft* delete does not trigger it — the tombstone keeps
its row, and its edit history with it, which is exactly what moderation needs.

Both changes are additive and nullable/new, so no table rewrite and no backfill: an existing
message has never been edited, and `edited_at IS NULL` says so correctly.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = 'dd7dc4d01780'
down_revision = 'db4dc9136619'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('messages', sa.Column('edited_at', sa.DateTime(timezone=True), nullable=True))
    op.create_table(
        'message_edits',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            'message_id',
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey('messages.id', ondelete='CASCADE'),
            nullable=False,
        ),
        sa.Column('previous_body', sa.Text(), nullable=False),
        sa.Column('edited_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index('ix_message_edits_message_id', 'message_edits', ['message_id'])


def downgrade() -> None:
    op.drop_index('ix_message_edits_message_id', table_name='message_edits')
    op.drop_table('message_edits')
    op.drop_column('messages', 'edited_at')
