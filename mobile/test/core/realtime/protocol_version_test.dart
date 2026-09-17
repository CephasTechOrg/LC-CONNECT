import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/realtime/ws_protocol.dart';

import 'fake_socket.dart';

void main() {
  /// Phase 3 step 1 — the client must keep what `auth.ok` negotiated.
  ///
  /// `protocol_version` was parsed into [AuthOk] and then discarded, so nothing could tell
  /// whether the connected server understands a frame before sending it. During a staged
  /// rollout it frequently does not: this build reaches TestFlight alongside, or ahead of, the
  /// API deploy. See `docs/features/messaging/phase3_design.md` §0a.
  group('negotiated protocol version', () {
    test('is zero until auth.ok, then whatever the server advertised', () {
      fakeAsync((async) {
        final channel = FakeWsChannel();
        final client = clientOn(channel);
        client.connect();
        async.flushMicrotasks();

        // Zero rather than `kProtocolVersion`: assuming the peer speaks whatever we speak is
        // exactly the bug being prevented.
        expect(client.serverProtocolVersion, 0);
        expect(client.supportsProtocol(1), isFalse);

        channel.serverAuthOk(protocolVersion: 2);
        async.flushMicrotasks();

        expect(client.serverProtocolVersion, 2);
        expect(client.supportsProtocol(2), isTrue);
        expect(client.supportsProtocol(1), isTrue, reason: 'a v2 server still speaks v1');

        client.dispose();
        async.flushTimers();
      });
    });

    test('a newer client against an older server does not claim support', () {
      fakeAsync((async) {
        final channel = FakeWsChannel();
        final client = clientOn(channel);
        client.connect();
        async.flushMicrotasks();
        channel.serverAuthOk(protocolVersion: 1);
        async.flushMicrotasks();

        // The whole point of the gate: sending a v2 frame here earns `unsupported_frame`, so
        // the feature must present as unavailable instead of writing into a void.
        expect(client.supportsProtocol(2), isFalse);

        client.dispose();
        async.flushTimers();
      });
    });

    test('a server that omits protocol_version is read as v1', () {
      fakeAsync((async) {
        final channel = FakeWsChannel();
        final client = clientOn(channel);
        client.connect();
        async.flushMicrotasks();
        channel.serverAuthOk(protocolVersion: null);
        async.flushMicrotasks();

        expect(client.serverProtocolVersion, 1);

        client.dispose();
        async.flushTimers();
      });
    });

    test('the client still advertises its own version outbound', () {
      fakeAsync((async) {
        final channel = FakeWsChannel();
        final client = clientOn(channel);
        client.connect();
        async.flushMicrotasks();

        // Negotiation is two-sided; retaining the server's answer must not drop ours.
        expect(channel.writtenOfType('auth').single['protocol_version'], kProtocolVersion);

        client.dispose();
        async.flushTimers();
      });
    });

    test('is renegotiated on a reconnect rather than inherited', () {
      fakeAsync((async) {
        final first = FakeWsChannel();
        final second = FakeWsChannel();
        final client = clientOver([first, second]);
        client.connect();
        async.flushMicrotasks();
        first.serverAuthOk(protocolVersion: 2);
        async.flushMicrotasks();
        expect(client.serverProtocolVersion, 2);

        first.incoming.close(); // the socket drops
        async.flushMicrotasks();

        // Cleared immediately, before the new handshake: a reconnect can land on an instance
        // running an older build than the one that just answered, and a stale 2 would gate a v2
        // frame open against a v1 server.
        expect(client.serverProtocolVersion, 0);

        async.elapse(const Duration(seconds: 31)); // past the backoff cap
        async.flushMicrotasks();
        second.serverAuthOk(protocolVersion: 1);
        async.flushMicrotasks();

        expect(client.serverProtocolVersion, 1, reason: 'the new socket decides, not the old one');

        client.dispose();
        async.flushTimers();
      });
    });
  });

  /// The gate this whole mechanism exists for.
  group('gating a protocol 2 frame', () {
    test('a delivered frame is not sent to a v1 server', () {
      fakeAsync((async) {
        final channel = FakeWsChannel();
        final client = clientOn(channel);
        client.connect();
        async.flushMicrotasks();
        channel.serverAuthOk(protocolVersion: 1);
        async.flushMicrotasks();

        // Reported, not silently dropped: the caller needs to know delivery state is unavailable
        // on this connection rather than wait for a tick that is never coming.
        expect(client.markDelivered('conv-1', 'msg-1'), isFalse);
        expect(channel.writtenOfType('messages.delivered'), isEmpty);

        client.dispose();
        async.flushTimers();
      });
    });

    test('a delivered frame is sent to a v2 server', () {
      fakeAsync((async) {
        final channel = FakeWsChannel();
        final client = clientOn(channel);
        client.connect();
        async.flushMicrotasks();
        channel.serverAuthOk(protocolVersion: 2);
        async.flushMicrotasks();

        expect(client.markDelivered('conv-1', 'msg-1'), isTrue);
        final sent = channel.writtenOfType('messages.delivered');
        expect(sent, hasLength(1));
        expect(sent.single['through_message_id'], 'msg-1');

        client.dispose();
        async.flushTimers();
      });
    });

    test('a delivered frame is not sent before the handshake', () {
      fakeAsync((async) {
        final channel = FakeWsChannel();
        final client = clientOn(channel);
        client.connect();
        async.flushMicrotasks();

        // Nothing is negotiated yet, so nothing is supported — and `_sink` would discard it
        // anyway, which would look like a delivered frame that vanished.
        expect(client.markDelivered('conv-1', 'msg-1'), isFalse);

        client.dispose();
        async.flushTimers();
      });
    });
  });
}
