import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, String, func, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class DeviceToken(Base):
    __tablename__ = 'device_tokens'

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), index=True, nullable=False)
    # FCM registration token — unique so re-registration upserts (never duplicates).
    token: Mapped[str] = mapped_column(String(512), unique=True, index=True, nullable=False)
    platform: Mapped[str] = mapped_column(String(20), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)


class Notification(Base):
    """In-app notification for a recipient — e.g. a group invite, a request approval, or a role
    change. Structured (type + group + actor) rather than pre-rendered text, so names stay fresh;
    the client composes the sentence. `read_at` drives the unread badge."""

    __tablename__ = 'notifications'
    # Fetch `created_at` with the INSERT's RETURNING clause rather than on first access. The
    # attendance fan-out publishes a live frame per row immediately after committing, and without
    # this each frame either triggered a refresh round trip or had to invent its own timestamp —
    # which is what made a live notification and the same row from `GET /notifications` disagree
    # about when it happened. Same reasoning as `Message`.
    __mapper_args__ = {'eager_defaults': True}
    __table_args__ = (
        # Keyset listing: WHERE user_id = ? ORDER BY created_at DESC, id DESC. The single-column
        # indexes this table shipped with left the sort to be done per request.
        Index(
            'ix_notifications_user_created_id',
            text('user_id'),
            text('created_at DESC'),
            text('id DESC'),
        ),
        # Unread badge. Partial, so it holds only unread rows and stays small as history grows —
        # the same shape as `ix_messages_unread`.
        Index(
            'ix_notifications_unread',
            'user_id',
            postgresql_where=text('read_at IS NULL'),
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), index=True, nullable=False)
    type: Mapped[str] = mapped_column(String(40), nullable=False)
    group_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey('groups.id', ondelete='CASCADE'), index=True, nullable=True)
    actor_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'), nullable=True)
    # A short display token for this one event, when the structured columns above cannot carry it.
    # Currently only the reaction emoji: `type` says "someone reacted", `actor_id` who, `target_id`
    # where — but which emoji belongs to this row alone. Deliberately not a payload: nothing
    # branches on it, and anything needing structure gets its own column.
    detail: Mapped[str | None] = mapped_column(String(16), nullable=True)
    # ── deep-link target ──────────────────────────────────────────────────────
    #
    # What tapping this row should open, when `group_id`/`actor_id` above cannot say. Attendance
    # is the case that forced it: those rows were inserted with no target at all, so a
    # notification about a session could not open that session — the row could only open the
    # inbox, and the scanner then had to re-guess which session was meant.
    #
    # Deliberately a generic `(type, id)` pair rather than a typed FK per notification kind. The
    # targets live in *different tables* — attendance sessions, campus posts, activities — so no
    # single foreign key can cover them, and one nullable FK per kind means a migration every
    # time a notification type is added. `group_id` and `actor_id` stay typed because they are
    # shared across many types and want the cascade behaviour.
    #
    # The cost, stated: no referential integrity, so a target can dangle. That is acceptable here
    # because the client must handle a vanished target regardless — a session closes, a post is
    # deleted — and "that session has closed" is a better outcome than a cascade silently deleting
    # the user's notification history.
    target_type: Mapped[str | None] = mapped_column(String(30), nullable=True)
    target_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)

    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
