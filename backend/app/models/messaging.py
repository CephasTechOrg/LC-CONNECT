import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, String, Text, UniqueConstraint, func, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class Conversation(Base):
    """Messaging container. `kind='dm'` wraps a Match (2 members); `kind='group'` is owned by
    a Group (N members). Introduced additively in P1 — see docs/groups/."""

    __tablename__ = 'conversations'

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    kind: Mapped[str] = mapped_column(String(20), default='dm', index=True, nullable=False)
    # DM conversations point at their Match, inheriting its normalized-pair uniqueness
    # (uq_match_pair) — that is what prevents duplicate DM conversations. NULL for groups.
    match_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey('matches.id', ondelete='CASCADE'), unique=True, nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class ConversationMember(Base):
    """Per-member state in a conversation: role, lifecycle status, and the read boundary."""

    __tablename__ = 'conversation_members'
    __table_args__ = (
        UniqueConstraint('conversation_id', 'user_id', name='uq_conversation_member'),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    conversation_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey('conversations.id', ondelete='CASCADE'), index=True, nullable=False
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), index=True, nullable=False
    )
    role: Mapped[str] = mapped_column(String(20), default='member', nullable=False)  # owner|admin|member
    status: Mapped[str] = mapped_column(String(20), default='active', index=True, nullable=False)
    # invited|requested|active|removed|banned
    invited_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'), nullable=True
    )
    # Per-member unread boundary. A single Message.read_at cannot express "who has read this"
    # in an N-member conversation, so groups require this. Adopted in P2.
    last_read_message_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey('messages.id', ondelete='SET NULL'), nullable=True
    )
    muted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class Message(Base):
    __tablename__ = 'messages'
    __table_args__ = (
        # Idempotency: a sender's client_message_id maps to exactly one server row.
        # Partial so legacy rows (NULL client_message_id) are exempt.
        Index(
            'uq_messages_sender_client',
            'sender_id',
            'client_message_id',
            unique=True,
            postgresql_where=text('client_message_id IS NOT NULL'),
        ),
        # Keyset pagination + reconnect sync, keyed by the conversation (the live path since
        # P2). Newest-first within a conversation; also serves the unread boundary scan.
        Index('ix_messages_conversation_created_id', text('conversation_id'), text('created_at DESC'), text('id DESC')),
        # Legacy match-keyed keyset index — retained during the transition (match_id is still
        # dual-written) so a rollback to the match path stays fast. Droppable post-cutover.
        Index('ix_messages_match_created_id', text('match_id'), text('created_at DESC'), text('id DESC')),
        # Legacy unread index (match/read_at based). Superseded by the boundary scan; kept for
        # rollback safety, droppable post-cutover.
        Index('ix_messages_unread', 'match_id', 'sender_id', postgresql_where=text('read_at IS NULL')),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    # Nullable since P4: DM messages carry a match_id (+ conversation_id), but GROUP messages
    # have only a conversation_id (no match). conversation_id is the universal container.
    match_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey('matches.id', ondelete='CASCADE'), index=True, nullable=True)
    # P1: additive + nullable. Backfilled for every existing message; nothing reads it until
    # P2. `match_id` stays written throughout the cutover so rollback is trivial.
    conversation_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey('conversations.id', ondelete='CASCADE'), index=True, nullable=True
    )
    sender_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), index=True, nullable=False)
    # Client-generated idempotency key; NULL for legacy rows, required for new sends.
    client_message_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True, nullable=False)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    # Soft-delete ("delete for everyone"): set when unsent. The original body is retained for
    # moderation/audit but never serialized to clients once this is set (they get a tombstone).
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
