"""Wire-protocol parsing: valid frames, unknown types, oversized/empty bodies."""

from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.features.realtime import protocol


def test_parses_auth_frame():
    frame = protocol.parse_inbound({'type': 'auth', 'access_token': 'tok'})
    assert isinstance(frame, protocol.AuthFrame)
    assert frame.access_token == 'tok'


def test_parses_send_frame_and_strips_body():
    raw = {
        'type': 'message.send',
        'request_id': str(uuid4()),
        'conversation_id': str(uuid4()),
        'client_message_id': str(uuid4()),
        'body': '  hi  ',
    }
    frame = protocol.parse_inbound(raw)
    assert isinstance(frame, protocol.SendFrame)
    assert frame.body == 'hi'


def test_rejects_unknown_type():
    with pytest.raises(ValidationError):
        protocol.parse_inbound({'type': 'nope'})


def test_rejects_missing_discriminator():
    with pytest.raises(ValidationError):
        protocol.parse_inbound({'access_token': 'x'})


def test_rejects_empty_body():
    raw = {
        'type': 'message.send',
        'request_id': str(uuid4()),
        'conversation_id': str(uuid4()),
        'client_message_id': str(uuid4()),
        'body': '   ',
    }
    with pytest.raises(ValidationError):
        protocol.parse_inbound(raw)


def test_rejects_oversized_body():
    raw = {
        'type': 'message.send',
        'request_id': str(uuid4()),
        'conversation_id': str(uuid4()),
        'client_message_id': str(uuid4()),
        'body': 'x' * (protocol.MAX_BODY_CHARS + 1),
    }
    with pytest.raises(ValidationError):
        protocol.parse_inbound(raw)


def test_rejects_non_uuid_conversation():
    with pytest.raises(ValidationError):
        protocol.parse_inbound({'type': 'typing.start', 'conversation_id': 'not-a-uuid'})
