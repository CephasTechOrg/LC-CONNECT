"""Wire-protocol parsing: valid frames, unknown types, oversized/empty bodies."""

from uuid import uuid4

import pytest
from pydantic import ValidationError

from app.features.realtime import protocol


def test_parses_auth_frame():
    frame = protocol.parse_inbound({'type': 'auth', 'access_token': 'tok'})
    assert isinstance(frame, protocol.AuthFrame)
    assert frame.access_token == 'tok'


def test_frames_address_dm_by_match_id_and_group_by_conversation_id():
    """A DM message's frames carry its match id; a group message (match_id=None) must carry the
    conversation id — never the string 'None' — so the client can route it to the open chat."""
    from types import SimpleNamespace
    from uuid import uuid4

    from app.features.realtime.protocol import conversation_updated, message_created, serialize_message

    now = __import__('datetime').datetime(2026, 1, 1, tzinfo=__import__('datetime').UTC)
    match_id, conv_id = uuid4(), uuid4()

    def _msg(match, conversation):
        return SimpleNamespace(
            id=uuid4(), match_id=match, conversation_id=conversation, sender_id=uuid4(),
            client_message_id=None, body='hi', created_at=now, read_at=None,
        )

    dm = _msg(match_id, conv_id)
    group = _msg(None, conv_id)

    assert serialize_message(dm)['conversation_id'] == str(match_id)          # DM → match id
    assert message_created(group)['conversation_id'] == str(conv_id)          # group → conv id
    assert conversation_updated(group)['conversation_id'] == str(conv_id)
    assert 'None' not in message_created(group)['conversation_id']            # never str(None)


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
