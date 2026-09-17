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

Built with a plain `CREATE INDEX`, **not** `CONCURRENTLY`, for two reasons specific to this
deployment:

* Production connects through Supabase's transaction pooler (pgbouncer, port 6543). `CREATE INDEX
  CONCURRENTLY` cannot run inside a transaction block, and transaction-mode pooling gives no
  guarantee a statement runs outside one — so it is unreliable there by construction.
* A `CONCURRENTLY` build that fails part-way leaves an **INVALID** index behind. Combined with
  `IF NOT EXISTS`, a retry would then skip it silently and the index would never be used again —
  a permanent, invisible regression.

The lock a plain build takes is ACCESS EXCLUSIVE, which is the usual argument for CONCURRENTLY. It
does not apply at this size: `notifications` holds a few thousand rows in beta, so the build is
milliseconds. Revisit only if this table grows large enough for the lock to be felt, and if it
does, run the index build as a separate operational step rather than inside a deploy.
"""

from alembic import op

revision = 'e1a2b3c4d5e6'
down_revision = 'd9e0f1a2b3c4'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        'CREATE INDEX IF NOT EXISTS ix_notifications_user_created_id '
        'ON notifications (user_id, created_at DESC, id DESC)'
    )
    # Partial: holds only unread rows, so it stays small however much history accumulates.
    op.execute(
        'CREATE INDEX IF NOT EXISTS ix_notifications_unread '
        'ON notifications (user_id) WHERE read_at IS NULL'
    )
    # Superseded by the composite above, which can serve anything the single column could.
    op.execute('DROP INDEX IF EXISTS ix_notifications_created_at')


def downgrade() -> None:
    op.execute('CREATE INDEX IF NOT EXISTS ix_notifications_created_at ON notifications (created_at)')
    op.execute('DROP INDEX IF EXISTS ix_notifications_unread')
    op.execute('DROP INDEX IF EXISTS ix_notifications_user_created_id')
