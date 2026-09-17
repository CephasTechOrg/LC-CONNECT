"""Device-token persistence for push notifications + in-app notification records."""

from __future__ import annotations

from collections.abc import Sequence
from datetime import datetime
from uuid import UUID

from sqlalchemy import delete, func, select, tuple_, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.features.notifications.schema import (
    NotificationActor,
    NotificationGroupInfo,
    NotificationRead,
)
from app.models import DeviceToken, Group, Notification, Profile


async def register_device(db: AsyncSession, user_id: UUID, token: str, platform: str) -> None:
    """Idempotent upsert on the unique token: re-registration never duplicates, and a
    shared device's token moves to the newest user (rec #4)."""
    stmt = pg_insert(DeviceToken).values(user_id=user_id, token=token, platform=platform)
    stmt = stmt.on_conflict_do_update(
        index_elements=['token'],
        set_={'user_id': user_id, 'platform': platform, 'updated_at': func.now()},
    )
    await db.execute(stmt)
    await db.commit()


async def unregister_device(db: AsyncSession, user_id: UUID, token: str) -> None:
    """Drop one of *the caller's own* device tokens.

    Scoped to `user_id` on purpose: the token is the URL path segment, so without this anyone
    holding another user's token could silently unregister their device and kill their push
    notifications. A token that isn't theirs simply matches nothing (the endpoint stays 204/
    idempotent, and never reveals whether the token exists).
    """
    await db.execute(
        delete(DeviceToken).where(DeviceToken.token == token, DeviceToken.user_id == user_id)
    )
    await db.commit()


async def tokens_for_user(db: AsyncSession, user_id: UUID) -> list[str]:
    rows = await db.execute(select(DeviceToken.token).where(DeviceToken.user_id == user_id))
    return [row[0] for row in rows.all()]


async def prune_tokens(db: AsyncSession, tokens: Sequence[str]) -> None:
    if not tokens:
        return
    await db.execute(delete(DeviceToken).where(DeviceToken.token.in_(tokens)))
    await db.commit()


# ── in-app notifications ───────────────────────────────────────────────────────────

async def create_notification(
    db: AsyncSession, *, user_id: UUID, type: str, group_id: UUID | None = None, actor_id: UUID | None = None
) -> Notification:
    """Insert a notification (caller commits). Never notify someone about their own action."""
    notification = Notification(user_id=user_id, type=type, group_id=group_id, actor_id=actor_id)
    db.add(notification)
    await db.flush()
    return notification


def _to_read(n: Notification, group_name: str | None, actor_name: str | None, actor_avatar: str | None) -> NotificationRead:
    return NotificationRead(
        id=n.id,
        type=n.type,
        read=n.read_at is not None,
        created_at=n.created_at,
        group=NotificationGroupInfo(id=n.group_id, name=group_name) if (n.group_id and group_name) else None,
        actor=NotificationActor(id=n.actor_id, display_name=actor_name, avatar_url=actor_avatar) if n.actor_id else None,
    )


async def list_notifications(
    db: AsyncSession,
    user_id: UUID,
    *,
    limit: int = 50,
    before_created_at: datetime | None = None,
    before_id: UUID | None = None,
) -> list[NotificationRead]:
    """Newest-first page, resolving the group name + actor profile in one query (no N+1).

    Ordered by `(created_at DESC, id DESC)`. The tiebreaker is not cosmetic: the attendance
    fan-out inserts one row per member in a single commit, so ties are the norm rather than the
    exception, and ordering by `created_at` alone returned them in a different order on each call.
    That is invisible in a single fixed page and corrupts a paged one — a row could repeat or be
    skipped at the boundary.

    Pagination is keyset, matching `messages.list_thread`: pass the last row of the previous page
    as `before_created_at`/`before_id`. OFFSET would re-scan everything it skips and would still
    drift whenever a new notification arrives mid-scroll.
    """
    actor = aliased(Profile)
    stmt = (
        select(Notification, Group.name, actor.display_name, actor.avatar_url)
        .outerjoin(Group, Group.id == Notification.group_id)
        .outerjoin(actor, actor.user_id == Notification.actor_id)
        .where(Notification.user_id == user_id)
    )
    if before_created_at is not None and before_id is not None:
        stmt = stmt.where(
            tuple_(Notification.created_at, Notification.id) < tuple_(before_created_at, before_id)
        )
    stmt = stmt.order_by(Notification.created_at.desc(), Notification.id.desc()).limit(limit)

    rows = (await db.execute(stmt)).all()
    return [_to_read(n, group_name, actor_name, actor_avatar) for n, group_name, actor_name, actor_avatar in rows]


async def read_one(db: AsyncSession, notification: Notification) -> NotificationRead:
    """Resolve a single notification's group/actor for the live WS frame."""
    group_name = None
    if notification.group_id:
        group_name = (
            await db.execute(select(Group.name).where(Group.id == notification.group_id))
        ).scalar_one_or_none()
    actor_name = actor_avatar = None
    if notification.actor_id:
        row = (
            await db.execute(
                select(Profile.display_name, Profile.avatar_url).where(Profile.user_id == notification.actor_id)
            )
        ).first()
        if row is not None:
            actor_name, actor_avatar = row
    return _to_read(notification, group_name, actor_name, actor_avatar)


async def unread_count(db: AsyncSession, user_id: UUID) -> int:
    return (
        await db.execute(
            select(func.count(Notification.id)).where(
                Notification.user_id == user_id, Notification.read_at.is_(None)
            )
        )
    ).scalar_one()


async def mark_one_read(db: AsyncSession, user_id: UUID, notification_id: UUID) -> bool:
    """Mark a single notification read. Returns whether a row was affected.

    Scoped to `user_id` so the id in the URL cannot be used to touch someone else's row, and
    idempotent: re-reading an already-read notification is a no-op rather than an error, which is
    what lets the client fire this optimistically on tap.
    """
    result = await db.execute(
        update(Notification)
        .where(
            Notification.id == notification_id,
            Notification.user_id == user_id,
            Notification.read_at.is_(None),
        )
        .values(read_at=func.now())
    )
    await db.commit()
    return bool(result.rowcount)


async def mark_all_read(db: AsyncSession, user_id: UUID) -> None:
    await db.execute(
        update(Notification)
        .where(Notification.user_id == user_id, Notification.read_at.is_(None))
        .values(read_at=func.now())
    )
    await db.commit()
