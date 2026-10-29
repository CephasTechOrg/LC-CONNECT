"""Outbound frames added in protocol 5 — kept beside `protocol.py`, which re-exports them, so that
file stays a readable size. Builders only: we produce these frames, so they need no validation.
"""

from __future__ import annotations

from typing import Any
from uuid import UUID


def reaction_change(
    *,
    conversation_id: UUID | str,
    message_id: UUID,
    user_id: UUID,
    emoji: str,
    added: bool,
    user_emoji: str | None,
    reactions: list[dict[str, Any]],
    actor_name: str | None,
    message_sender_id: UUID | None,
    message_snippet: str,
    reacted_at: str,
) -> dict[str, Any]:
    """A `messages.reaction` frame carrying the resulting state, sent to every member's user
    channel (protocol 5).

    The v3 fields (`message_id`, `user_id`, `emoji`, `added`) are unchanged, so an older client
    still applies it as a delta. A v5 client instead applies `user_emoji` (that person's one
    reaction now, or null) and `reactions` (the message's tallies, no viewer flag) — state, not a
    delta, so a repeated or reordered frame cannot make counts drift. `conversation_id` is the
    addressing id, which is what lets the inbox update with the chat closed; the actor's name and
    the message excerpt let it say "Ama reacted 👍 to “see you at 5”".
    """
    return {
        'type': 'messages.reaction',
        'conversation_id': str(conversation_id),
        'message_id': str(message_id),
        'user_id': str(user_id),
        'emoji': emoji,
        'added': added,
        'user_emoji': user_emoji,
        'reactions': reactions,
        'actor_name': actor_name,
        'message_sender_id': str(message_sender_id) if message_sender_id else None,
        'message_snippet': message_snippet,
        'reacted_at': reacted_at,
    }


def notification_retracted(notification_id: UUID) -> dict[str, Any]:
    """User-channel event: an unread notification was withdrawn (its reaction was taken back
    before it was seen) — clients drop the row and re-seed the badge."""
    return {'type': 'notification.retracted', 'id': str(notification_id)}


def notifications_read(notification_ids: list[UUID]) -> dict[str, Any]:
    """User-channel event: these notifications were marked read elsewhere (another device, or by
    opening the chat they were about) — clients untint them and re-seed the badge."""
    return {'type': 'notifications.read', 'ids': [str(i) for i in notification_ids]}


def conversation_muted(conversation_id: UUID | str, muted: bool) -> dict[str, Any]:
    """User-channel event: this user muted or unmuted a conversation, so their other devices'
    inbox shows the same bell. `conversation_id` is the addressing id."""
    return {'type': 'conversation.muted', 'conversation_id': str(conversation_id), 'muted': muted}


def presence(
    user_id: UUID, *, online: bool, last_seen_at: str | None, visible: bool = True
) -> dict[str, Any]:
    """User-channel event to a DM partner: this user came online or went offline. `visible` false
    means they hid their status — show nothing, and expect no further presence frames."""
    return {
        'type': 'presence',
        'user_id': str(user_id),
        'online': online,
        'last_seen_at': last_seen_at,
        'visible': visible,
    }
