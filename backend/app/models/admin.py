import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class AdminMembership(Base):
    """A scoped admin role held by a user — `super_admin`, `school_admin`, `honors_admin`,
    `content_admin`, or `auditor` (see `app/features/admin/admins.py` for the invite matrix that
    governs who can grant which). `User.role == 'admin'` is still the base gate (`require_admin_aal2`
    — MFA-enforced); this layers *which* admin capabilities that account actually holds on top of
    it. A user can hold more than one scope, hence one row per (user, role) rather than a single
    column on `User`."""

    __tablename__ = 'admin_memberships'
    __table_args__ = (
        UniqueConstraint('user_id', 'role', name='uq_admin_membership_user_role'),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), index=True, nullable=False
    )
    role: Mapped[str] = mapped_column(String(30), index=True, nullable=False)
    status: Mapped[str] = mapped_column(String(20), default='active', index=True, nullable=False)
    invited_by_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'), nullable=True
    )
    invited_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class AdminAuditLog(Base):
    """Immutable record of sensitive admin actions (position review, suspensions, etc.)."""

    __tablename__ = 'admin_audit_logs'

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    actor_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'), index=True, nullable=True
    )
    action: Mapped[str] = mapped_column(String(80), index=True, nullable=False)
    target_type: Mapped[str] = mapped_column(String(40), index=True, nullable=False)
    target_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), index=True, nullable=False)
    before_data: Mapped[str | None] = mapped_column(Text, nullable=True)
    after_data: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True, nullable=False)


class SuspensionAppeal(Base):
    """A suspended user's request for review. Does not auto-reactivate — admins decide separately."""

    __tablename__ = 'suspension_appeals'

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), index=True, nullable=False
    )
    message: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(String(20), default='open', index=True, nullable=False)
    # open | dismissed | resolved
    admin_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    reviewed_by_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True, nullable=False)
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
