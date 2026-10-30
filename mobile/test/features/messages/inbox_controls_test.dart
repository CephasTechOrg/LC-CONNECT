import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/api/api_client.dart';
import 'package:lc_connect/core/realtime/realtime_client.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/messages/data/thread_order.dart';
import 'package:lc_connect/features/messages/providers/inbox_drafts_provider.dart';
import 'package:lc_connect/features/messages/providers/messages_provider.dart';
import 'package:lc_connect/features/messages/screens/chat_screen.dart';
import 'package:lc_connect/features/messages/screens/messages_screen.dart';

class _Empty implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async =>
      ResponseBody.fromString('[]', 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

  @override
  void close({bool force = false}) {}
}

class _Threads extends ThreadsNotifier {
  _Threads(this._fixed);
  final List<MessageThread> _fixed;

  @override
  Future<List<MessageThread>> build() async => _fixed;
}

class _Auth extends AuthNotifier {
  @override
  Future<AuthUser?> build() async =>
      AuthUser(id: 'me', email: 'me@livingstone.edu', role: 'student', profileCompleted: true);
}

const _partner = MessagePartner(
  profileId: 'p1',
  userId: 'u1',
  displayName: 'Maya Chen',
  interests: [],
  lookingFor: [],
  languagesSpoken: [],
  languagesLearning: [],
);

MessageThread _t(String id, {DateTime? pinnedAt, bool archived = false, bool online = false}) => MessageThread(
      conversationId: 'c-$id',
      kind: 'dm',
      matchId: id,
      partner: _partner,
      pinnedAt: pinnedAt,
      archived: archived,
      partnerOnline: online,
      latestMessage: ChatMessage(id: 'm-$id', matchId: id, senderId: 'u1', body: 'hi $id', createdAt: DateTime(2026)),
    );

ChatMessage _m(String id, String sender) =>
    ChatMessage(id: id, matchId: 'x', senderId: sender, body: id, createdAt: DateTime(2026));

void main() {
  test('pinned chats lead, newest pin first; archived ones leave the main list', () {
    final arranged = arrangeInbox([
      _t('a'),
      _t('b', pinnedAt: DateTime(2026, 1, 1)),
      _t('c', archived: true),
      _t('d', pinnedAt: DateTime(2026, 2, 1)),
    ]);
    expect(arranged.main.map((t) => t.matchId), ['d', 'b', 'a']);
    expect(arranged.archived.map((t) => t.matchId), ['c']);
  });

  test('the "New messages" divider sits above the oldest unread message from others', () {
    final messages = [_m('1', 'u1'), _m('2', 'me'), _m('3', 'u1'), _m('4', 'u1')];
    expect(firstUnreadId(messages, mine: 'me', unread: 2), '3');
    expect(firstUnreadId(messages, mine: 'me', unread: 0), isNull);
    expect(firstUnreadId(messages, mine: 'me', unread: 9), '1', reason: 'older ones are not loaded yet');
  });

  testWidgets('the inbox shows drafts, online dots, pins and an Archived row', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        threadsNotifierProvider.overrideWith(() => _Threads([
              _t('a', online: true),
              _t('b', pinnedAt: DateTime(2026)),
              _t('c', archived: true),
            ])),
        authNotifierProvider.overrideWith(_Auth.new),
        inboxDraftsProvider.overrideWith((ref) async => {'a': 'see you at five'}),
        realtimeClientProvider.overrideWith((ref) {
          final client = RealtimeClient(url: Uri.parse('ws://localhost/ws'), tokenProvider: () async => null);
          ref.onDispose(client.dispose);
          return client;
        }),
        apiClientProvider.overrideWith(
          (ref) => ApiClient(dio: Dio(BaseOptions(baseUrl: 'http://t/'))..httpClientAdapter = _Empty()),
        ),
      ],
      child: const MaterialApp(home: MessagesScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Draft:', findRichText: true), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Online')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Pinned')), findsOneWidget);
    expect(find.text('Archived'), findsOneWidget);
    expect(find.text('hi c'), findsNothing, reason: 'archived chats are behind the Archived row');
    semantics.dispose();
  });
}
