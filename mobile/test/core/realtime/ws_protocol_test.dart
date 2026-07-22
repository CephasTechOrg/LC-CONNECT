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

    test('unknown type', () {
      expect(parseInbound({'type': 'mystery'}), isA<UnknownEvent>());
    });
  });
}
