"""Fan-out for Honors attendance session-open notifications (in-app + WebSocket + push).

Kept out of ``service.py`` so the business logic stays lean and this delivery concern owns its
own module. Runs as a background task after the session is created, so a slow or failed delivery
never blocks (or breaks) the instructor's ``Start Attendance`` action.
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import select

from app.database import AsyncSessionLocal
from app.features.notifications.push import push_sender
from app.features.notifications.schema import NotificationRead
from app.models import AttendanceSession, DeviceToken, Notification, ProgramMembership, User
from app.models.attendance import ATTENDANCE_SESSION_OPEN_STATUS

logger = logging.getLogger('lc_connect.attendance')

ATTENDANCE_OPEN_NOTIFICATION = 'honors_attendance_open'


async def _active_member_ids(db, program_id: UUID) -> list[UUID]:
    rows = await db.execute(
        select(ProgramMembership.user_id).where(
            ProgramMembership.program_id == program_id,
            ProgramMembership.status == 'active',
        )
    )
    return list(rows.scalars().all())


async def _member_device_tokens(db, program_id: UUID) -> list[str]:
    rows = await db.execute(
        select(DeviceToken.token)
        .join(User, User.id == DeviceToken.user_id)
        .join(ProgramMembership, ProgramMembership.user_id == User.id)
        .where(
            ProgramMembership.program_id == program_id,
            ProgramMembership.status == 'active',
            User.is_active.is_(True),
            User.status == 'active',
            User.deleted_at.is_(None),
        )
    )
    return [row[0] for row in rows.all()]


async def notify_attendance_session_open(session_id: UUID) -> None:
    """Tell active Honors students a session just opened.

    Persists an in-app notification per student, pushes each one live over their user channel,
    and sends a single bulk push carrying the session id so tapping opens the scanner. Entirely
    best-effort — any failure is logged and swallowed.
    """
    try:
        async with AsyncSessionLocal() as db:
            session = await db.get(AttendanceSession, session_id)
            if session is None or session.status != ATTENDANCE_SESSION_OPEN_STATUS:
                return

            member_ids = await _active_member_ids(db, session.program_id)
            if not member_ids:
                return

            # id is a client-side uuid4 default, so it's available before commit — no refresh
            # round-trip needed to build the live frames below.
            notifications = [
                Notification(user_id=user_id, type=ATTENDANCE_OPEN_NOTIFICATION)
                for user_id in member_ids
            ]
            db.add_all(notifications)
            await db.commit()

            tokens = await _member_device_tokens(db, session.program_id)

        await _publish_live(notifications)

        if tokens:
            async with AsyncSessionLocal() as db:
                await push_sender.notify_honors_attendance_open(db, tokens=tokens, session_id=session_id)
    except Exception as exc:  # noqa: BLE001 - delivery must never break starting attendance
        logger.warning('notify_attendance_session_open failed (session=%s): %s', session_id, exc)


async def _publish_live(notifications: list[Notification]) -> None:
    from app.features.realtime import protocol
    from app.features.realtime.runtime import event_bus

    now = datetime.now(UTC)
    for notification in notifications:
        dto = NotificationRead(
            id=notification.id,
            type=notification.type,
            read=False,
            created_at=now,
        )
        await event_bus.publish_to_user(
            notification.user_id, protocol.notification_event(dto.model_dump(mode='json'))
        )
