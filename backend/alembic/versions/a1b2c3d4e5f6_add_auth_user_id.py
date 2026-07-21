"""Add users.auth_user_id and allow nullable password_hash for Supabase Auth."""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = 'a1b2c3d4e5f6'
down_revision: str | None = '3ffad56200ff'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column('users', sa.Column('auth_user_id', sa.UUID(), nullable=True))
    op.create_index(
        'uq_users_auth_user_id',
        'users',
        ['auth_user_id'],
        unique=True,
        postgresql_where=sa.text('auth_user_id IS NOT NULL'),
    )
    op.alter_column('users', 'password_hash', existing_type=sa.String(length=255), nullable=True)


def downgrade() -> None:
    op.execute("UPDATE users SET password_hash = '' WHERE password_hash IS NULL")
    op.alter_column('users', 'password_hash', existing_type=sa.String(length=255), nullable=False)
    op.drop_index('uq_users_auth_user_id', table_name='users')
    op.drop_column('users', 'auth_user_id')
