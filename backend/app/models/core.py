import uuid
from datetime import datetime

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, String, Table, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base

profile_interests = Table(
    'user_interests',
    Base.metadata,
    Column('profile_id', UUID(as_uuid=True), ForeignKey('profiles.id', ondelete='CASCADE'), primary_key=True),
    Column('interest_id', Integer, ForeignKey('interests.id', ondelete='CASCADE'), primary_key=True),
)

user_looking_for = Table(
    'user_looking_for',
    Base.metadata,
    Column('profile_id', UUID(as_uuid=True), ForeignKey('profiles.id', ondelete='CASCADE'), primary_key=True),
    Column('option_id', Integer, ForeignKey('looking_for_options.id', ondelete='CASCADE'), primary_key=True),
)


class User(Base):
    __tablename__ = 'users'

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    # Supabase Auth subject (auth.users.id). NULL only on soft-deleted tombstones
    # (account deletion unlinks) or before ops linking completes — see AUTH_USER_LINKING_RUNBOOK.
    auth_user_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True, index=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True, nullable=False)
    role: Mapped[str] = mapped_column(String(30), default='student', nullable=False)
    status: Mapped[str] = mapped_column(String(30), default='active', nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    # Personal inbox for auth OTP (signup/recovery). Campus identity stays in `email`.
    contact_email: Mapped[str | None] = mapped_column(String(255), nullable=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
    # Set when the user self-deletes. The row is anonymized in place (see app/features/account),
    # not removed — a hard delete would cascade away other people's messages/groups/activities.
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    profile: Mapped['Profile'] = relationship('Profile', back_populates='user', uselist=False, cascade='all, delete-orphan')


class Interest(Base):
    __tablename__ = 'interests'

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(80), unique=True, index=True, nullable=False)
    category: Mapped[str | None] = mapped_column(String(50), nullable=True)


class Language(Base):
    __tablename__ = 'languages'

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(80), unique=True, index=True, nullable=False)


class LookingForOption(Base):
    __tablename__ = 'looking_for_options'

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    code: Mapped[str] = mapped_column(String(50), unique=True, index=True, nullable=False)
    name: Mapped[str] = mapped_column(String(80), unique=True, nullable=False)


class Profile(Base):
    __tablename__ = 'profiles'

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), unique=True, index=True, nullable=False)
    display_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    pronouns: Mapped[str | None] = mapped_column(String(50), nullable=True)
    major: Mapped[str | None] = mapped_column(String(120), index=True, nullable=True)
    class_year: Mapped[int | None] = mapped_column(Integer, index=True, nullable=True)
    country_state: Mapped[str | None] = mapped_column(String(120), nullable=True)
    campus: Mapped[str | None] = mapped_column(String(120), default='Livingstone Campus', nullable=True)
    bio: Mapped[str | None] = mapped_column(Text, nullable=True)
    avatar_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_hidden: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    allow_messages_from_matches_only: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    show_profile_to_verified_only: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    profile_completed: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    user: Mapped[User] = relationship('User', back_populates='profile')
    interests: Mapped[list[Interest]] = relationship('Interest', secondary=profile_interests, lazy='selectin')
    looking_for_options: Mapped[list[LookingForOption]] = relationship('LookingForOption', secondary=user_looking_for, lazy='selectin')
    languages: Mapped[list['UserLanguage']] = relationship('UserLanguage', back_populates='profile', cascade='all, delete-orphan', lazy='selectin')


class UserLanguage(Base):
    __tablename__ = 'user_languages'
    __table_args__ = (UniqueConstraint('profile_id', 'language_id', 'kind', name='uq_user_language_kind'),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    profile_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey('profiles.id', ondelete='CASCADE'), index=True, nullable=False)
    language_id: Mapped[int] = mapped_column(Integer, ForeignKey('languages.id', ondelete='CASCADE'), nullable=False)
    kind: Mapped[str] = mapped_column(String(20), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    profile: Mapped[Profile] = relationship('Profile', back_populates='languages')
    language: Mapped[Language] = relationship('Language', lazy='selectin')
