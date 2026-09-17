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

/// Report #1 through the actual composer, because the part that was missing was never the file
/// I/O — it was that nothing called it. The I/O itself is covered by `chat_draft_store_test.dart`.
///
/// The store is an in-memory double here for a hard reason, not convenience: `testWidgets` runs
/// inside a fake-async zone, and a real `dart:io` future never completes there — the first
/// version of this file hung on its first `await store.load(...)`. Everything the widget is
/// responsible for (the debounce, the flush on teardown, clearing on send, seeding the field
/// without clobbering live typing) is observable through a double, and observable
/// deterministically.
class _EmptyGetAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? _) async =>
      ResponseBody.fromString(
        o.method == 'POST'
            ? jsonEncode({
                'id': 'server-1',
                'match_id': 'match-001',
                'sender_id': 'current-user-id',
                'client_message_id': null,
                'body': 'sent',
                'created_at': '2026-01-01T00:00:00.000Z',
                'read_at': null,
              })
            : '[]',
        o.method == 'POST' ? 201 : 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );

  @override
  void close({bool force = false}) {}
}

/// Records calls and answers synchronously, so the fake clock governs the timing under test
/// rather than the disk.
class _InMemoryDraftStore extends ChatDraftStore {
  final Map<String, String> drafts = {};
  int saves = 0;

  @override
  Future<String?> load(String conversationId) async => drafts[conversationId];

  @override
  Future<void> save(String conversationId, String text) async {
    saves++;
    if (text.trim().isEmpty) {
      drafts.remove(conversationId);
      return;
    }
    drafts[conversationId] = text;
  }

  @override
  Future<void> delete(String conversationId) async => drafts.remove(conversationId);
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

void main() {
  late _InMemoryDraftStore store;

  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost:8000/api/v1\nENV=test');
  });

  setUp(() => store = _InMemoryDraftStore());

  /// [child] lets a test unmount the chat screen without tearing the scope down — Riverpod
  /// forbids changing the *number* of overrides across a rebuild, so replacing the whole
  /// ProviderScope is not an option.
  Widget chat({Widget child = const ChatScreen(matchId: 'match-001')}) => ProviderScope(
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
          apiClientProvider.overrideWith((ref) => ApiClient(
              dio: Dio(BaseOptions(baseUrl: 'http://test.local/'))
                ..httpClientAdapter = _EmptyGetAdapter())),
          chatMessageCacheProvider.overrideWith((ref) => _NoopChatCache()),
          chatDraftStoreProvider.overrideWith((ref) => store),
        ],
        child: MaterialApp(home: child),
      );

  Finder composer() => find.byType(TextField).last;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(chat());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('typing is saved after the debounce settles', (tester) async {
    await open(tester);
    await tester.enterText(composer(), 'half a thought');

    // Nothing is written yet: the debounce exists so typing is not one write per keystroke.
    expect(store.drafts['match-001'], isNull);

    await tester.pump(const Duration(milliseconds: 600));
    expect(store.drafts['match-001'], 'half a thought');
  });

  testWidgets('a saved draft is restored into the composer on re-entry', (tester) async {
    store.drafts['match-001'] = 'written earlier';
    await open(tester);
    // The load is async, so the field is seeded a frame or two in.
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.widget<TextField>(composer()).controller!.text, 'written earlier');
  });

  testWidgets('the cursor sits at the end of a restored draft', (tester) async {
    store.drafts['match-001'] = 'resume here';
    await open(tester);
    await tester.pump(const Duration(milliseconds: 50));

    // Resuming should continue the sentence, not insert at its start.
    final selection = tester.widget<TextField>(composer()).controller!.selection;
    expect(selection.baseOffset, 'resume here'.length);
  });

  testWidgets('leaving the screen flushes before the debounce fires', (tester) async {
    // The commonest way to lose a draft, and it happens well inside the 500ms window.
    await open(tester);
    await tester.enterText(composer(), 'typed then left');
    await tester.pump(const Duration(milliseconds: 100)); // mid-debounce

    await tester.pumpWidget(chat(child: const SizedBox()));
    await tester.pump();

    expect(store.drafts['match-001'], 'typed then left');
  });

  testWidgets('sending clears the draft', (tester) async {
    await open(tester);
    await tester.enterText(composer(), 'about to send');
    await tester.pump(const Duration(milliseconds: 600)); // draft persisted
    expect(store.drafts['match-001'], isNotNull);

    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // The text is in the message list now; keeping it as a draft too would restore it into the
    // composer beside the message the user can already see.
    expect(store.drafts['match-001'], isNull);
  });

  testWidgets('emptying the composer removes the draft', (tester) async {
    await open(tester);
    await tester.enterText(composer(), 'never mind');
    await tester.pump(const Duration(milliseconds: 600));
    expect(store.drafts['match-001'], isNotNull);

    await tester.enterText(composer(), '');
    await tester.pump(const Duration(milliseconds: 600));

    expect(store.drafts['match-001'], isNull);
  });

  testWidgets('a restored draft does not overwrite text the user is already typing',
      (tester) async {
    // The load is async. On a slow read the user may have started typing already, and seeding
    // the field then would replace what they just wrote with something older.
    store.drafts['match-001'] = 'older text';
    await tester.pumpWidget(chat());
    await tester.enterText(composer(), 'typed immediately');
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.widget<TextField>(composer()).controller!.text, 'typed immediately');
  });
}
