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
    # Per-member delivery boundary — "this member's device has everything up to here". Same
    # shape and same reasoning as the read boundary above, and for the same reason it is not a
    # column on `messages`: one column cannot say *who* has it.
    #
    # Also deliberately not a `message_deliveries` table: that is messages x members rows for a
    # cosmetic tick, where a boundary is O(members). Advanced only by an explicit client
    # acknowledgement (`messages.delivered`), never by the server's own fan-out — an enqueue to a
    # half-open socket is not a delivery.
    last_delivered_message_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey('messages.id', ondelete='SET NULL'), nullable=True
    )
    muted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class Message(Base):
    __tablename__ = 'messages'
    # Fetch server defaults (`created_at`) with the INSERT's RETURNING clause rather than on first
    # access. PostgreSQL would usually do this anyway under SQLAlchemy 2.0's `"auto"` default, but
    # the send path depends on it: `persist_message_idempotent` no longer issues a `db.refresh()`
    # after commit, and that refresh was a whole extra round trip on every message sent.
    __mapper_args__ = {'eager_defaults': True}
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
    # Null until the sender edits it. Display-only — the *authority* on what changed is the
    # `message_edits` row written in the same transaction.
    edited_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    # Soft-delete ("delete for everyone"): set when unsent. The original body is retained for
    # moderation until the retention window elapses, then purged by cron (see
    # `MESSAGE_SOFT_DELETE_RETENTION_DAYS`). Report snapshots survive row purge.
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class MessageReaction(Base):
    """One person's one emoji on one message (report #4).

    A table rather than a JSON column on `messages`, and the reason is concurrency: a blob cannot
    carry a unique constraint, so two people reacting at the same instant would read-modify-write
    the same row and one would lose. Toggling would also mean rewriting a hot row on every tap.

    `emoji` is a short string checked against a server-side allowlist rather than an enum table.
    An enum table means a join on the hottest read in the app; free text is an abuse surface and
    makes the per-message aggregate unbounded. A bounded allowlist gives neither problem and keeps
    the column readable in a database console.
    """

    __tablename__ = 'message_reactions'
    __table_args__ = (
        # Makes a toggle idempotent: a double-tap cannot produce two rows, and the loser of a race
        # catches IntegrityError and treats it as success — the same arbiter pattern as message
        # idempotency.
        UniqueConstraint('message_id', 'user_id', 'emoji', name='uq_message_reaction'),
        # Serves the per-page aggregate: GROUP BY message_id, emoji over a page of message ids.
        Index('ix_message_reactions_message_emoji', 'message_id', 'emoji'),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    message_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey('messages.id', ondelete='CASCADE'), index=True, nullable=False
    )
    # CASCADE on the *user*, unlike `Message.sender_id`: a reaction is not a record of anything.
    # Deleting an account should take its reactions with it, where deleting an account must not
    # take its messages (they are half of someone else's conversation).
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), index=True, nullable=False
    )
    emoji: Mapped[str] = mapped_column(String(8), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class MessageEdit(Base):
    """The body a message had before an edit — an immutable audit trail (report #5).

    Required, not optional. Without it an edit *destroys evidence*, and this codebase already
    treats that as unacceptable: a delete is soft precisely so the body survives for moderation,
    and a safety report snapshots the reported text. An edit with no history would be the one
    way to make a message say something it never said, with nothing left to check against.

    Purged on the same schedule as soft-deleted bodies (`MESSAGE_SOFT_DELETE_RETENTION_DAYS`), so
    it does not become a permanent record of everything anyone ever rephrased.
    """

    __tablename__ = 'message_edits'

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    message_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey('messages.id', ondelete='CASCADE'), index=True, nullable=False
    )
    previous_body: Mapped[str] = mapped_column(Text, nullable=False)
    edited_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
