import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, String, Text, UniqueConstraint, func, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

# V1: at most one live session per Honors program (`presidential_scholars`).
ATTENDANCE_SESSION_OPEN_STATUS = 'open'


class AttendanceSession(Base):
    """One Honors attendance event — live or historical."""

    __tablename__ = 'attendance_sessions'
    __table_args__ = (
        Index(
            'uq_attendance_session_one_open_per_program',
            'program_id',
            unique=True,
            postgresql_where=text(f"status = '{ATTENDANCE_SESSION_OPEN_STATUS}'"),
        ),
        Index('ix_attendance_sessions_program_status', 'program_id', 'status'),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    program_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey('programs.id', ondelete='CASCADE'), index=True, nullable=False
    )
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    started_by_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'), index=True, nullable=False
    )
    opened_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    present_until: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    late_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    closed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    status: Mapped[str] = mapped_column(String(20), index=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class AttendanceRecord(Base):
    """One student's result for one attendance session."""

    __tablename__ = 'attendance_records'
    __table_args__ = (
        UniqueConstraint('session_id', 'student_id', name='uq_attendance_record_session_student'),
        Index('ix_attendance_records_session_id', 'session_id'),
        Index('ix_attendance_records_student_id', 'student_id'),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    session_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey('attendance_sessions.id', ondelete='CASCADE'), nullable=False
    )
    student_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False
    )
    status: Mapped[str] = mapped_column(String(20), nullable=False)
    verification_method: Mapped[str] = mapped_column(String(20), nullable=False)
    checked_in_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    original_checked_in_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    manually_modified: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    modified_by_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'), nullable=True
    )
    modified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    modification_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class AttendanceAuditLog(Base):
    """Immutable trail for instructor manual attendance corrections."""

    __tablename__ = 'attendance_audit_logs'

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    attendance_record_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey('attendance_records.id', ondelete='CASCADE'), index=True, nullable=False
    )
    changed_by_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'), index=True, nullable=True
    )
    previous_status: Mapped[str] = mapped_column(String(20), nullable=False)
    new_status: Mapped[str] = mapped_column(String(20), nullable=False)
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True, nullable=False
    )
