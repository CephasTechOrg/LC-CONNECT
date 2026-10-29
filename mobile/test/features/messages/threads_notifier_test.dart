import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/core/api/api_client.dart';
import 'package:lc_connect/core/realtime/realtime_client.dart';
import 'package:lc_connect/core/realtime/ws_protocol.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/messages/providers/messages_provider.dart';

class _MockAuth extends AuthNotifier {
  @override
  Future<AuthUser?> build() async =>
      AuthUser(id: 'me', email: 'me@livingstone.edu', role: 'student', profileCompleted: true);
}

/// A protocol-5 server, so the inbox takes the state frames.
class _FakeRealtime extends RealtimeClient {
  final _ev = StreamController<InboundEvent>.broadcast();
  _FakeRealtime() : super(url: Uri.parse('ws://test'), tokenProvider: () async => null);

  @override
  Stream<InboundEvent> get events => _ev.stream;
  @override
  bool supportsProtocol(int version) => version <= kProtocolVersion;

  void emit(InboundEvent e) => _ev.add(e);
}

class _Adapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> threads;
  final mutes = <String>[];
  bool failMute = false;
  bool failState = false;
  _Adapter(this.threads);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    const json = {Headers.contentTypeHeader: [Headers.jsonContentType]};
    if (o.path.endsWith('/messages/threads') && o.method == 'GET') {
      return ResponseBody.fromString(jsonEncode(threads), 200, headers: json);
    }
    if (o.path.endsWith('/state') && o.method == 'PATCH') {
      if (failState) return ResponseBody.fromString('{"detail":"You can pin up to 3 chats"}', 409, headers: json);
      return ResponseBody.fromString('{"pinned_at":null,"archived":false}', 200, headers: json);
    }
    if (o.path.endsWith('/mute') && o.method == 'PATCH') {
      if (failMute) return ResponseBody.fromString('{"detail":"nope"}', 500, headers: json);
      mutes.add(o.path);
      return ResponseBody.fromString('{"muted":true}', 200, headers: json);
    }
    return ResponseBody.fromString('{"detail":"unexpected"}', 500, headers: json);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _thread({String kind = 'dm', String? reactionActor}) => {
      'conversation_id': 'conv-1',
      'kind': kind,
      if (kind == 'dm') 'match_id': 'match-1',
      if (kind == 'dm')
        'partner': {'id': 'p1', 'user_id': 'them', 'display_name': 'Ama Mensah'}
      else
        'group': {'id': 'g1', 'name': 'Study group'},
      'latest_message': {
        'id': 'm1',
        'conversation_id': 'conv-1',
        'sender_id': 'me',
        'body': 'see you at 5',
        'created_at': '2026-10-01T12:00:00Z',
      },
      if (reactionActor != null)
        'latest_reaction': {
          'emoji': '👍',
          'actor_id': reactionActor,
          'message_id': 'm1',
          'message_sender_id': 'me',
          'message_snippet': 'see you at 5',
          'reacted_at': '2026-10-01T12:05:00Z',
        },
      'muted': false,
    };

ReactionEvent _reaction({
  String conversationId = 'match-1',
  String userId = 'them',
  String? userEmoji = '❤️',
  String senderId = 'me',
}) =>
    ReactionEvent('m1', userId, userEmoji ?? '👍', userEmoji != null,
        conversationId: conversationId,
        userEmoji: userEmoji,
        counts: const [],
        actorName: 'Ama Mensah',
        messageSenderId: senderId,
        messageSnippet: 'see you at 5',
        reactedAt: '2026-10-01T12:10:00Z');

Future<(ProviderContainer, _FakeRealtime, _Adapter)> _ready(List<Map<String, dynamic>> threads) async {
  final rt = _FakeRealtime();
  final adapter = _Adapter(threads);
  final c = ProviderContainer(overrides: [
    authNotifierProvider.overrideWith(_MockAuth.new),
    realtimeClientProvider.overrideWithValue(rt),
    apiClientProvider.overrideWith(
      (ref) => ApiClient(dio: Dio(BaseOptions(baseUrl: 'http://test.local/'))..httpClientAdapter = adapter),
    ),
  ]);
  addTearDown(c.dispose);
  await c.read(authNotifierProvider.future);
  c.listen(threadsNotifierProvider, (_, _) {}, fireImmediately: true);
  await c.read(threadsNotifierProvider.future);
  return (c, rt, adapter);
}

MessageThread _only(ProviderContainer c) => c.read(threadsNotifierProvider).value!.single;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a reaction frame becomes the row preview with who reacted and to what', () async {
    final (c, rt, _) = await _ready([_thread()]);
    rt.emit(_reaction());
    await pumpEventQueue();

    final r = _only(c).latestReaction!;
    expect((r.emoji, r.actorName, r.messageSnippet), ('❤️', 'Ama Mensah', 'see you at 5'));
  });

  test("in a group, a reaction between two other people stays off my row", () async {
    final (c, rt, _) = await _ready([_thread(kind: 'group')]);
    rt.emit(_reaction(conversationId: 'conv-1', userId: 'kofi', senderId: 'abena'));
    await pumpEventQueue();
    expect(_only(c).latestReaction, isNull);

    rt.emit(_reaction(conversationId: 'conv-1', userId: 'kofi', senderId: 'me'));
    await pumpEventQueue();
    expect(_only(c).latestReaction?.actorId, 'kofi');
  });

  test('editing or deleting the latest message updates the row live', () async {
    final (c, rt, _) = await _ready([_thread(reactionActor: 'them')]);
    rt.emit(const MessageEdited('match-1', 'm1', 'see you at 6', '2026-10-01T12:20:00Z'));
    await pumpEventQueue();
    expect(_only(c).latestMessage!.body, 'see you at 6');
    expect(_only(c).latestReaction!.messageSnippet, 'see you at 6');

    rt.emit(const MessageDeleted('match-1', 'm1'));
    await pumpEventQueue();
    expect(_only(c).latestMessage!.deleted, isTrue);
    expect(_only(c).latestReaction, isNull, reason: 'a reaction to a deleted message is not news');
  });

  test('mute is optimistic, synced from other devices, and rolled back on failure', () async {
    final (c, rt, adapter) = await _ready([_thread()]);
    final notifier = c.read(threadsNotifierProvider.notifier);

    await notifier.setMuted('match-1', true);
    expect(_only(c).muted, isTrue);
    expect(adapter.mutes, ['/messages/threads/match-1/mute']);

    rt.emit(const ConversationMuted('match-1', false));
    await pumpEventQueue();
    expect(_only(c).muted, isFalse);

    adapter.failMute = true;
    await expectLater(notifier.setMuted('match-1', true), throwsA(anything));
    expect(_only(c).muted, isFalse);
  });

  test('a connection coming online lights the dot on their chat', () async {
    final (c, rt, _) = await _ready([_thread()]);
    rt.emit(const PresenceEvent('them', online: true));
    await pumpEventQueue();
    expect(_only(c).partnerOnline, isTrue);

    rt.emit(const PresenceEvent('them', online: false, visible: false));
    await pumpEventQueue();
    expect(_only(c).partnerOnline, isFalse);
  });

  test('pins and archives made on another device arrive here', () async {
    final (c, rt, _) = await _ready([_thread()]);
    rt.emit(const ConversationState('match-1', pinnedAt: '2026-10-29T12:00:00Z', archived: false));
    await pumpEventQueue();
    expect(_only(c).pinned, isTrue);

    rt.emit(const ConversationState('match-1', archived: true));
    await pumpEventQueue();
    expect((_only(c).pinned, _only(c).archived), (false, true));
  });

  test('a refused pin (the fourth) is rolled back', () async {
    final (c, _, adapter) = await _ready([_thread()]);
    adapter.failState = true;
    await expectLater(c.read(threadsNotifierProvider.notifier).setPinned('match-1', true), throwsA(anything));
    expect(_only(c).pinned, isFalse);
  });
}
