import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class EmployerOrganization(Base):
    """An employer partner organization — self-registered, then reviewed. `EmployerAccount` is
    deliberately NOT a `User` (see docs/LC_CONNECT_BLUEPRINT_BOND_INTEGRATION_SPEC.md §11.0): an
    employer identity that never touches the `users` table means every existing student/staff
    endpoint stays default-deny for them with zero additional auditing — they simply don't resolve
    against `get_current_user`."""

    __tablename__ = 'employer_organizations'

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    status: Mapped[str] = mapped_column(String(20), default='pending', index=True, nullable=False)
    review_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    reviewed_by_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'), nullable=True
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class EmployerAccount(Base):
    """The contact person for an `EmployerOrganization`. `auth_user_id` stays NULL until the org
    is approved — a pending/rejected employer has no Supabase identity at all, not just a gated
    one, which is the strongest form of "zero access" while pending."""

    __tablename__ = 'employer_accounts'

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    organization_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey('employer_organizations.id', ondelete='CASCADE'), index=True, nullable=False
    )
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    display_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    auth_user_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True, index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
