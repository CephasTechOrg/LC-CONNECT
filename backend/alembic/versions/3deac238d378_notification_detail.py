"""add notifications.detail (short display token, currently the reaction emoji)

Revision ID: 3deac238d378
Revises: dd7dc4d01780
Create Date: 2026-09-19

A reaction notification has to say *which* reaction, and the structured columns cannot: `type`
names the kind, `actor_id` the person, `target_id` the conversation — none of them carry a value
belonging to this one event. Rendering the sentence server-side was the alternative, and the table
deliberately does not do that (see the model docstring: names would go stale).

Short and nullable on purpose. It is a display token, not a payload — nothing branches on it, and
anything that needs structure should get its own column rather than be encoded in here.
"""

import sqlalchemy as sa
from alembic import op

revision = '3deac238d378'
down_revision = 'dd7dc4d01780'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('notifications', sa.Column('detail', sa.String(length=16), nullable=True))


def downgrade() -> None:
    op.drop_column('notifications', 'detail')
