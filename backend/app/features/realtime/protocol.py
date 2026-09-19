"""WebSocket wire protocol: typed inbound frames + outbound builders.

Inbound frames are a discriminated union on ``type`` so a malformed or unknown
frame is rejected uniformly (never crashes a handler). Outbound frames are built
by small helpers — we control them, so they need no validation.
"""

from __future__ import annotations

from typing import Annotated, Any, Literal
from uuid import UUID

from pydantic import BaseModel, Field, TypeAdapter, field_validator

from app.models import Message

MAX_BODY_CHARS = 2000
# 2 adds `messages.delivered` (inbound) and `messages.delivery` (outbound). A client learns the
# server's version from `auth.ok` and gates new frames on it, so a v1 server meeting a v2 client
# answers `unsupported_frame` at worst — and no longer spends the abuse budget doing so.
# 3 adds `messages.reaction` (outbound). Reactions are applied over REST rather than a new
# inbound frame: the request needs a response the client can roll an optimistic chip back from,
# and the WebSocket path has no request/response shape.
PROTOCOL_VERSION = 3


# ── Error + close codes ───────────────────────────────────────────────────────

class ErrorCode:
    AUTH_REQUIRED = 'auth_required'
    AUTH_FAILED = 'auth_failed'
    FORBIDDEN = 'forbidden'
    INVALID_FRAME = 'invalid_frame'
    # A well-formed frame whose `type` this server does not know — a version mismatch, not abuse.
    # Kept distinct from INVALID_FRAME because the gateway must NOT charge it to the abuse budget:
    # doing so banned any client that sent a newer frame type, and the client then reconnected and
    # sent it again. See `gateway._tolerate_unsupported`.
    UNSUPPORTED_FRAME = 'unsupported_frame'
    FRAME_TOO_LARGE = 'frame_too_large'
    RATE_LIMITED = 'rate_limited'
    NOT_SUBSCRIBED = 'not_subscribed'
    INTERNAL = 'internal_error'
    IDLE_TIMEOUT = 'idle_timeout'


class CloseCode:
    # Application close codes (4000–4999 are private-use).
    AUTH_FAILED = 4401
    FORBIDDEN = 4403
    AUTH_TIMEOUT = 4408
    IDLE_TIMEOUT = 4409
    ABUSE = 4429
    GOING_AWAY = 1001


# ── Inbound frames ────────────────────────────────────────────────────────────

class AuthFrame(BaseModel):
    type: Literal['auth']
    access_token: str = Field(min_length=1, max_length=4096)
    device_id: str | None = Field(default=None, max_length=200)
    app_version: str | None = Field(default=None, max_length=40)
    protocol_version: int | None = None


class SubscribeFrame(BaseModel):
    type: Literal['conversation.subscribe']
    request_id: UUID
    conversation_id: UUID


class UnsubscribeFrame(BaseModel):
    type: Literal['conversation.unsubscribe']
    request_id: UUID | None = None
    conversation_id: UUID


class SendFrame(BaseModel):
    type: Literal['message.send']
    request_id: UUID
    conversation_id: UUID
    client_message_id: UUID
    body: str = Field(max_length=MAX_BODY_CHARS)

    @field_validator('body')
    @classmethod
    def _non_empty(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError('body must not be empty')
        return stripped


class TypingStartFrame(BaseModel):
    type: Literal['typing.start']
    conversation_id: UUID


class TypingStopFrame(BaseModel):
    type: Literal['typing.stop']
    conversation_id: UUID


class PingFrame(BaseModel):
    """Application-level keepalive. The idle reaper only sees *inbound application frames*
    (`manager.touch` runs in the serve loop), so transport-level pings from uvicorn cannot keep
    a socket alive. A reading-only client sends nothing for minutes, so without this its socket
    is reaped at `WS_IDLE_TIMEOUT_SECONDS` and live delivery stops until it reconnects."""

    type: Literal['ping']


class ReadFrame(BaseModel):
    type: Literal['messages.read']
    conversation_id: UUID
    through_message_id: UUID


class DeliveredFrame(BaseModel):
    """The recipient's device has the message (protocol 2).

    Deliberately client-driven, and deliberately not inferred from the server's own fan-out:
    `deliver_to_conversation` enqueues to each live connection, but an enqueue to a half-open
    socket is not a delivery — writes to one succeed silently while nothing arrives, which is why
    the client detects half-open sockets at all. Only the client can say it has the message.

    Symmetric with [ReadFrame] in shape and in semantics: a monotonic per-member boundary, so a
    re-sent or out-of-order acknowledgement is a no-op rather than a regression. That matters
    because the client re-sends boundaries after a reconnect.
    """

    type: Literal['messages.delivered']
    conversation_id: UUID
    through_message_id: UUID


InboundFrame = Annotated[
    AuthFrame | SubscribeFrame | UnsubscribeFrame | SendFrame | TypingStartFrame | TypingStopFrame
    | ReadFrame | DeliveredFrame | PingFrame,
    Field(discriminator='type'),
]

_inbound_adapter: TypeAdapter[InboundFrame] = TypeAdapter(InboundFrame)


def parse_inbound(raw: Any) -> InboundFrame:
    """Validate a decoded JSON object into a typed frame. Raises ValidationError."""
    return _inbound_adapter.validate_python(raw)


# Every `type` this server understands, read off the union itself so it can never drift from it.
KNOWN_INBOUND_TYPES: frozenset[str] = frozenset(
    member.model_fields['type'].annotation.__args__[0]  # Literal['...'] → '...'
    for member in (
        AuthFrame,
        SubscribeFrame,
        UnsubscribeFrame,
        SendFrame,
        TypingStartFrame,
        TypingStopFrame,
        ReadFrame,
        DeliveredFrame,
        PingFrame,
    )
)


def is_unsupported_type(raw: Any) -> bool:
    """Whether a decoded frame carries a `type` this server does not implement.

    The distinction matters because the two failures deserve opposite treatment. A frame with an
    unknown `type` is a **newer client talking to an older server** — expected during any staged
    rollout, and harmless. A frame with a *known* type but invalid fields is a client bug or an
    attack, and belongs on the abuse budget.

    Both arrive as the same `ValidationError` from a discriminated union, so the gateway asks this
    to tell them apart.
    """
    if not isinstance(raw, dict):
        return False  # not even an object — malformed, not a version mismatch
    frame_type = raw.get('type')
    return isinstance(frame_type, str) and frame_type not in KNOWN_INBOUND_TYPES


# ── Outbound builders ─────────────────────────────────────────────────────────

def addressing_id(message: Message) -> str:
    """The id clients use to address this conversation over the socket: a DM's match id, or —
    for a group message, where match_id is null — the conversation id. Keeps DM frames
    byte-identical while making group frames route to the open group chat."""
    return str(message.match_id or message.conversation_id)


def serialize_message(message: Message) -> dict[str, Any]:
    deleted = message.deleted_at is not None
    return {
        'id': str(message.id),
        'conversation_id': addressing_id(message),
        'sender_id': str(message.sender_id),
        'client_message_id': str(message.client_message_id) if message.client_message_id else None,
        'body': '' if deleted else message.body,
        'created_at': message.created_at.isoformat(),
        'read_at': message.read_at.isoformat() if message.read_at else None,
        'deleted': deleted,
    }


def auth_ok(user_id: UUID, heartbeat_seconds: int) -> dict[str, Any]:
    return {
        'type': 'auth.ok',
        'user_id': str(user_id),
        'heartbeat_interval_seconds': heartbeat_seconds,
        'protocol_version': PROTOCOL_VERSION,
    }


def pong() -> dict[str, Any]:
    """Reply to a client keepalive. Clients use its arrival to detect a half-open socket."""
    return {'type': 'pong'}


def error(code: str, message: str, request_id: UUID | None = None) -> dict[str, Any]:
    frame: dict[str, Any] = {'type': 'error', 'code': code, 'message': message}
    if request_id is not None:
        frame['request_id'] = str(request_id)
    return frame


def subscribed(request_id: UUID, conversation_id: UUID) -> dict[str, Any]:
    return {'type': 'subscribed', 'request_id': str(request_id), 'conversation_id': str(conversation_id)}


def unsubscribed(conversation_id: UUID) -> dict[str, Any]:
    return {'type': 'unsubscribed', 'conversation_id': str(conversation_id)}


def message_ack(request_id: UUID, message: Message, duplicate: bool) -> dict[str, Any]:
    return {
        'type': 'message.ack',
        'request_id': str(request_id),
        'client_message_id': str(message.client_message_id) if message.client_message_id else None,
        'duplicate': duplicate,
        'message': serialize_message(message),
    }


def message_created(message: Message) -> dict[str, Any]:
    return {'type': 'message.created', 'conversation_id': addressing_id(message), 'message': serialize_message(message)}


def conversation_updated(message: Message) -> dict[str, Any]:
    """User-channel event: a conversation has a new latest message (thread-list update)."""
    return {'type': 'conversation.updated', 'conversation_id': addressing_id(message), 'message': serialize_message(message)}


def typing_event(conversation_id: UUID | str, user_id: UUID, active: bool) -> dict[str, Any]:
    return {
        'type': 'typing',
        'conversation_id': str(conversation_id),
        'user_id': str(user_id),
        'active': active,
    }


def read_receipt(
    conversation_id: UUID | str, user_id: UUID, through_message_id: UUID, read_at_iso: str
) -> dict[str, Any]:
    return {
        'type': 'messages.receipt',
        'conversation_id': str(conversation_id),
        'user_id': str(user_id),
        'through_message_id': str(through_message_id),
        'read_at': read_at_iso,
    }


def delivery_receipt(
    conversation_id: UUID | str, user_id: UUID, through_message_id: UUID, delivered_at_iso: str
) -> dict[str, Any]:
    """Conversation-channel event: `user_id`'s device now has everything up to
    `through_message_id`. Mirrors [read_receipt]; the sender renders it as the second tick."""
    return {
        'type': 'messages.delivery',
        'conversation_id': str(conversation_id),
        'user_id': str(user_id),
        'through_message_id': str(through_message_id),
        'delivered_at': delivered_at_iso,
    }


def reaction_event(
    message_id: UUID, user_id: UUID, emoji: str, *, added: bool
) -> dict[str, Any]:
    """Conversation-channel event: someone's reaction on a message changed (protocol 3).

    Carries the resulting state (`added`) rather than a delta, so an add racing a remove resolves
    to last-write-wins at the frame level — the same answer the database gives.
    """
    return {
        'type': 'messages.reaction',
        'message_id': str(message_id),
        'user_id': str(user_id),
        'emoji': emoji,
        'added': added,
    }


def notification_event(notification: dict[str, Any]) -> dict[str, Any]:
    """User-channel event: a new in-app notification (already serialized to a plain dict)."""
    return {'type': 'notification', 'notification': notification}


def announcement_event(audience: str) -> dict[str, Any]:
    """Campus-wide ping that a new announcement was published. Content-free (just the audience) so a
    client can bump an unread counter without leaking staff-only content to students."""
    return {'type': 'announcement', 'audience': audience}


def opportunity_event(audience: str) -> dict[str, Any]:
    """Campus-wide ping that a new opportunity was published. Same content-free shape as
    announcements — clients bump the Opportunities hub badge, not Latest Updates."""
    return {'type': 'opportunity', 'audience': audience}


def message_deleted(conversation_id: UUID | str, message_id: UUID) -> dict[str, Any]:
    """A message was deleted for everyone — clients tombstone it in the open chat.

    `conversation_id` must be the **addressing** id (see `addressing_id`), not the canonical
    conversation id, or the client's open-chat guard will not match it for a DM.
    """
    return {'type': 'message.deleted', 'conversation_id': str(conversation_id), 'message_id': str(message_id)}
