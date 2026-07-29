"""simplify campus post kinds

Revision ID: d6e7f8a9b0c1
Revises: a9b0c1d2e3f4
Create Date: 2026-07-28

Collapses the campus-post `kind` taxonomy to two clear types students see: `announcement` and
`opportunity`. The old `update`, `deadline`, and `alert` kinds all fold into `announcement` —
urgency is expressed by `priority` (urgent → the alert banner), not a separate kind. Data-only;
`kind` is a free String column so no type/enum change is needed.
"""

from __future__ import annotations

from alembic import op

revision = 'd6e7f8a9b0c1'
down_revision = 'a9b0c1d2e3f4'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        "UPDATE campus_posts SET kind = 'announcement' "
        "WHERE kind IN ('update', 'deadline', 'alert')"
    )


def downgrade() -> None:
    # Best-effort reverse: everything that isn't an opportunity becomes a generic 'update'.
    # The original update/deadline/alert distinction isn't recoverable.
    op.execute(
        "UPDATE campus_posts SET kind = 'update' "
        "WHERE kind = 'announcement'"
    )
