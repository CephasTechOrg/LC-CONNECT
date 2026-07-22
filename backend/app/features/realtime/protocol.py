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


# ── Error + close codes ───────────────────────────────────────────────────────

class ErrorCode:
    AUTH_REQUIRED = 'auth_required'
    AUTH_FAILED = 'auth_failed'
    FORBIDDEN = 'forbidden'
    INVALID_FRAME = 'invalid_frame'
    RATE_LIMITED = 'rate_limited'
    NOT_SUBSCRIBED = 'not_subscribed'
    INTERNAL = 'internal_error'


class CloseCode:
    # Application close codes (4000–4999 are private-use).
    AUTH_FAILED = 4401
    FORBIDDEN = 4403
    AUTH_TIMEOUT = 4408
    ABUSE = 4429
    GOING_AWAY = 1001


# ── Inbound frames ────────────────────────────────────────────────────────────

class AuthFrame(BaseModel):
    type: Literal['auth']
    access_token: str = Field(min_length=1, max_length=4096)
    device_id: str | None = Field(default=None, max_length=200)
    app_version: str | None = Field(default=None, max_length=40)


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


class ReadFrame(BaseModel):
    type: Literal['messages.read']
    conversation_id: UUID
    through_message_id: UUID


InboundFrame = Annotated[
    AuthFrame | SubscribeFrame | UnsubscribeFrame | SendFrame | TypingStartFrame | TypingStopFrame | ReadFrame,
    Field(discriminator='type'),
]

_inbound_adapter: TypeAdapter[InboundFrame] = TypeAdapter(InboundFrame)


def parse_inbound(raw: Any) -> InboundFrame:
    """Validate a decoded JSON object into a typed frame. Raises ValidationError."""
    return _inbound_adapter.validate_python(raw)


# ── Outbound builders ─────────────────────────────────────────────────────────

def serialize_message(message: Message) -> dict[str, Any]:
    return {
        'id': str(message.id),
        'conversation_id': str(message.match_id),
        'sender_id': str(message.sender_id),
        'client_message_id': str(message.client_message_id) if message.client_message_id else None,
        'body': message.body,
        'created_at': message.created_at.isoformat(),
        'read_at': message.read_at.isoformat() if message.read_at else None,
    }


def auth_ok(user_id: UUID, heartbeat_seconds: int) -> dict[str, Any]:
    return {'type': 'auth.ok', 'user_id': str(user_id), 'heartbeat_interval_seconds': heartbeat_seconds}


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
    return {'type': 'message.created', 'conversation_id': str(message.match_id), 'message': serialize_message(message)}


def conversation_updated(message: Message) -> dict[str, Any]:
    """User-channel event: a conversation has a new latest message (thread-list update)."""
    return {'type': 'conversation.updated', 'conversation_id': str(message.match_id), 'message': serialize_message(message)}


def typing_event(conversation_id: UUID, user_id: UUID, active: bool) -> dict[str, Any]:
    return {
        'type': 'typing',
        'conversation_id': str(conversation_id),
        'user_id': str(user_id),
        'active': active,
    }


def read_receipt(conversation_id: UUID, user_id: UUID, through_message_id: UUID, read_at_iso: str) -> dict[str, Any]:
    return {
        'type': 'messages.receipt',
        'conversation_id': str(conversation_id),
        'user_id': str(user_id),
        'through_message_id': str(through_message_id),
        'read_at': read_at_iso,
    }
