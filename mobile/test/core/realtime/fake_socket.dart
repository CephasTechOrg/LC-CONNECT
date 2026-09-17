import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:lc_connect/core/realtime/realtime_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Shared across the realtime socket tests.
///
/// Extracted from `realtime_client_socket_test.dart` when Phase 3 began adding connection-level
/// tests: the client's behaviour after `auth.ok` is only observable across a real lifecycle, and
/// keeping every such test in one file was walking it toward the 600-line cap.

/// A socket we control: nothing reaches the network, and inbound frames are injected by hand.
class FakeWsSink implements WebSocketSink {
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

class FakeWsChannel implements WebSocketChannel {
  final StreamController<dynamic> incoming = StreamController<dynamic>.broadcast();
  final FakeWsSink fake = FakeWsSink();
  final Completer<void> readyCompleter = Completer<void>();

  FakeWsChannel({bool readyNow = true}) {
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

  void serverAuthOk({int heartbeat = 25, int? protocolVersion = 1}) => serverSends({
        'type': 'auth.ok',
        'user_id': 'u1',
        'heartbeat_interval_seconds': heartbeat,
        // Omitted when null: a server predating the field, which the client must read as v1.
        'protocol_version': ?protocolVersion,
      });
}

/// A client wired to one socket — the common case, where no reconnect is involved.
RealtimeClient clientOn(FakeWsChannel channel, {Duration? connectTimeout}) =>
    clientOver([channel], connectTimeout: connectTimeout);

/// Hands out `channels` in order, then repeats the last one — so a reconnect gets a fresh
/// socket the way it would in production.
RealtimeClient clientOver(List<FakeWsChannel> channels, {Duration? connectTimeout}) {
  var i = 0;
  return RealtimeClient(
    url: Uri.parse('ws://localhost/ws'),
    tokenProvider: () async => 'token',
    random: Random(1),
    connectChannel: (_) => channels[i < channels.length - 1 ? i++ : channels.length - 1],
    connectTimeout: connectTimeout ?? const Duration(seconds: 30),
  );
}
