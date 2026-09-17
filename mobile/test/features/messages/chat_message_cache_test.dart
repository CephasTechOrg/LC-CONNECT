import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/messages/data/chat_message_cache.dart';
import 'package:lc_connect/features/messages/providers/messages_provider.dart';

void main() {
  late Directory tempDir;
  late ChatMessageCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chat_cache_test_');
    cache = ChatMessageCache(rootDir: () async => tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('round-trips messages including pending status', () async {
    final messages = [
      ChatMessage(
        id: 'local:abc',
        matchId: 'conv-1',
        senderId: 'me',
        clientMessageId: 'abc',
        body: 'queued offline',
        createdAt: DateTime.utc(2025, 5, 1, 10),
        status: MessageStatus.sending,
      ),
      ChatMessage(
        id: 'srv-1',
        matchId: 'conv-1',
        senderId: 'them',
        body: 'hello',
        createdAt: DateTime.utc(2025, 5, 1, 10, 1),
      ),
    ];

    await cache.save('conv-1', messages);
    final loaded = await cache.load('conv-1');

    expect(loaded, isNotNull);
    expect(loaded!.length, 2);
    expect(loaded.first.status, MessageStatus.sending);
    expect(loaded.last.body, 'hello');
  });

  test('keeps only the newest tail', () async {
    final many = List.generate(
      ChatMessageCache.maxMessages + 10,
      (i) => ChatMessage(
        id: 'm$i',
        matchId: 'conv-2',
        senderId: 'u',
        body: '$i',
        createdAt: DateTime.utc(2025, 1, 1).add(Duration(minutes: i)),
      ),
    );

    await cache.save('conv-2', many);
    final loaded = await cache.load('conv-2');

    expect(loaded, isNotNull);
    expect(loaded!.length, ChatMessageCache.maxMessages);
    expect(loaded.first.body, '10');
    expect(loaded.last.body, '${ChatMessageCache.maxMessages + 9}');
  });

  /// Phase 3 step 2 — the cache gained a format version.
  ///
  /// The point is not the envelope itself, it is being able to make a breaking change later.
  /// Reactions, `editedAt` and delivery state are all coming, and until now there was no way to
  /// tell which build wrote a file, so no way to know whether its rows meant what you assumed.
  /// See `docs/features/messaging/phase3_design.md` §0b.
  group('format version', () {
    File fileFor(String conversationId) => File('${tempDir.path}/$conversationId.json');

    ChatMessage message({String id = 'srv-1', String body = 'hello'}) => ChatMessage(
          id: id,
          matchId: 'conv-1',
          senderId: 'them',
          body: body,
          createdAt: DateTime.utc(2025, 5, 1, 10),
        );

    test('save writes a versioned envelope', () async {
      await cache.save('conv-1', [message()]);

      final decoded = jsonDecode(await fileFor('conv-1').readAsString()) as Map<String, dynamic>;
      expect(decoded['v'], chatCacheFormatVersion);
      expect(decoded['messages'], hasLength(1));
    });

    test('a legacy bare array still loads', () async {
      // What every build before this one wrote. The row shape is unchanged, so discarding it
      // would cost an upgrading user their history for no reason at all.
      await fileFor('conv-1').writeAsString(jsonEncode([
        {
          'id': 'srv-1',
          'match_id': 'conv-1',
          'sender_id': 'them',
          'body': 'from the old format',
          'created_at': '2025-05-01T10:00:00.000Z',
          'status': 'sent',
          'deleted': false,
        }
      ]));

      final loaded = await cache.load('conv-1');
      expect(loaded, hasLength(1));
      expect(loaded!.single.body, 'from the old format');
    });

    test('a legacy file is rewritten with a version on the next save', () async {
      await fileFor('conv-1').writeAsString(jsonEncode(<dynamic>[]));
      await cache.save('conv-1', [message()]);

      final decoded = jsonDecode(await fileFor('conv-1').readAsString());
      expect(decoded, isA<Map<String, dynamic>>());
      expect((decoded as Map<String, dynamic>)['v'], chatCacheFormatVersion);
    });

    test('a file from a newer build is discarded unread', () async {
      // Real scenario: a TestFlight rollback. The newer build's rows may mean something this
      // one would misread, and showing the user wrong messages is worse than showing none.
      await fileFor('conv-1').writeAsString(jsonEncode({
        'v': chatCacheFormatVersion + 1,
        'messages': [
          {
            'id': 'srv-1',
            'match_id': 'conv-1',
            'sender_id': 'them',
            'body': 'written by a future build',
            'created_at': '2025-05-01T10:00:00.000Z',
          }
        ],
      }));

      expect(await cache.load('conv-1'), isNull);
    });

    test('an envelope with no version is discarded', () async {
      // No build of this app writes a map without `v`, so this is corruption or something else
      // entirely — not a format to guess at.
      await fileFor('conv-1').writeAsString(jsonEncode({'messages': <dynamic>[]}));
      expect(await cache.load('conv-1'), isNull);
    });

    test('a corrupt file is discarded rather than thrown', () async {
      await fileFor('conv-1').writeAsString('{not json');
      expect(await cache.load('conv-1'), isNull);
    });
  });

  /// The reader tolerates per-row damage. Before this, one bad row returned null and silently
  /// threw away the whole 150-message tail.
  group('tolerant reader', () {
    File fileFor(String conversationId) => File('${tempDir.path}/$conversationId.json');

    Map<String, dynamic> row(String id, {String? status}) => {
          'id': id,
          'match_id': 'conv-1',
          'sender_id': 'them',
          'body': 'body $id',
          'created_at': '2025-05-01T10:00:00.000Z',
          'status': ?status,
        };

    test('one unreadable row costs that row, not the conversation', () async {
      await fileFor('conv-1').writeAsString(jsonEncode({
        'v': chatCacheFormatVersion,
        'messages': [
          row('a'),
          {'id': 'b'}, // missing every required field
          row('c'),
        ],
      }));

      final loaded = await cache.load('conv-1');
      expect(loaded!.map((m) => m.id), ['a', 'c']);
    });

    test('an unknown status name reads as sent, keeping the message', () async {
      // Phase 3 adds `delivered`; a rollback to a build without it meets a name it cannot
      // resolve. `byName` used to throw here, discarding the file. `sent` understates the
      // message's progress without ever claiming it failed.
      await fileFor('conv-1').writeAsString(jsonEncode({
        'v': chatCacheFormatVersion,
        'messages': [row('a', status: 'delivered')],
      }));

      final loaded = await cache.load('conv-1');
      expect(loaded, hasLength(1));
      expect(loaded!.single.status, MessageStatus.sent);
    });

    test('a known status name is still honoured', () async {
      // The fallback must not flatten the states that do matter — a failed send has to stay
      // failed, or the user loses the Retry affordance.
      await fileFor('conv-1').writeAsString(jsonEncode({
        'v': chatCacheFormatVersion,
        'messages': [row('a', status: 'failed')],
      }));

      expect((await cache.load('conv-1'))!.single.status, MessageStatus.failed);
    });

    test('a missing status reads as sent', () async {
      await fileFor('conv-1').writeAsString(jsonEncode({
        'v': chatCacheFormatVersion,
        'messages': [row('a')],
      }));

      expect((await cache.load('conv-1'))!.single.status, MessageStatus.sent);
    });
  });


  /// The delivered flag has to survive the cache, or reopening a conversation offline drops
  /// every second tick back to one — which a sender reads as "it never arrived".
  group('delivery state round-trips', () {
    test('a delivered message stays delivered', () async {
      await cache.save('conv-1', [
        ChatMessage(
          id: 'srv-1',
          matchId: 'conv-1',
          senderId: 'me',
          body: 'hello',
          createdAt: DateTime.utc(2025, 5, 1, 10),
          delivered: true,
        ),
      ]);

      expect((await cache.load('conv-1'))!.single.delivered, isTrue);
    });

    test('a file written before the flag existed reads as not delivered', () async {
      // Understating progress is a missing tick; overstating it is a false claim about someone
      // else's device.
      await File('${tempDir.path}/conv-1.json').writeAsString(jsonEncode({
        'v': chatCacheFormatVersion,
        'messages': [
          {
            'id': 'srv-1',
            'match_id': 'conv-1',
            'sender_id': 'me',
            'body': 'hello',
            'created_at': '2025-05-01T10:00:00.000Z',
          }
        ],
      }));

      expect((await cache.load('conv-1'))!.single.delivered, isFalse);
    });
  });
}
