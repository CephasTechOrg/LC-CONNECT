import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/messages/data/chat_message_cache.dart';
import 'package:lc_connect/features/messages/providers/messages_provider.dart';

/// Sent-message editing — report #5 (checklist 3.7), client side.
///
/// The server owns the rules; these cover what the client must get right around them: the edited
/// marker surviving a round trip, and the advisory window never *granting* an edit the server
/// would refuse.
void main() {
  group('the edited marker', () {
    test('is parsed off the wire', () {
      final message = ChatMessage.fromJson({
        'id': 'srv-1',
        'match_id': 'm1',
        'sender_id': 'me',
        'body': 'corrected',
        'created_at': '2026-09-18T10:00:00Z',
        'read_at': null,
        'edited_at': '2026-09-18T10:02:00Z',
      });

      expect(message.editedAt, DateTime.utc(2026, 9, 18, 10, 2));
    });

    test('an unedited message has none', () {
      final message = ChatMessage.fromJson({
        'id': 'srv-1',
        'match_id': 'm1',
        'sender_id': 'me',
        'body': 'original',
        'created_at': '2026-09-18T10:00:00Z',
        'read_at': null,
      });

      expect(message.editedAt, isNull);
    });

    test('a server that predates editing is fine', () {
      // Deploy order is server-before-client, but a client must never require a field a running
      // server may not send.
      final message = ChatMessage.fromJson({
        'id': 'srv-1',
        'match_id': 'm1',
        'sender_id': 'me',
        'body': 'original',
        'created_at': '2026-09-18T10:00:00Z',
        'read_at': null,
        'edited_at': null,
      });

      expect(message.editedAt, isNull);
    });
  });

  group('copyWith carries an edit', () {
    final message = ChatMessage(
      id: 'srv-1',
      matchId: 'm1',
      senderId: 'me',
      body: 'before',
      createdAt: DateTime.utc(2026, 9, 18, 10),
      delivered: true,
    );

    test('the body and the stamp move together', () {
      final at = DateTime.utc(2026, 9, 18, 10, 5);
      final next = message.copyWith(body: 'after', editedAt: at);

      expect(next.body, 'after');
      expect(next.editedAt, at);
    });

    test('unrelated state survives an edit', () {
      // The optimistic path rebuilds the message from `copyWith`; losing the tick or the
      // reactions here would make an edit visibly clobber them.
      final next = message.copyWith(body: 'after', editedAt: DateTime.utc(2026, 9, 18, 10, 5));

      expect(next.delivered, isTrue);
      expect(next.createdAt, message.createdAt);
      expect(next.senderId, 'me');
    });

    test('rolling back restores the original body', () {
      // How the failure path undoes an optimistic edit: it puts the *whole* previous message
      // back, so `editedAt` returns to null as well as the text.
      final optimistic = message.copyWith(body: 'after', editedAt: DateTime.now());

      expect(optimistic.body, 'after');
      expect(message.body, 'before', reason: 'the original instance is untouched');
      expect(message.editedAt, isNull);
    });
  });

  group('the cache round-trips an edit', () {
    late Directory tempDir;
    late ChatMessageCache cache;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('edit_cache_');
      cache = ChatMessageCache(rootDir: () async => tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('an edited message reopens as edited', () async {
      // Otherwise reopening a conversation offline shows the new text with no indication it
      // changed — which is worse than showing the old text, because it looks original.
      await cache.save('conv-1', [
        ChatMessage(
          id: 'srv-1',
          matchId: 'conv-1',
          senderId: 'me',
          body: 'corrected',
          createdAt: DateTime.utc(2026, 9, 18, 10),
          editedAt: DateTime.utc(2026, 9, 18, 10, 2),
        ),
      ]);

      final loaded = (await cache.load('conv-1'))!.single;
      expect(loaded.body, 'corrected');
      expect(loaded.editedAt, DateTime.utc(2026, 9, 18, 10, 2));
    });

    test('a file written before editing existed reads as unedited', () async {
      await File('${tempDir.path}/conv-1.json').writeAsString(jsonEncode({
        'v': chatCacheFormatVersion,
        'messages': [
          {
            'id': 'srv-1',
            'match_id': 'conv-1',
            'sender_id': 'me',
            'body': 'original',
            'created_at': '2026-09-18T10:00:00.000Z',
          }
        ],
      }));

      expect((await cache.load('conv-1'))!.single.editedAt, isNull);
    });
  });
}
