"""add attendance_sessions, attendance_records, attendance_audit_logs

Revision ID: c2d3e4f5a6b7
Revises: b1c2d3e4f5a6
Create Date: 2026-08-31

Honors attendance Phase 1 — durable session/record tables. Student eligibility and instructor
access reuse existing `program_memberships` and `honors_admin`; no parallel enrollment tables.
Partial unique index enforces one open session per program (V1).
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = 'c2d3e4f5a6b7'
down_revision = 'b1c2d3e4f5a6'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'attendance_sessions',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('program_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('programs.id', ondelete='CASCADE'), nullable=False),
        sa.Column('title', sa.String(length=160), nullable=False),
        sa.Column('started_by_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=False),
        sa.Column('opened_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('present_until', sa.DateTime(timezone=True), nullable=False),
        sa.Column('late_until', sa.DateTime(timezone=True), nullable=True),
        sa.Column('closed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('status', sa.String(length=20), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    )
    op.create_index('ix_attendance_sessions_program_id', 'attendance_sessions', ['program_id'])
    op.create_index('ix_attendance_sessions_started_by_id', 'attendance_sessions', ['started_by_id'])
    op.create_index('ix_attendance_sessions_status', 'attendance_sessions', ['status'])
    op.create_index('ix_attendance_sessions_program_status', 'attendance_sessions', ['program_id', 'status'])
    op.create_index(
        'uq_attendance_session_one_open_per_program',
        'attendance_sessions',
        ['program_id'],
        unique=True,
        postgresql_where=sa.text("status = 'open'"),
    )

    op.create_table(
        'attendance_records',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('session_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('attendance_sessions.id', ondelete='CASCADE'), nullable=False),
        sa.Column('student_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('status', sa.String(length=20), nullable=False),
        sa.Column('verification_method', sa.String(length=20), nullable=False),
        sa.Column('checked_in_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('original_checked_in_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('manually_modified', sa.Boolean(), server_default=sa.false(), nullable=False),
        sa.Column('modified_by_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('modified_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('modification_reason', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.UniqueConstraint('session_id', 'student_id', name='uq_attendance_record_session_student'),
    )
    op.create_index('ix_attendance_records_session_id', 'attendance_records', ['session_id'])
    op.create_index('ix_attendance_records_student_id', 'attendance_records', ['student_id'])

    op.create_table(
        'attendance_audit_logs',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('attendance_record_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('attendance_records.id', ondelete='CASCADE'), nullable=False),
        sa.Column('changed_by_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('previous_status', sa.String(length=20), nullable=False),
        sa.Column('new_status', sa.String(length=20), nullable=False),
        sa.Column('reason', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    )
    op.create_index('ix_attendance_audit_logs_attendance_record_id', 'attendance_audit_logs', ['attendance_record_id'])
    op.create_index('ix_attendance_audit_logs_changed_by_id', 'attendance_audit_logs', ['changed_by_id'])
    op.create_index('ix_attendance_audit_logs_created_at', 'attendance_audit_logs', ['created_at'])


def downgrade() -> None:
    op.drop_index('ix_attendance_audit_logs_created_at', table_name='attendance_audit_logs')
    op.drop_index('ix_attendance_audit_logs_changed_by_id', table_name='attendance_audit_logs')
    op.drop_index('ix_attendance_audit_logs_attendance_record_id', table_name='attendance_audit_logs')
    op.drop_table('attendance_audit_logs')
    op.drop_index('ix_attendance_records_student_id', table_name='attendance_records')
    op.drop_index('ix_attendance_records_session_id', table_name='attendance_records')
    op.drop_table('attendance_records')
    op.drop_index('uq_attendance_session_one_open_per_program', table_name='attendance_sessions')
    op.drop_index('ix_attendance_sessions_program_status', table_name='attendance_sessions')
    op.drop_index('ix_attendance_sessions_status', table_name='attendance_sessions')
    op.drop_index('ix_attendance_sessions_started_by_id', table_name='attendance_sessions')
    op.drop_index('ix_attendance_sessions_program_id', table_name='attendance_sessions')
    op.drop_table('attendance_sessions')
