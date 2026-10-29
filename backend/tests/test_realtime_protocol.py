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

    def _msg(match, conversation, *, deleted=False):
        return SimpleNamespace(
            id=uuid4(), match_id=match, conversation_id=conversation, sender_id=uuid4(),
            client_message_id=None, body='secret', created_at=now, read_at=None,
            deleted_at=now if deleted else None,
        )

    dm = _msg(match_id, conv_id)
    group = _msg(None, conv_id)
    deleted_dm = _msg(match_id, conv_id, deleted=True)

    assert serialize_message(dm)['conversation_id'] == str(match_id)          # DM → match id
    assert serialize_message(deleted_dm)['body'] == ''
    assert serialize_message(deleted_dm)['deleted'] is True
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


def test_protocol_5_send_frame_takes_an_optional_reply():
    base = {
        'type': 'message.send', 'request_id': str(uuid4()), 'conversation_id': str(uuid4()),
        'client_message_id': str(uuid4()), 'body': 'ok',
    }
    assert protocol.parse_inbound(base).reply_to_id is None
    target = uuid4()
    assert protocol.parse_inbound({**base, 'reply_to_id': str(target)}).reply_to_id == target


def test_a_serialized_message_carries_its_reply_quote():
    from datetime import UTC, datetime
    from types import SimpleNamespace

    message = SimpleNamespace(
        id=uuid4(), match_id=uuid4(), conversation_id=uuid4(), sender_id=uuid4(),
        client_message_id=None, body='on my way', created_at=datetime(2026, 1, 1, tzinfo=UTC),
        read_at=None, deleted_at=None,
    )
    quote = {'id': str(uuid4()), 'body_snippet': 'see you at 5'}
    assert protocol.serialize_message(message)['reply_to'] is None
    assert protocol.message_created(message, quote)['message']['reply_to'] == quote


def test_protocol_5_frames():
    assert protocol.PROTOCOL_VERSION == 5
    user, message, conversation = uuid4(), uuid4(), uuid4()
    frame = protocol.reaction_change(
        conversation_id=conversation, message_id=message, user_id=user, emoji='👍', added=True,
        user_emoji='👍', reactions=[{'emoji': '👍', 'count': 2}], actor_name='Ama',
        message_sender_id=None, message_snippet='hi', reacted_at='2026-01-01T00:00:00+00:00',
    )
    # The v3 fields an older client applies as a delta are unchanged.
    assert {k: frame[k] for k in ('type', 'message_id', 'user_id', 'emoji', 'added')} == {
        'type': 'messages.reaction', 'message_id': str(message), 'user_id': str(user),
        'emoji': '👍', 'added': True,
    }
    assert frame['conversation_id'] == str(conversation)
    assert protocol.notification_retracted(message) == {'type': 'notification.retracted', 'id': str(message)}
    assert protocol.notifications_read([message])['ids'] == [str(message)]
    assert protocol.conversation_muted(conversation, True)['muted'] is True
    assert protocol.presence(user, online=False, last_seen_at=None, visible=False)['visible'] is False
    assert protocol.ErrorCode.INVALID_REPLY == 'invalid_reply'
