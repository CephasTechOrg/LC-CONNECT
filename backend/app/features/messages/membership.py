"""A member's own settings on a conversation — currently mute, for DMs and groups alike.

Groups already had mute (`PATCH /groups/{id}/members/me`); a direct message had the same
`ConversationMember.muted` column, honoured by every push, but no way to set it.
"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Conversation, ConversationMember


async def set_muted(db: AsyncSession, conversation: Conversation, user_id: UUID, muted: bool) -> None:
    """Mute or unmute the conversation for this member. The caller has already authorized them."""
    await db.execute(
        update(ConversationMember)
        .where(
            ConversationMember.conversation_id == conversation.id,
            ConversationMember.user_id == user_id,
        )
        .values(muted=muted)
    )
    await db.commit()
