import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/api/api_client.dart';
import 'package:lc_connect/core/realtime/realtime_client.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/messages/data/chat_draft_store.dart';
import 'package:lc_connect/features/messages/data/chat_message_cache.dart';
import 'package:lc_connect/features/messages/providers/messages_provider.dart';
import 'package:lc_connect/features/messages/providers/unread_provider.dart';
import 'package:lc_connect/features/messages/screens/chat_screen.dart';

import '../../core/realtime/fake_socket.dart';

/// Locks the Wave A `_hasMenu` fix: a partner bubble must open the reaction picker on
/// long-press when report/delete are not the only menu reasons.
const _me = 'current-user-id';
const _them = 'partner-user-id';

class _PartnerPageAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? _) async {
    if (o.method != 'GET') {
      return ResponseBody.fromString(
        '{}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode([
        {
          'id': 'partner-1',
          'match_id': 'match-001',
          'sender_id': _them,
          'client_message_id': null,
          'body': 'hello from partner',
          'created_at': '2026-01-01T10:00:00.000Z',
          'read_at': null,
          'delivered': true,
          'reactions': <Map<String, dynamic>>[],
        },
      ]),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MockAuthNotifier extends AuthNotifier {
  @override
  Future<AuthUser?> build() async => AuthUser(
        id: _me,
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

class _NoopDraftStore extends ChatDraftStore {
  @override
  Future<String?> load(String conversationId) async => null;

  @override
  Future<void> save(String conversationId, String text) async {}

  @override
  Future<void> delete(String conversationId) async {}
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost:8000/api/v1\nENV=test');
  });

  testWidgets('long-press partner message opens reaction picker', (tester) async {
    final socket = FakeWsChannel();
    final client = clientOn(socket);
    final adapter = _PartnerPageAdapter();

    Widget scope(Widget child) => ProviderScope(
          overrides: [
            authNotifierProvider.overrideWith(_MockAuthNotifier.new),
            unreadProvider.overrideWith(_MockUnreadNotifier.new),
            realtimeClientProvider.overrideWith((ref) {
              ref.onDispose(client.dispose);
              return client;
            }),
            apiClientProvider.overrideWith(
              (ref) => ApiClient(
                dio: Dio(BaseOptions(baseUrl: 'http://test.local/'))..httpClientAdapter = adapter,
              ),
            ),
            chatMessageCacheProvider.overrideWith((ref) => _NoopChatCache()),
            chatDraftStoreProvider.overrideWith((ref) => _NoopDraftStore()),
          ],
          child: MaterialApp(home: child),
        );

    await tester.pumpWidget(
      scope(
        Consumer(
          builder: (context, ref, _) {
            ref.watch(authNotifierProvider);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(scope(const ChatScreen(matchId: 'match-001')));
    await client.connect();
    socket.serverAuthOk(protocolVersion: 3);
    await tester.pumpAndSettle();

    expect(find.text('hello from partner'), findsOneWidget);

    await tester.longPress(find.text('hello from partner'));
    await tester.pumpAndSettle();

    // Picker exposes each allowlisted emoji as its own semantics label.
    expect(find.text('👍'), findsOneWidget);
    expect(find.text('❤️'), findsOneWidget);
  });

  testWidgets('double-tap partner message opens reaction picker', (tester) async {
    final socket = FakeWsChannel();
    final client = clientOn(socket);
    final adapter = _PartnerPageAdapter();

    Widget scope(Widget child) => ProviderScope(
          overrides: [
            authNotifierProvider.overrideWith(_MockAuthNotifier.new),
            unreadProvider.overrideWith(_MockUnreadNotifier.new),
            realtimeClientProvider.overrideWith((ref) {
              ref.onDispose(client.dispose);
              return client;
            }),
            apiClientProvider.overrideWith(
              (ref) => ApiClient(
                dio: Dio(BaseOptions(baseUrl: 'http://test.local/'))..httpClientAdapter = adapter,
              ),
            ),
            chatMessageCacheProvider.overrideWith((ref) => _NoopChatCache()),
            chatDraftStoreProvider.overrideWith((ref) => _NoopDraftStore()),
          ],
          child: MaterialApp(home: child),
        );

    await tester.pumpWidget(
      scope(
        Consumer(
          builder: (context, ref, _) {
            ref.watch(authNotifierProvider);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(scope(const ChatScreen(matchId: 'match-001')));
    await client.connect();
    socket.serverAuthOk(protocolVersion: 3);
    await tester.pumpAndSettle();

    await tester.tap(find.text('hello from partner'));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(find.text('hello from partner'));
    await tester.pumpAndSettle();

    expect(find.text('👍'), findsOneWidget);
  });
}
