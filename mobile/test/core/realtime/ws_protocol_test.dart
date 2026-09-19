import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/realtime/ws_protocol.dart';

void main() {
  group('outbound frames', () {
    test('authFrame includes token, omits null optionals', () {
      final f = authFrame('tok');
      expect(f['type'], 'auth');
      expect(f['access_token'], 'tok');
      expect(f.containsKey('device_id'), isFalse);
    });

    test('sendFrame has all required fields', () {
      final f = sendFrame(requestId: 'r', conversationId: 'c', clientMessageId: 'm', body: 'hi');
      expect(f, {
        'type': 'message.send',
        'request_id': 'r',
        'conversation_id': 'c',
        'client_message_id': 'm',
        'body': 'hi',
      });
    });

    test('typingFrame toggles start/stop', () {
      expect(typingFrame('c', active: true)['type'], 'typing.start');
      expect(typingFrame('c', active: false)['type'], 'typing.stop');
    });
  });

  group('parseInbound', () {
    test('auth.ok', () {
      final e = parseInbound({'type': 'auth.ok', 'user_id': 'u', 'heartbeat_interval_seconds': 25});
      expect(e, isA<AuthOk>());
      expect((e as AuthOk).userId, 'u');
      expect(e.heartbeatSeconds, 25);
    });

    test('message.ack carries duplicate + message', () {
      final e = parseInbound({
        'type': 'message.ack',
        'client_message_id': 'm',
        'duplicate': true,
        'message': {'id': 's1', 'body': 'hi'},
      });
      expect(e, isA<MessageAck>());
      final ack = e as MessageAck;
      expect(ack.duplicate, isTrue);
      expect(ack.clientMessageId, 'm');
      expect(ack.message['id'], 's1');
    });

    test('message.created', () {
      final e = parseInbound({'type': 'message.created', 'conversation_id': 'c', 'message': {'id': 's'}});
      expect(e, isA<MessageCreated>());
      expect((e as MessageCreated).conversationId, 'c');
    });

    test('conversation.updated', () {
      final e = parseInbound({'type': 'conversation.updated', 'conversation_id': 'c', 'message': {'id': 's'}});
      expect(e, isA<ConversationUpdated>());
    });

    test('typing', () {
      final e = parseInbound({'type': 'typing', 'conversation_id': 'c', 'user_id': 'u', 'active': false});
      expect(e, isA<TypingEvent>());
      expect((e as TypingEvent).active, isFalse);
    });

    test('messages.receipt', () {
      final e = parseInbound({
        'type': 'messages.receipt',
        'conversation_id': 'c',
        'user_id': 'u',
        'through_message_id': 't',
        'read_at': '2026-01-01T00:00:00Z',
      });
      expect(e, isA<ReadReceipt>());
    });

    test('error', () {
      final e = parseInbound({'type': 'error', 'code': 'forbidden', 'message': 'no'});
      expect(e, isA<WsError>());
      expect((e as WsError).code, 'forbidden');
    });

    test('announcement and opportunity pings', () {
      final a = parseInbound({'type': 'announcement', 'audience': 'students'});
      expect(a, isA<AnnouncementEvent>());
      expect((a as AnnouncementEvent).audience, 'students');

      final o = parseInbound({'type': 'opportunity', 'audience': 'all'});
      expect(o, isA<OpportunityEvent>());
      expect((o as OpportunityEvent).audience, 'all');
    });

    test('unknown type', () {
      expect(parseInbound({'type': 'mystery'}), isA<UnknownEvent>());
    });
  });

  group('keepalive + error correlation', () {
    test('pingFrame is the bare keepalive the server expects', () {
      expect(pingFrame(), {'type': 'ping'});
    });

    test('parseInbound understands pong', () {
      expect(parseInbound({'type': 'pong'}), isA<Pong>());
    });

    test('WsError carries request_id so one failure is not blamed on every send', () {
      final e = parseInbound({
        'type': 'error',
        'code': 'rate_limited',
        'message': 'Slow down',
        'request_id': 'req-1',
      }) as WsError;
      expect(e.code, 'rate_limited');
      expect(e.requestId, 'req-1');
    });

    test('WsError without request_id is connection-wide, not attributable', () {
      final e = parseInbound({'type': 'error', 'code': 'idle_timeout', 'message': 'idle'}) as WsError;
      expect(e.requestId, isNull);
    });
  });

  /// Protocol 2 — the delivered tick (report #21).
  group('delivery frames', () {
    test('deliveredFrame carries the boundary, not a message flag', () {
      final frame = deliveredFrame('conv-1', 'msg-9');
      expect(frame['type'], 'messages.delivered');
      expect(frame['conversation_id'], 'conv-1');
      expect(frame['through_message_id'], 'msg-9');
    });

    test('parseInbound understands messages.delivery', () {
      final event = parseInbound({
        'type': 'messages.delivery',
        'conversation_id': 'conv-1',
        'user_id': 'them',
        'through_message_id': 'msg-9',
        'delivered_at': '2026-01-01T00:00:00.000Z',
      });

      expect(event, isA<DeliveryReceipt>());
      final receipt = event as DeliveryReceipt;
      expect(receipt.conversationId, 'conv-1');
      expect(receipt.userId, 'them');
      expect(receipt.throughMessageId, 'msg-9');
      expect(receipt.deliveredAt, '2026-01-01T00:00:00.000Z');
    });

    test('a delivery receipt is not confused with a read receipt', () {
      // Two ticks now hang off these, and mixing them up shows "read" for a message nobody has
      // opened — a claim about another person that is simply false.
      final delivery = parseInbound({
        'type': 'messages.delivery',
        'conversation_id': 'c',
        'user_id': 'u',
        'through_message_id': 'm',
        'delivered_at': '2026-01-01T00:00:00.000Z',
      });
      final read = parseInbound({
        'type': 'messages.receipt',
        'conversation_id': 'c',
        'user_id': 'u',
        'through_message_id': 'm',
        'read_at': '2026-01-01T00:00:00.000Z',
      });

      expect(delivery, isA<DeliveryReceipt>());
      expect(delivery, isNot(isA<ReadReceipt>()));
      expect(read, isA<ReadReceipt>());
      expect(read, isNot(isA<DeliveryReceipt>()));
    });

    test('the client advertises its current protocol version', () {
      // Bumped to 3 by reactions. `kDeliveryProtocolVersion` stays at 2 on purpose: it is the
      // version delivery *arrived* in, and gating on the current version would stop a v2 server
      // from getting delivery acknowledgements it understands perfectly well.
      expect(kProtocolVersion, 3);
      expect(kDeliveryProtocolVersion, 2);
      expect(kReactionProtocolVersion, 3);
      expect(authFrame('tok')['protocol_version'], kProtocolVersion);
    });
  });

  /// Protocol 3 — reactions (report #4).
  group('reaction frames', () {
    test('parseInbound understands messages.reaction', () {
      final event = parseInbound({
        'type': 'messages.reaction',
        'message_id': 'msg-1',
        'user_id': 'them',
        'emoji': '👍',
        'added': true,
      });

      expect(event, isA<ReactionEvent>());
      final reaction = event as ReactionEvent;
      expect(reaction.messageId, 'msg-1');
      expect(reaction.userId, 'them');
      expect(reaction.emoji, '👍');
      expect(reaction.added, isTrue);
    });

    test('a removal is the same frame with added false', () {
      // State, not a delta — so an add racing a remove is last-write-wins, matching the database.
      final event = parseInbound({
        'type': 'messages.reaction',
        'message_id': 'msg-1',
        'user_id': 'them',
        'emoji': '👍',
        'added': false,
      }) as ReactionEvent;

      expect(event.added, isFalse);
    });

    test('a frame missing `added` is treated as an add', () {
      // Defensive: the field is always sent, and defaulting to "removed" would silently drop a
      // chip that exists.
      final event = parseInbound({
        'type': 'messages.reaction',
        'message_id': 'msg-1',
        'user_id': 'them',
        'emoji': '👍',
      }) as ReactionEvent;

      expect(event.added, isTrue);
    });
  });
}
