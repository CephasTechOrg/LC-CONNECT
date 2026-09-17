"""add notification inbox indexes (keyset listing + unread count)

Revision ID: e1a2b3c4d5e6
Revises: d9e0f1a2b3c4
Create Date: 2026-09-16

The notifications table shipped with three single-column indexes (`user_id`, `group_id`,
`created_at`) and nothing since has touched it, while the two queries the inbox actually runs are:

  * list  — WHERE user_id = ? ORDER BY created_at DESC, id DESC LIMIT n
  * badge — SELECT count(*) WHERE user_id = ? AND read_at IS NULL

Neither is served well by a single-column index: the list has to sort, and the count walks every
row for the user however many are already read. The messages table already solves the same two
shapes this way (`ix_messages_conversation_created_id` and the partial `ix_messages_unread`); this
brings notifications in line.

Both are created CONCURRENTLY: the table is small today, but an index build takes an ACCESS
EXCLUSIVE lock, and the inbox and its badge are on the app's startup path.
"""

from alembic import op

revision = 'e1a2b3c4d5e6'
down_revision = 'd9e0f1a2b3c4'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # CONCURRENTLY cannot run inside a transaction; Alembic wraps migrations in one by default.
    with op.get_context().autocommit_block():
        op.execute(
            'CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_notifications_user_created_id '
            'ON notifications (user_id, created_at DESC, id DESC)'
        )
        # Partial: holds only unread rows, so it stays small however much history accumulates.
        op.execute(
            'CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_notifications_unread '
            'ON notifications (user_id) WHERE read_at IS NULL'
        )

    # Superseded by the composite above, which can serve anything the single column could.
    op.execute('DROP INDEX IF EXISTS ix_notifications_created_at')


def downgrade() -> None:
    op.execute('CREATE INDEX IF NOT EXISTS ix_notifications_created_at ON notifications (created_at)')
    with op.get_context().autocommit_block():
        op.execute('DROP INDEX CONCURRENTLY IF EXISTS ix_notifications_unread')
        op.execute('DROP INDEX CONCURRENTLY IF EXISTS ix_notifications_user_created_id')
