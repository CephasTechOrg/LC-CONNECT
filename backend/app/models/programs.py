import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import ARRAY, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Program(Base):
    """A school-run program a student can be enrolled in (e.g. Presidential Scholars) — the
    generic foundation the Blueprint Bond module is built on. Seeded, not admin-CRUD'd, for now."""

    __tablename__ = 'programs'

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    slug: Mapped[str] = mapped_column(String(60), unique=True, index=True, nullable=False)
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class ProgramMembership(Base):
    """A user's enrollment in a `Program` — never self-declared; an Honors admin verifies from an
    official roster (see `app/features/admin/programs.py`). One row per (user, program): a revoke
    flips `status` rather than deleting, so a later re-verify reactivates the same row instead of
    duplicating history."""

    __tablename__ = 'program_memberships'
    __table_args__ = (
        UniqueConstraint('user_id', 'program_id', name='uq_program_membership_user_program'),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), index=True, nullable=False
    )
    program_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey('programs.id', ondelete='CASCADE'), index=True, nullable=False
    )
    status: Mapped[str] = mapped_column(String(20), default='active', index=True, nullable=False)
    verified_by_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'), nullable=True
    )
    verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class ScholarProfessionalProfile(Base):
    """The Blueprint Bond professional extension — separate from the social `Profile`/avatar on
    purpose: the headshot and résumé are only ever shown in employer-facing views (once employer
    discovery exists), never mixed into the normal social profile. Only a verified Presidential
    Scholar (`ProgramMembership`) can have one; enforced in `app/features/scholars/service.py`, not
    here. `headshot_path`/`resume_path` are private-bucket **object paths**, never public URLs —
    every read goes through a short-lived signed URL generated on demand."""

    __tablename__ = 'scholar_professional_profiles'

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), unique=True, index=True, nullable=False
    )
    headshot_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    resume_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    linkedin_url: Mapped[str | None] = mapped_column(String(300), nullable=True)
    handshake_url: Mapped[str | None] = mapped_column(String(300), nullable=True)
    summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    skills: Mapped[list[str]] = mapped_column(ARRAY(String(60)), default=list, nullable=False)
    career_interests: Mapped[list[str]] = mapped_column(ARRAY(String(60)), default=list, nullable=False)
    # Employer-visibility consent, captured as fields rather than a separate table (a single
    # boolean + timestamp + version doesn't earn its own model yet) — `consent_version` lets a
    # later policy change force re-consent by bumping `CURRENT_CONSENT_VERSION` in service.py.
    employer_visibility_consent: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    consent_given_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    consent_version: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
