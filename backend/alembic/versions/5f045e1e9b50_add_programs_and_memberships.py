"""add programs and program_memberships

Revision ID: 5f045e1e9b50
Revises: d2e3f4a5b6c7
Create Date: 2026-07-31

Foundation for the Blueprint Bond module (Presidential Scholars + employer partnership). A
`Program` is a school-run program a student can be enrolled in; `ProgramMembership` is the
admin-verified enrollment record — never self-declared. Seeds the single `presidential_scholars`
program row; no admin CRUD on `Program` itself yet (see docs/LC_CONNECT_BLUEPRINT_BOND_INTEGRATION_SPEC.md).
Additive + reversible.
"""

from __future__ import annotations

import uuid

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

from alembic import op

revision = '5f045e1e9b50'
down_revision = 'd2e3f4a5b6c7'
branch_labels = None
depends_on = None

PRESIDENTIAL_SCHOLARS_ID = uuid.uuid4()


def upgrade() -> None:
    op.create_table(
        'programs',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('slug', sa.String(60), nullable=False),
        sa.Column('name', sa.String(160), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint('slug', name='uq_programs_slug'),
    )
    op.create_index('ix_programs_slug', 'programs', ['slug'])

    op.create_table(
        'program_memberships',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('program_id', UUID(as_uuid=True), sa.ForeignKey('programs.id', ondelete='CASCADE'), nullable=False),
        sa.Column('status', sa.String(20), nullable=False, server_default='active'),
        sa.Column('verified_by_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('verified_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('revoked_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint('user_id', 'program_id', name='uq_program_membership_user_program'),
    )
    op.create_index('ix_program_memberships_user_id', 'program_memberships', ['user_id'])
    op.create_index('ix_program_memberships_program_id', 'program_memberships', ['program_id'])
    op.create_index('ix_program_memberships_status', 'program_memberships', ['status'])

    op.execute(
        sa.text(
            "INSERT INTO programs (id, slug, name, description, is_active) "
            "VALUES (:id, 'presidential_scholars', 'Presidential Scholars', "
            "'Blueprint Bond — Presidential Scholars program membership.', true)"
        ).bindparams(id=str(PRESIDENTIAL_SCHOLARS_ID))
    )


def downgrade() -> None:
    op.drop_index('ix_program_memberships_status', table_name='program_memberships')
    op.drop_index('ix_program_memberships_program_id', table_name='program_memberships')
    op.drop_index('ix_program_memberships_user_id', table_name='program_memberships')
    op.drop_table('program_memberships')
    op.drop_index('ix_programs_slug', table_name='programs')
    op.drop_table('programs')
