import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/messages/data/chat_draft_store.dart';

/// Report #1 — "message drafts are not preserved".
///
/// Nothing persisted composer text at all: the controller was created in `initState`, cleared on
/// send, and disposed. Leaving the conversation, switching apps, or having the app reclaimed by
/// the OS all lost whatever was half-written.
void main() {
  late Directory tempDir;
  late ChatDraftStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chat_drafts_test_');
    store = ChatDraftStore(rootDir: () async => tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  File fileFor(String id) => File('${tempDir.path}/$id.json');

  group('round trip', () {
    test('a saved draft loads back', () async {
      await store.save('conv-1', 'half a thought');
      expect(await store.load('conv-1'), 'half a thought');
    });

    test('there is no draft before one is written', () async {
      expect(await store.load('conv-1'), isNull);
    });

    test('drafts are scoped per conversation', () async {
      await store.save('conv-1', 'for alice');
      await store.save('conv-2', 'for bob');

      expect(await store.load('conv-1'), 'for alice');
      expect(await store.load('conv-2'), 'for bob');
    });

    test('saving again replaces the previous draft', () async {
      await store.save('conv-1', 'first');
      await store.save('conv-1', 'second');
      expect(await store.load('conv-1'), 'second');
    });

    test('leading and trailing whitespace is preserved', () async {
      // The draft is resumed mid-composition: trimming it would move the user's cursor context
      // and eat a deliberate trailing space between words.
      await store.save('conv-1', 'a sentence ending in a space ');
      expect(await store.load('conv-1'), 'a sentence ending in a space ');
    });

    test('a conversation id with path characters cannot escape the directory', () async {
      await store.save('../../etc/passwd', 'nope');
      final written = await tempDir.list().toList();
      expect(written, hasLength(1));
      expect(written.single.path, startsWith(tempDir.path));
    });
  });

  group('clearing', () {
    test('delete removes one draft and leaves the others', () async {
      await store.save('conv-1', 'one');
      await store.save('conv-2', 'two');

      await store.delete('conv-1');

      expect(await store.load('conv-1'), isNull);
      expect(await store.load('conv-2'), 'two');
    });

    test('deleting a draft that does not exist is not an error', () async {
      await expectLater(store.delete('conv-absent'), completes);
    });

    test('saving blank text deletes the draft', () async {
      // A whitespace-only draft would restore a composer that looks empty but is not, and would
      // keep the file alive forever.
      await store.save('conv-1', 'something');
      await store.save('conv-1', '   \n ');

      expect(await store.load('conv-1'), isNull);
      expect(await fileFor('conv-1').exists(), isFalse);
    });

    test('clearAll removes every draft', () async {
      await store.save('conv-1', 'one');
      await store.save('conv-2', 'two');

      await store.clearAll();

      expect(await store.load('conv-1'), isNull);
      expect(await store.load('conv-2'), isNull);
    });

    test('clearAll on an empty store is not an error', () async {
      await expectLater(store.clearAll(), completes);
    });
  });

  group('pruning', () {
    test('a draft older than the window is dropped', () async {
      // Otherwise a draft typed into an abandoned conversation resurfaces months later as a
      // message the user has no memory of composing.
      await fileFor('conv-old').writeAsString(jsonEncode({
        'v': chatDraftFormatVersion,
        'text': 'typed long ago',
        'updated_at': DateTime.now().toUtc().subtract(const Duration(days: 31)).toIso8601String(),
      }));

      await store.pruneStale();

      expect(await store.load('conv-old'), isNull);
    });

    test('a recent draft survives pruning', () async {
      await store.save('conv-new', 'typed just now');
      await store.pruneStale();
      expect(await store.load('conv-new'), 'typed just now');
    });

    test('a draft with no usable timestamp is dropped', () async {
      // There is no basis for keeping something whose age cannot be established.
      await fileFor('conv-x').writeAsString(jsonEncode({
        'v': chatDraftFormatVersion,
        'text': 'no timestamp',
      }));

      await store.pruneStale();

      expect(await store.load('conv-x'), isNull);
    });

    test('a corrupt file is pruned rather than left to fail forever', () async {
      await fileFor('conv-bad').writeAsString('{not json');
      await store.pruneStale();
      expect(await fileFor('conv-bad').exists(), isFalse);
    });
  });

  group('format and limits', () {
    test('a draft is written with a format version', () async {
      await store.save('conv-1', 'text');
      final decoded = jsonDecode(await fileFor('conv-1').readAsString()) as Map<String, dynamic>;
      expect(decoded['v'], chatDraftFormatVersion);
      expect(decoded['text'], 'text');
    });

    test('a draft from a newer build is ignored', () async {
      await fileFor('conv-1').writeAsString(jsonEncode({
        'v': chatDraftFormatVersion + 1,
        'text': 'written by a future build',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }));

      expect(await store.load('conv-1'), isNull);
    });

    test('a corrupt draft reads as no draft rather than throwing', () async {
      await fileFor('conv-1').writeAsString('{not json');
      expect(await store.load('conv-1'), isNull);
    });

    test('an oversized draft is truncated, not rejected', () async {
      // The server caps a body at 2000 characters, so a longer draft cannot be sent as one
      // message — but a user trimming an overrun must not have the overflow silently eaten when
      // they switch away and come back.
      await store.save('conv-1', 'x' * (maxDraftChars + 500));
      expect((await store.load('conv-1'))!.length, maxDraftChars);
    });
  });
}
