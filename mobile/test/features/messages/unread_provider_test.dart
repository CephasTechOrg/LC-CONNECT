import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/api/api_client.dart';
import 'package:lc_connect/core/realtime/realtime_client.dart';
import 'package:lc_connect/core/realtime/ws_protocol.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/messages/providers/unread_provider.dart';

const _me = 'me';

class _MockAuth extends AuthNotifier {
  @override
  Future<AuthUser?> build() async => AuthUser(
        id: _me,
        email: 'me@example.com',
        role: 'student',
        profileCompleted: true,
      );
}

/// RealtimeClient whose event/reconnect streams we drive manually.
class _FakeRealtime extends RealtimeClient {
  final _ev = StreamController<InboundEvent>.broadcast();
  final _rc = StreamController<void>.broadcast();
  _FakeRealtime() : super(url: Uri.parse('ws://test'), tokenProvider: _noToken);
  static Future<String?> _noToken() async => null;

  @override
  Stream<InboundEvent> get events => _ev.stream;
  @override
  Stream<void> get reconnected => _rc.stream;

  void emit(InboundEvent e) => _ev.add(e);
  Future<void> closeStreams() async {
    await _ev.close();
    await _rc.close();
  }
}

class _SummaryAdapter implements HttpClientAdapter {
  final String body;
  _SummaryAdapter(this.body);
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async =>
      ResponseBody.fromString(body, 200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
  @override
  void close({bool force = false}) {}
}

ApiClient _stubApi(String summaryJson) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/'))
    ..httpClientAdapter = _SummaryAdapter(summaryJson);
  return ApiClient(dio: dio);
}

ConversationUpdated _incoming(String conv, String sender) => ConversationUpdated(conv, {
      'id': 'm-$sender',
      'match_id': conv,
      'sender_id': sender,
      'body': 'hi',
      'created_at': '2026-01-01T00:00:00.000Z',
    });

/// Builds the container, lets auth resolve + the initial seed run.
Future<(ProviderContainer, _FakeRealtime)> _ready(
    {String summary = '{"total":0,"per_conversation":{}}'}) async {
  final rt = _FakeRealtime();
  final c = ProviderContainer(overrides: [
    authNotifierProvider.overrideWith(_MockAuth.new),
    realtimeClientProvider.overrideWithValue(rt),
    apiClientProvider.overrideWith((ref) => _stubApi(summary)),
  ]);
  // Keep it actively listened so it eagerly rebuilds on the auth change (and its
  // event listener stays live) rather than recomputing lazily on the next read.
  c.listen(unreadProvider, (_, _) {}, fireImmediately: true);
  await c.read(authNotifierProvider.future); // resolve auth → triggers rebuild + seed
  await pumpEventQueue();
  return (c, rt);
}

void main() {
  // UnreadNotifier registers a WidgetsBindingObserver (app-resume re-seed), which
  // needs the binding initialized even in these non-widget tests.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('increments on a partner message', () async {
    final (c, rt) = await _ready();
    rt.emit(_incoming('conv-1', 'partner'));
    await pumpEventQueue();

    expect(c.read(unreadProvider).total, 1);
    expect(c.read(unreadProvider).countFor('conv-1'), 1);
    await rt.closeStreams();
    c.dispose();
  });

  test('ignores my own messages', () async {
    final (c, rt) = await _ready();
    rt.emit(_incoming('conv-1', _me));
    await pumpEventQueue();

    expect(c.read(unreadProvider).total, 0);
    await rt.closeStreams();
    c.dispose();
  });

  test('does not inflate the badge for the actively-open conversation', () async {
    final (c, rt) = await _ready();
    c.read(unreadProvider.notifier).enterConversation('conv-1');

    rt.emit(_incoming('conv-1', 'partner')); // being read live → ignored
    await pumpEventQueue();
    expect(c.read(unreadProvider).total, 0);

    c.read(unreadProvider.notifier).leaveConversation();
    rt.emit(_incoming('conv-1', 'partner')); // now counts
    await pumpEventQueue();
    expect(c.read(unreadProvider).total, 1);
    await rt.closeStreams();
    c.dispose();
  });

  test('clearConversation zeroes a conversation and adjusts the total', () async {
    final (c, rt) = await _ready();
    rt.emit(_incoming('conv-1', 'partner'));
    rt.emit(_incoming('conv-1', 'partner'));
    rt.emit(_incoming('conv-2', 'partner'));
    await pumpEventQueue();
    expect(c.read(unreadProvider).total, 3);

    c.read(unreadProvider.notifier).clearConversation('conv-1');
    expect(c.read(unreadProvider).countFor('conv-1'), 0);
    expect(c.read(unreadProvider).total, 1); // conv-2 remains
    await rt.closeStreams();
    c.dispose();
  });

  test('seeds total + per-conversation from the backend summary', () async {
    final (c, rt) =
        await _ready(summary: '{"total":5,"per_conversation":{"conv-9":5}}');
    expect(c.read(unreadProvider).total, 5);
    expect(c.read(unreadProvider).countFor('conv-9'), 5);
    await rt.closeStreams();
    c.dispose();
  });
}
