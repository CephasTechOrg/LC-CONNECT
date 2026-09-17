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
import 'package:lc_connect/features/messages/data/chat_draft_store.dart';
import 'package:lc_connect/features/messages/data/chat_message_cache.dart';
import 'package:lc_connect/features/messages/providers/messages_provider.dart';
import 'package:lc_connect/features/messages/providers/unread_provider.dart';
import 'package:lc_connect/features/messages/screens/chat_screen.dart';
import 'package:lc_connect/features/messages/widgets/message_status_icon.dart';

import '../../core/realtime/fake_socket.dart';

/// Read and delivery receipts are **boundaries**, and the chat screen used to ignore that: a
/// `messages.receipt` flipped *every* unread message of mine to read, whatever message the
/// receipt actually named.
///
/// That was invisible while there was one tick to flip — with a single read state, "all" and "up
/// to here" look identical the moment the partner is caught up, which they usually are. Delivered
/// makes it visible, and wrong in the worst direction: claiming someone read a message they have
/// not reached.
const _me = 'current-user-id';

/// Three messages from me, oldest first, already accepted by the server.
const _messageIds = ['srv-1', 'srv-2', 'srv-3'];

class _PageAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? _) async {
    if (o.method != 'GET') {
      return ResponseBody.fromString('{}', 200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    }
    return ResponseBody.fromString(
      jsonEncode([
        for (var i = 0; i < _messageIds.length; i++)
          {
            'id': _messageIds[i],
            'match_id': 'match-001',
            'sender_id': _me,
            'client_message_id': null,
            'body': 'message $i',
            'created_at': '2026-01-01T10:0$i:00.000Z',
            'read_at': null,
          },
      ]),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
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

  late FakeWsChannel socket;
  late RealtimeClient client;

  /// A chat over a socket the test drives, authenticated at protocol 2.
  ///
  /// Auth is resolved *before* the chat mounts, which matters rather than being ceremony:
  /// `ChatScreen` captures `currentUserId` once in `initState`, so a chat that mounts while auth
  /// is still loading treats every message as someone else's and renders no tick at all. The app
  /// cannot reach a conversation unauthenticated, so this reproduces the real ordering.
  Future<void> openChat(WidgetTester tester) async {
    socket = FakeWsChannel();
    client = clientOn(socket);
    // Inline rather than hoisted: the list closes over `client`, which is created just above,
    // and both frames below must use the *same* set — Riverpod forbids changing the number of
    // overrides across a rebuild.
    Widget scope(Widget child) => ProviderScope(
          overrides: [

        authNotifierProvider.overrideWith(_MockAuthNotifier.new),
        unreadProvider.overrideWith(_MockUnreadNotifier.new),
        realtimeClientProvider.overrideWith((ref) {
          ref.onDispose(client.dispose);
          return client;
        }),
        apiClientProvider.overrideWith((ref) => ApiClient(
            dio: Dio(BaseOptions(baseUrl: 'http://test.local/'))
              ..httpClientAdapter = _PageAdapter())),
        chatMessageCacheProvider.overrideWith((ref) => _NoopChatCache()),
        chatDraftStoreProvider.overrideWith((ref) => _NoopDraftStore()),
          ],
          child: MaterialApp(home: child),
        );

    // Warm-up frame: something has to watch the provider for it to start resolving.
    await tester.pumpWidget(scope(Consumer(
      builder: (context, ref, _) {
        ref.watch(authNotifierProvider);
        return const SizedBox();
      },
    )));
    await tester.pumpAndSettle();

    await tester.pumpWidget(scope(const ChatScreen(matchId: 'match-001')));
    await client.connect();
    socket.serverAuthOk(protocolVersion: 2);
    await tester.pumpAndSettle();
  }


  /// The tick state of each of my three messages, oldest first.
  List<OutgoingState> ticks(WidgetTester tester) => tester
      .widgetList<MessageStatusIcon>(find.byType(MessageStatusIcon))
      .map((icon) => OutgoingState.of(icon.message))
      .toList();

  void serverSays(String type, String throughMessageId, String stampField) =>
      socket.serverSends({
        'type': type,
        'conversation_id': 'match-001',
        'user_id': 'them',
        'through_message_id': throughMessageId,
        stampField: '2026-01-01T11:00:00.000Z',
      });

  testWidgets('all three of my messages start as sent', (tester) async {
    await openChat(tester);
    expect(ticks(tester), [OutgoingState.sent, OutgoingState.sent, OutgoingState.sent]);
  });

  testWidgets('a delivery receipt advances only up to its boundary', (tester) async {
    await openChat(tester);

    serverSays('messages.delivery', 'srv-2', 'delivered_at');
    await tester.pumpAndSettle();

    // The third message is past the boundary and must stay at one tick.
    expect(ticks(tester),
        [OutgoingState.delivered, OutgoingState.delivered, OutgoingState.sent]);
  });

  testWidgets('a read receipt advances only up to its boundary', (tester) async {
    await openChat(tester);

    serverSays('messages.receipt', 'srv-1', 'read_at');
    await tester.pumpAndSettle();

    // This is the case the old code got wrong: it marked all three read.
    expect(ticks(tester), [OutgoingState.read, OutgoingState.sent, OutgoingState.sent]);
  });

  testWidgets('reading implies delivery for everything up to the boundary', (tester) async {
    await openChat(tester);

    // A partner who opens the chat without this client ever having seen a delivery frame — the
    // ordinary case on a busy connection. Nothing may be left claiming "sent" behind a read one.
    serverSays('messages.receipt', 'srv-3', 'read_at');
    await tester.pumpAndSettle();

    expect(ticks(tester), [OutgoingState.read, OutgoingState.read, OutgoingState.read]);
  });

  testWidgets('a read receipt does not regress an already-read message', (tester) async {
    await openChat(tester);

    serverSays('messages.receipt', 'srv-3', 'read_at');
    await tester.pumpAndSettle();
    // Re-sent after a reconnect, naming an older boundary — the normal case, since the socket is
    // torn down on every app background and the client re-sends what it last knew.
    serverSays('messages.receipt', 'srv-1', 'read_at');
    await tester.pumpAndSettle();

    expect(ticks(tester), [OutgoingState.read, OutgoingState.read, OutgoingState.read]);
  });

  testWidgets('a delivery receipt does not demote a read message', (tester) async {
    await openChat(tester);

    serverSays('messages.receipt', 'srv-3', 'read_at');
    await tester.pumpAndSettle();
    serverSays('messages.delivery', 'srv-3', 'delivered_at');
    await tester.pumpAndSettle();

    expect(ticks(tester), [OutgoingState.read, OutgoingState.read, OutgoingState.read]);
  });

  testWidgets('a receipt naming an unknown message changes nothing', (tester) async {
    await openChat(tester);

    // Paged out of this client's tail, or newer than it. Guessing would be worse than waiting for
    // the next page load, which carries the correct state.
    serverSays('messages.delivery', 'srv-absent', 'delivered_at');
    await tester.pumpAndSettle();

    expect(ticks(tester), [OutgoingState.sent, OutgoingState.sent, OutgoingState.sent]);
  });

  testWidgets('a receipt for another conversation is ignored', (tester) async {
    await openChat(tester);

    socket.serverSends({
      'type': 'messages.delivery',
      'conversation_id': 'some-other-conversation',
      'user_id': 'them',
      'through_message_id': 'srv-3',
      'delivered_at': '2026-01-01T11:00:00.000Z',
    });
    await tester.pumpAndSettle();

    expect(ticks(tester), [OutgoingState.sent, OutgoingState.sent, OutgoingState.sent]);
  });
}
