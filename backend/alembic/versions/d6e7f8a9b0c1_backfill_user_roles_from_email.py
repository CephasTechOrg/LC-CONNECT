"""backfill user roles from email domain

Revision ID: d6e7f8a9b0c1
Revises: c5d6e7f8a9b0
Create Date: 2026-07-27

Campus Hub Phase 1: existing @livingstone.edu accounts that still have the default
`student` role are promoted to `staff`. Admins and @students.livingstone.edu accounts
are untouched. New signups get the correct role at bootstrap time.
"""

from __future__ import annotations

from alembic import op

revision = 'd6e7f8a9b0c1'
down_revision = 'c5d6e7f8a9b0'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        UPDATE users
        SET role = 'staff'
        WHERE role = 'student'
          AND lower(split_part(email, '@', 2)) = 'livingstone.edu'
        """
    )


def downgrade() -> None:
    # Cannot safely reverse — some staff accounts may have been created after upgrade.
    pass
