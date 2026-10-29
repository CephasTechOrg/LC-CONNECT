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

/// Answers every request with an empty list; this test never sends.
class _RecordingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async =>
      ResponseBody.fromString('[]', 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

  @override
  void close({bool force = false}) {}
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

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost:8000/api/v1\nENV=test');
  });

  // The socket in this scope never connects — the state a resume is in for its first moments.
  testWidgets('"Connecting…" waits before showing, so a quick reconnect never flashes it',
      (tester) async {
    await tester.pumpWidget(_chatScope(_RecordingAdapter()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Connecting…'), findsNothing);
    expect(find.text('Offline — reconnecting…'), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    expect(
      find.textContaining('onnecting…'),
      findsOneWidget,
      reason: 'a socket that stays down long enough to matter is still announced',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });
}
