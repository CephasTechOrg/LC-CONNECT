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

const _original = {
  'id': 'srv-1',
  'match_id': 'match-001',
  'sender_id': 'partner-id',
  'body': 'see you at 5?',
  'created_at': '2026-01-01T00:00:00.000Z',
  'read_at': null,
};

/// Speaks protocol 5 (so Reply is offered) but never connects, so sends go over REST.
class _V5Realtime extends RealtimeClient {
  _V5Realtime() : super(url: Uri.parse('ws://localhost/ws'), tokenProvider: () async => null);

  @override
  bool supportsProtocol(int version) => true;
}

/// Records every request and answers GETs with an empty page. POSTs get whatever
/// [postStatus]/[postBody] say, so a test can play "delivered", "rate limited" or "offline".
class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  int postStatus;
  Map<String, dynamic>? postBody;

  _RecordingAdapter({this.postStatus = 201, this.postBody});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.method != 'POST') {
      // The first page holds one message from the partner, to reply to.
      final page = options.path == '/messages/threads/match-001' &&
              !options.queryParameters.containsKey('before_created_at')
          ? [_original]
          : const [];
      return ResponseBody.fromString(jsonEncode(page), 200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
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
          final client = _V5Realtime();
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

Future<void> _replyToOriginal(WidgetTester tester) async {
  await tester.pumpWidget(_chatScope(_adapter));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.longPress(find.text('see you at 5?'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Reply'));
  await tester.pumpAndSettle();
}

late _RecordingAdapter _adapter;

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost:8000/api/v1\nENV=test');
  });

  testWidgets('a reply shows what it quotes, then sends the quoted id', (tester) async {
    _adapter = _RecordingAdapter(postBody: {
      'id': 'server-2',
      'match_id': 'match-001',
      'sender_id': 'current-user-id',
      'body': 'yes',
      'created_at': '2026-01-01T00:01:00.000Z',
      'read_at': null,
      'reply_to': {'id': 'srv-1', 'sender_id': 'partner-id', 'body_snippet': 'see you at 5?'},
    });
    await _replyToOriginal(tester);
    expect(find.textContaining('Replying to'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'yes');
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump(const Duration(milliseconds: 10));

    expect(_adapter.posts.single.data['reply_to_id'], 'srv-1');
    expect(find.textContaining('Replying to'), findsNothing, reason: 'the bar closes once sent');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });

  testWidgets('a reply whose original was deleted fails with a clear reason', (tester) async {
    _adapter = _RecordingAdapter(postStatus: 409, postBody: {'detail': 'reply_target_deleted'});
    await _replyToOriginal(tester);

    await tester.enterText(find.byType(TextField).last, 'yes');
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();

    expect(find.textContaining('no longer available'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });
}
