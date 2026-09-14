import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/realtime/realtime_client.dart';
import 'package:lc_connect/core/realtime/ws_protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A socket we control: nothing reaches the network, and inbound frames are injected by hand.
class _FakeSink implements WebSocketSink {
  final List<Object?> added = [];
  final Completer<void> _done = Completer<void>();
  bool closed = false;

  @override
  void add(Object? data) => added.add(data);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (closed) return;
    closed = true;
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<Object?> stream) async {}
}

class _FakeChannel implements WebSocketChannel {
  final StreamController<dynamic> incoming = StreamController<dynamic>.broadcast();
  final _FakeSink fake = _FakeSink();
  final Completer<void> readyCompleter = Completer<void>();

  _FakeChannel({bool readyNow = true}) {
    if (readyNow) readyCompleter.complete();
  }

  @override
  Future<void> get ready => readyCompleter.future;

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  WebSocketSink get sink => fake;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  /// Everything else on StreamChannel is unused by RealtimeClient.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  /// Frames the client wrote, decoded.
  List<Map<String, dynamic>> get written =>
      fake.added.map((e) => jsonDecode(e as String) as Map<String, dynamic>).toList();

  List<Map<String, dynamic>> writtenOfType(String type) =>
      written.where((f) => f['type'] == type).toList();

  void serverSends(Map<String, dynamic> frame) => incoming.add(jsonEncode(frame));

  void serverAuthOk({int heartbeat = 25}) => serverSends({
        'type': 'auth.ok',
        'user_id': 'u1',
        'heartbeat_interval_seconds': heartbeat,
        'protocol_version': 1,
      });
}

RealtimeClient _client(_FakeChannel channel, {Duration? connectTimeout}) =>
    _clientOver([channel], connectTimeout: connectTimeout);

/// Hands out `channels` in order, then repeats the last one — so a reconnect gets a fresh
/// socket the way it would in production.
RealtimeClient _clientOver(List<_FakeChannel> channels, {Duration? connectTimeout}) {
  var i = 0;
  return RealtimeClient(
    url: Uri.parse('ws://localhost/ws'),
    tokenProvider: () async => 'token',
    random: Random(1),
    connectChannel: (_) => channels[i < channels.length - 1 ? i++ : channels.length - 1],
    connectTimeout: connectTimeout ?? const Duration(seconds: 30),
  );
}

void main() {
  group('heartbeat', () {
    test('pings at the server-advertised interval once authenticated', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final client = _client(channel);
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
        final channel = _FakeChannel();
        final client = _client(channel);
        client.connect();
        async.elapse(const Duration(seconds: 120));
        expect(channel.writtenOfType('ping'), isEmpty);
        client.dispose();
        async.flushTimers();
      });
    });

    test('a pong keeps the socket alive and is not republished as an event', () {
      fakeAsync((async) {
        final channel = _FakeChannel();
        final client = _client(channel);
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
        final channel = _FakeChannel();
        final client = _client(channel);
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
        final channel = _FakeChannel();
        final client = _client(channel);
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
        final channel = _FakeChannel();
        final client = _client(channel);
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
        final first = _FakeChannel();
        final second = _FakeChannel();
        final client = _clientOver([first, second]);
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
        final channel = _FakeChannel();
        final client = _client(channel);
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
        final channel = _FakeChannel();
        final client = _client(channel);
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
        final channel = _FakeChannel(readyNow: false); // never becomes ready
        final client = _client(channel, connectTimeout: const Duration(seconds: 5));
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
