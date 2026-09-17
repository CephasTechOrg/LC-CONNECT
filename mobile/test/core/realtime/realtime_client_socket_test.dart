
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/realtime/realtime_client.dart';
import 'package:lc_connect/core/realtime/ws_protocol.dart';

import 'fake_socket.dart';

void main() {
  group('heartbeat', () {
    test('pings at the server-advertised interval once authenticated', () {
      fakeAsync((async) {
        final channel = FakeWsChannel();
        final client = clientOn(channel);
        client.connect();
        async.flushMicrotasks();
        channel.serverAuthOk(heartbeat: 10);
        async.flushMicrotasks();

        expect(channel.writtenOfType('ping'), isEmpty, reason: 'no ping before the interval');

        // A healthy server answers every ping; without that the client would (correctly)
        // conclude the socket is half-open and stop pinging to reconnect instead.
        for (var i = 1; i <= 3; i++) {
          async.elapse(const Duration(seconds: 10));
          expect(channel.writtenOfType('ping').length, i);
          channel.serverSends({'type': 'pong'});
          async.flushMicrotasks();
        }

        client.dispose();
        async.flushTimers();
      });
    });

    test('does not ping before auth.ok', () {
      fakeAsync((async) {
        final channel = FakeWsChannel();
        final client = clientOn(channel);
        client.connect();
        async.elapse(const Duration(seconds: 120));
        expect(channel.writtenOfType('ping'), isEmpty);
        client.dispose();
        async.flushTimers();
      });
    });

    test('a pong keeps the socket alive and is not republished as an event', () {
      fakeAsync((async) {
        final channel = FakeWsChannel();
        final client = clientOn(channel);
        final events = <InboundEvent>[];
        client.events.listen(events.add);
        client.connect();
        async.flushMicrotasks();
        channel.serverAuthOk(heartbeat: 10);
        async.flushMicrotasks();

        // Reply to every ping, as a healthy server would.
        for (var i = 0; i < 6; i++) {
          async.elapse(const Duration(seconds: 10));
          channel.serverSends({'type': 'pong'});
          async.flushMicrotasks();
        }

        expect(client.status.value, RealtimeStatus.ready, reason: 'watchdog must not fire');
        expect(events.whereType<Pong>(), isEmpty, reason: 'pong is liveness, not an app event');
        client.dispose();
        async.flushTimers();
      });
    });

    test('watchdog reconnects when the server stops answering (half-open socket)', () {
      fakeAsync((async) {
        final channel = FakeWsChannel();
        final client = clientOn(channel);
        client.connect();
        async.flushMicrotasks();
        channel.serverAuthOk(heartbeat: 10);
        async.flushMicrotasks();
        expect(client.status.value, RealtimeStatus.ready);

        // Server goes silent: writes still "succeed" but nothing comes back. Two silent
        // intervals are tolerated, so the third tick (30s at heartbeat 10) gives up.
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();

        expect(client.status.value, isNot(RealtimeStatus.ready),
            reason: 'a stalled read must force a reconnect, not sit there looking connected');
        client.dispose();
        async.flushTimers();
      });
    });
  });

  group('in-flight sends survive a disconnect', () {
    test('a send written to a ready socket is re-queued when the socket closes', () {
      fakeAsync((async) {
        final channel = FakeWsChannel();
        final client = clientOn(channel);
        client.connect();
        async.flushMicrotasks();
        channel.serverAuthOk();
        async.flushMicrotasks();

        expect(client.sendMessage(conversationId: 'c1', clientMessageId: 'm1', body: 'hi'), isTrue);
        expect(channel.writtenOfType('message.send').length, 1);
        expect(client.outboxCount.value, 0, reason: 'written, not queued');

        // Socket dies before the ack arrives.
        channel.incoming.close();
        async.flushMicrotasks();

        expect(client.outboxCount.value, 1,
            reason: 'an unacked send must go back to the outbox, not vanish');
        client.dispose();
        async.flushTimers();
      });
    });

    test('an acked send is NOT re-queued', () {
      fakeAsync((async) {
        final channel = FakeWsChannel();
        final client = clientOn(channel);
        client.connect();
        async.flushMicrotasks();
        channel.serverAuthOk();
        async.flushMicrotasks();

        client.sendMessage(conversationId: 'c1', clientMessageId: 'm1', body: 'hi');
        channel.serverSends({
          'type': 'message.ack',
          'request_id': channel.writtenOfType('message.send').first['request_id'],
          'client_message_id': 'm1',
          'duplicate': false,
          'message': {'id': 's1', 'conversation_id': 'c1', 'sender_id': 'u1', 'body': 'hi',
                      'created_at': '2026-01-01T00:00:00Z', 'client_message_id': 'm1'},
        });
        async.flushMicrotasks();

        channel.incoming.close();
        async.flushMicrotasks();

        expect(client.outboxCount.value, 0, reason: 'already delivered — must not send twice');
        client.dispose();
        async.flushTimers();
      });
    });

    test('re-queued sends are flushed over the reconnected socket', () {
      fakeAsync((async) {
        final first = FakeWsChannel();
        final second = FakeWsChannel();
        final client = clientOver([first, second]);
        client.connect();
        async.flushMicrotasks();
        first.serverAuthOk();
        async.flushMicrotasks();
        client.sendMessage(conversationId: 'c1', clientMessageId: 'm1', body: 'hi');

        first.incoming.close(); // socket dies before the ack
        async.flushMicrotasks();
        expect(client.outboxCount.value, 1);

        async.elapse(const Duration(seconds: 31)); // let backoff reconnect
        async.flushMicrotasks();
        second.serverAuthOk();
        async.flushMicrotasks();

        expect(second.writtenOfType('message.send').length, 1,
            reason: 'the queued send must be retried on the new socket');
        expect(second.writtenOfType('message.send').first['client_message_id'], 'm1');
        expect(client.outboxCount.value, 0);
        client.dispose();
        async.flushTimers();
      });
    });
  });

  group('error correlation', () {
    test('maps a request id back to its client message id', () {
      fakeAsync((async) {
        final channel = FakeWsChannel();
        final client = clientOn(channel);
        client.connect();
        async.flushMicrotasks();
        channel.serverAuthOk();
        async.flushMicrotasks();

        client.sendMessage(conversationId: 'c1', clientMessageId: 'm1', body: 'hi');
        final requestId = channel.writtenOfType('message.send').first['request_id'] as String;

        expect(client.clientMessageIdForRequest(requestId), 'm1');
        expect(client.clientMessageIdForRequest('not-a-request'), isNull,
            reason: 'an unattributable error must not be blamed on some arbitrary message');
        client.dispose();
        async.flushTimers();
      });
    });

    test('cancelPendingSend stops a message being retried after REST delivery', () {
      fakeAsync((async) {
        final channel = FakeWsChannel();
        final client = clientOn(channel);
        client.connect();
        async.flushMicrotasks();
        channel.serverAuthOk();
        async.flushMicrotasks();

        client.sendMessage(conversationId: 'c1', clientMessageId: 'm1', body: 'hi');
        client.cancelPendingSend('m1'); // delivered over REST instead

        channel.incoming.close();
        async.flushMicrotasks();

        expect(client.outboxCount.value, 0, reason: 'REST already delivered it');
        client.dispose();
        async.flushTimers();
      });
    });
  });

  group('connect timeout', () {
    test('gives up on a handshake that never completes instead of hanging in connecting', () {
      fakeAsync((async) {
        final channel = FakeWsChannel(readyNow: false); // never becomes ready
        final client = clientOn(channel, connectTimeout: const Duration(seconds: 5));
        client.connect();
        async.flushMicrotasks();
        expect(client.status.value, RealtimeStatus.connecting);

        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();

        // The client abandons the stalled handshake and schedules a retry. Asserting on
        // `status` would be ambiguous — the retry puts it back in `connecting` — so assert the
        // dead socket was actually closed rather than left dangling.
        expect(channel.fake.closed, isTrue,
            reason: 'a cold-start hang must be abandoned, not left blocking every send');
        client.dispose();
        async.flushTimers();
      });
    });
  });
}
