"""Administrative audit trail for sensitive actions."""

from __future__ import annotations

import json
from typing import Any
from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import AdminAuditLog


def _snapshot(data: dict[str, Any] | None) -> str | None:
    if data is None:
        return None
    return json.dumps(data, default=str)


async def record_audit(
    db: AsyncSession,
    *,
    actor_id: UUID,
    action: str,
    target_type: str,
    target_id: UUID,
    before_data: dict[str, Any] | None = None,
    after_data: dict[str, Any] | None = None,
) -> AdminAuditLog:
    from app.shared.request_context import get_request_id

    # Stamp correlation id into after_data when present so moderator reviews can join logs.
    req_id = get_request_id()
    if req_id:
        after_data = {**(after_data or {}), 'request_id': req_id}

    entry = AdminAuditLog(
        actor_id=actor_id,
        action=action,
        target_type=target_type,
        target_id=target_id,
        before_data=_snapshot(before_data),
        after_data=_snapshot(after_data),
    )
    db.add(entry)
    await db.flush()
    return entry
