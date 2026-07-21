"""Initial schema

Revision ID: 3ffad56200ff
Revises:
Create Date: 2026-05-08 02:52:44.978941

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '3ffad56200ff'
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create base tables on a fresh database, or add OTP columns if users already exists."""
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    tables = set(inspector.get_table_names())

    if 'users' not in tables:
        # Fresh local DB: create the full schema from SQLAlchemy models.
        from app.database import Base
        import app.models  # noqa: F401

        Base.metadata.create_all(bind=conn)
        return

    columns = [c['name'] for c in inspector.get_columns('users')]
    if 'verify_otp_hash' not in columns:
        op.add_column('users', sa.Column('verify_otp_hash', sa.String(length=64), nullable=True))
    if 'verify_otp_expires_at' not in columns:
        op.add_column('users', sa.Column('verify_otp_expires_at', sa.DateTime(timezone=True), nullable=True))
    if 'reset_otp_hash' not in columns:
        op.add_column('users', sa.Column('reset_otp_hash', sa.String(length=64), nullable=True))
    if 'reset_otp_expires_at' not in columns:
        op.add_column('users', sa.Column('reset_otp_expires_at', sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    if 'users' not in inspector.get_table_names():
        return
    columns = {c['name'] for c in inspector.get_columns('users')}
    if 'reset_otp_expires_at' in columns:
        op.drop_column('users', 'reset_otp_expires_at')
    if 'reset_otp_hash' in columns:
        op.drop_column('users', 'reset_otp_hash')
    if 'verify_otp_expires_at' in columns:
        op.drop_column('users', 'verify_otp_expires_at')
    if 'verify_otp_hash' in columns:
        op.drop_column('users', 'verify_otp_hash')
