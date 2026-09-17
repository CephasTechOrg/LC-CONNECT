import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/api/api_client.dart';
import 'package:lc_connect/core/realtime/realtime_client.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/messages/data/chat_message_cache.dart';
import 'package:lc_connect/features/messages/providers/messages_provider.dart';
import 'package:lc_connect/features/messages/providers/unread_provider.dart';
import 'package:lc_connect/features/messages/screens/chat_screen.dart';

/// Records every request and answers GETs with an empty page. POSTs get whatever
/// [postStatus]/[postBody] say, so a test can play "delivered", "rate limited" or "offline".
class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  int postStatus;
  Map<String, dynamic>? postBody;
  bool postThrowsNetworkError;

  _RecordingAdapter({this.postStatus = 201, this.postBody, this.postThrowsNetworkError = false});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.method != 'POST') {
      return ResponseBody.fromString('[]', 200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    }
    if (postThrowsNetworkError) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    return ResponseBody.fromString(
      jsonEncode(postBody ?? {'detail': 'nope'}),
      postStatus,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}

  List<RequestOptions> get posts => requests.where((r) => r.method == 'POST').toList();
}

class _MockAuthNotifier extends AuthNotifier {
  @override
  Future<AuthUser?> build() async => AuthUser(
        id: 'current-user-id',
        email: 'test@example.com',
        role: 'student',
        profileCompleted: true,
      );
}

class _MockUnreadNotifier extends UnreadNotifier {
  @override
  UnreadState build() => const UnreadState();
}

class _NoopChatCache extends ChatMessageCache {
  @override
  Future<List<ChatMessage>?> load(String conversationId) async => null;

  @override
  Future<void> save(String conversationId, List<ChatMessage> messages) async {}
}

/// A chat wired to an idle realtime client — it never reaches `ready`, so every send sits
/// unacked. That is precisely the situation the REST fallback exists for.
ProviderScope _chatScope(_RecordingAdapter adapter) => ProviderScope(
      overrides: [
        authNotifierProvider.overrideWith(_MockAuthNotifier.new),
        unreadProvider.overrideWith(_MockUnreadNotifier.new),
        realtimeClientProvider.overrideWith((ref) {
          final client = RealtimeClient(
            url: Uri.parse('ws://localhost/ws'),
            tokenProvider: () async => null, // never connects
          );
          ref.onDispose(client.dispose);
          return client;
        }),
        apiClientProvider.overrideWith((ref) {
          final dio = Dio(BaseOptions(baseUrl: 'http://test.local/'))..httpClientAdapter = adapter;
          return ApiClient(dio: dio);
        }),
        chatMessageCacheProvider.overrideWith((ref) => _NoopChatCache()),
      ],
      child: const MaterialApp(home: ChatScreen(matchId: 'match-001')),
    );

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).last, text);
  await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
  await tester.pump();
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost:8000/api/v1\nENV=test');
  });

  /// The realtime client in this scope never reaches `ready`, which is the situation the REST
  /// path exists for — and, since the socket is torn down on every app background, the situation
  /// the *first message after resuming* is always in.
  group('send falls back to REST when the socket cannot carry it', () {
    testWidgets('posts the same client_message_id so the server can dedupe', (tester) async {
      final adapter = _RecordingAdapter(postBody: {
        'id': 'server-1',
        'match_id': 'match-001',
        'sender_id': 'current-user-id',
        'client_message_id': null, // filled in below
        'body': 'hello there',
        'created_at': '2026-01-01T00:00:00.000Z',
        'read_at': null,
      });
      await tester.pumpWidget(_chatScope(adapter));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await _type(tester, 'hello there');
      await tester.pump(const Duration(milliseconds: 10)); // let the POST dispatch

      // A not-ready socket queues the frame in the outbox until the next `auth.ok`, so waiting
      // out the ack timer would buy nothing — HTTP starts immediately instead. Safe only because
      // the server is idempotent on `client_message_id`, which the assertions below pin.
      expect(adapter.posts.length, 1, reason: 'no reason to stall behind a socket that is down');
      final post = adapter.posts.single;
      expect(post.path, '/messages/threads/match-001');
      final body = post.data as Map;
      expect(body['body'], 'hello there');
      expect(body['client_message_id'], isNotNull,
          reason: 'without it the server cannot dedupe a WS/REST race');

      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('sends exactly once — the race must not double-post', (tester) async {
      final adapter = _RecordingAdapter();
      await tester.pumpWidget(_chatScope(adapter));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await _type(tester, 'only once');
      await tester.pump(const Duration(milliseconds: 10));
      expect(adapter.posts.length, 1);

      // Well past the old 6s ack timeout: the immediate escalation must have cancelled the
      // pending WS send, so no second attempt is armed.
      await tester.pump(const Duration(seconds: 8));
      expect(adapter.posts.length, 1, reason: 'the ack timer must not fire a duplicate');
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('a 429 is final — it fails the message instead of retrying forever', (tester) async {
      // Rate limiting is a decision, not a blip: retrying would only deepen the limit.
      final adapter = _RecordingAdapter(
        postStatus: 429,
        postBody: {'detail': 'Slow down — too many messages sent.'},
      );
      await tester.pumpWidget(_chatScope(adapter));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await _type(tester, 'spammy');
      await tester.pump(const Duration(seconds: 7));
      await tester.pump();
      expect(adapter.posts.length, 1);

      await tester.pump(const Duration(seconds: 40));
      await tester.pump();
      expect(adapter.posts.length, 1,
          reason: 'a rate-limited send must not be retried on the slow cadence');

      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('a network failure keeps the message pending rather than failing it', (tester) async {
      // A cold-started server refuses the first HTTP attempt too. The old code failed the
      // bubble at 8s flat; now it stays pending and retries until the deadline.
      final adapter = _RecordingAdapter(postThrowsNetworkError: true);
      await tester.pumpWidget(_chatScope(adapter));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await _type(tester, 'cold start');
      await tester.pump(const Duration(seconds: 7));
      await tester.pump();
      expect(adapter.posts.length, 1);

      // Retries on the slower cadence instead of giving up.
      await tester.pump(const Duration(seconds: 21));
      await tester.pump();
      expect(adapter.posts.length, greaterThan(1),
          reason: 'a transient network error must be retried, not treated as a rejection');

      await tester.pump(const Duration(seconds: 60));
    });
  });
}
