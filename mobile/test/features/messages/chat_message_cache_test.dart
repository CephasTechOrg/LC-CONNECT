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
}
