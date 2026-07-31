import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Group(Base):
    """A campus community (club, housing, class, interest). A domain entity distinct from its
    messaging container: it *owns* a `Conversation(kind='group')` for the group chat, leaving
    room to grow (events, announcements, posts) without bloating the conversation. Membership +
    roles live on `ConversationMember` (the same table DMs use)."""

    __tablename__ = 'groups'

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    avatar_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    category: Mapped[str] = mapped_column(String(30), index=True, nullable=False)  # club|housing|class|interest
    visibility: Mapped[str] = mapped_column(String(20), default='public', index=True, nullable=False)  # public|unlisted|private
    join_policy: Mapped[str] = mapped_column(String(20), default='approval', nullable=False)  # open|approval|invite
    owner_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), index=True, nullable=False)
    conversation_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey('conversations.id', ondelete='CASCADE'), unique=True, nullable=False
    )
    max_members: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
