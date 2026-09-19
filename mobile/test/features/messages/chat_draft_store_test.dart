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

  /// Design §9.8 — drafts moved off the backed-up path.
  ///
  /// They lived under `getApplicationDocumentsDirectory()`, which iOS includes in iCloud backups
  /// and Android in auto-backup. Unsent draft text is the most private content in the feature and
  /// it was leaving the device. The migration matters as much as the move: without it a user
  /// mid-message loses it on update, *and* the old files stay behind still being backed up.
  group('migration off the backup path', () {
    late Directory legacyDir;
    late ChatDraftStore migrating;

    setUp(() async {
      legacyDir = await Directory.systemTemp.createTemp('chat_drafts_legacy_');
      migrating = ChatDraftStore(
        rootDir: () async => tempDir,
        legacyRootDir: () async => legacyDir,
      );
    });

    tearDown(() async {
      if (await legacyDir.exists()) await legacyDir.delete(recursive: true);
    });

    Future<void> writeLegacy(String id, String text) async {
      await File('${legacyDir.path}/$id.json').writeAsString(jsonEncode({
        'v': chatDraftFormatVersion,
        'text': text,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }));
    }

    test('an old draft is carried over', () async {
      await writeLegacy('conv-1', 'written before the update');

      await migrating.migrateOffBackupPath();

      expect(await migrating.load('conv-1'), 'written before the update');
    });

    test('the old directory is removed, so nothing keeps being backed up', () async {
      await writeLegacy('conv-1', 'old');

      await migrating.migrateOffBackupPath();

      expect(await legacyDir.exists(), isFalse);
    });

    test('a draft written since the update wins', () async {
      // The new location is newer by definition — the user has typed since upgrading.
      await writeLegacy('conv-1', 'stale');
      await migrating.save('conv-1', 'current');

      await migrating.migrateOffBackupPath();

      expect(await migrating.load('conv-1'), 'current');
    });

    test('running it twice is harmless', () async {
      await writeLegacy('conv-1', 'old');
      await migrating.migrateOffBackupPath();
      await migrating.migrateOffBackupPath();

      expect(await migrating.load('conv-1'), 'old');
    });

    test('nothing to migrate is not an error', () async {
      await legacyDir.delete(recursive: true);
      await expectLater(migrating.migrateOffBackupPath(), completes);
    });
  });

  group('the teardown is wired to every sign-out, not just the button', () {
    // `clearAll` above proves the wipe works; this proves it is reached. Most sign-outs are not
    // the user pressing Log out — the Dio interceptor signs out when a refresh token is finally
    // rejected, and bootstrap signs out when the account is gone. Those paths bypassed `logout`
    // entirely and left cached bodies and unsent drafts on disk for the next person to sign in,
    // which on a shared campus device is the whole risk this store carries.
    //
    // Asserted against the source because the real listener needs a live GoTrue client that no
    // widget test has. It is a coarse check, but it fails if the call is removed, which is the
    // regression worth catching.
    final source =
        File('lib/features/auth/providers/auth_provider.dart').readAsStringSync();

    test('the signedOut event clears local chat data', () {
      final signedOut = source.indexOf('AuthChangeEvent.signedOut');
      expect(signedOut, greaterThan(-1), reason: 'the signedOut branch is gone');
      final branch = source.substring(signedOut, signedOut + 900);
      expect(branch, contains('_clearLocalChatData()'));
    });

    test('logout still clears it on the deterministic path', () {
      expect(source, contains('await _clearLocalChatData();'));
    });

    test('the teardown covers both stores', () {
      expect(source, contains('chatDraftStoreProvider).clearAll()'));
      expect(source, contains('chatMessageCacheProvider).clearAll()'));
    });
  });
}
