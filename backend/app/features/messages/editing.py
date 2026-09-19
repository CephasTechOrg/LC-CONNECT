"""Sent-message editing — report #5.

Split out of `service.py` when that file crossed the 600-line hard cap.

One function, and its length is almost entirely the authorization ladder — which is the point of
the feature. Editing is the one operation here that can make a message say something it never
said, so what it *refuses* matters more than what it does.
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import Message, MessageEdit
from app.shared.message_limits import MAX_BODY_CHARS


async def edit_message(db: AsyncSession, message_id: UUID, actor_id: UUID, body: str) -> Message:
    """Edit a message's body, keeping the previous one (report #5).

    The authorization order below is the substance of this function, and each step is refused for
    a different reason:

    1. **Accessible conversation** — 404 for a non-member, 403 for a block or a closed staff
       thread. The same gate as every other REST message endpoint, so a message id alone reveals
       nothing.
    2. **Sender only.** Deliberately asymmetric with delete, where a group admin may remove
       someone else's message. An admin who could *edit* it would hold a forgery primitive: the
       ability to put words in another person's mouth, in a conversation others are reading, under
       that person's name. No moderation need justifies that — removing the message already does
       the job.
    3. **Not deleted** — checked *inside* this transaction, not before it, so a delete racing an
       edit resolves with the delete winning. Editing a tombstone would resurrect a body the
       delete exists to withhold.
    4. **Inside the window** — measured from `created_at` server-side. A client clock cannot be
       trusted with it, and its countdown is advisory only.

    The previous body is written to `message_edits` in the same transaction as the update: if one
    can happen without the other, the audit trail is worth nothing.
    """
    from app.shared.conversations import accessible_conversation

    message = await db.get(Message, message_id)
    if message is None or message.conversation_id is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Message not found')

    await accessible_conversation(db, message.conversation_id, actor_id)

    if message.sender_id != actor_id:
        # Not 403: a non-sender should not learn that a message exists and is merely un-editable.
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Message not found')

    if message.deleted_at is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail='That message was deleted'
        )

    age = datetime.now(UTC) - message.created_at
    if age.total_seconds() > settings.message_edit_window_seconds:
        # A distinct, machine-readable reason so the client can say "the edit window has passed"
        # rather than a generic failure — the mistake report #8 made with attendance.
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='edit_window_expired',
        )

    cleaned = body.strip()
    if not cleaned or len(cleaned) > MAX_BODY_CHARS:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=f'Message must be between 1 and {MAX_BODY_CHARS} characters',
        )
    if cleaned == message.body:
        # Nothing changed: return as-is rather than writing a history row saying "X became X".
        return message

    db.add(MessageEdit(message_id=message.id, previous_body=message.body))
    message.body = cleaned
    message.edited_at = datetime.now(UTC)
    await db.commit()
    return message
