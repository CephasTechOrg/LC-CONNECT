"""backfill scholar consent_version for discovery gate

Revision ID: g1a2b3c4d5e6
Revises: f9a0b1c2d3e4
Create Date: 2026-10-19

Employer discovery now requires consent_version >= CURRENT_CONSENT_VERSION (1).
Scholars who already consented under the old boolean-only gate kept version 0 and
would otherwise vanish from the directory after this filter ships.
"""

from __future__ import annotations

from alembic import op

revision = 'g1a2b3c4d5e6'
down_revision = 'f9a0b1c2d3e4'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        UPDATE scholar_professional_profiles
        SET consent_version = 1
        WHERE employer_visibility_consent IS TRUE
          AND consent_version < 1
        """
    )


def downgrade() -> None:
    # Irreversible data backfill — leaving versions as-is is safe.
    pass
