import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// The on-disk format version for a draft, for the reasons given in [ChatMessageCache].
const int chatDraftFormatVersion = 1;

/// The longest draft kept.
///
/// The server caps a message body at 2000 characters (`MAX_BODY_CHARS`), so a draft beyond that
/// can never be sent as one message. A little headroom above the cap is deliberate: a user who
/// has overrun the limit and needs to trim their text must not have the overflow silently eaten
/// when they switch away and come back.
const int maxDraftChars = 4000;

/// Unsent composer text, kept per conversation across leaving the screen, backgrounding, and
/// app restart (report #1).
///
/// Mirrors [ChatMessageCache] deliberately — `path_provider`, one JSON file per conversation
/// under `<appDocs>/chat_drafts/`, every failure swallowed — because a draft store that can
/// break the chat screen is worse than no draft store.
///
/// ## Why a file and not provider state
///
/// A Riverpod provider keyed by conversation would survive leaving the screen but not process
/// death, which is precisely the case users notice: the OS reclaims the app while they check
/// something else, and the half-written message is gone.
///
/// ## What is deliberately not here
///
/// Cross-device sync. Keeping a draft in step across devices means a server round trip per
/// keystroke, for a feature whose whole value is being instant and local.
class ChatDraftStore {
  ChatDraftStore({Future<Directory> Function()? rootDir}) : _rootDir = rootDir ?? _defaultRootDir;

  final Future<Directory> Function() _rootDir;

  static Future<Directory> _defaultRootDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory('${dir.path}/chat_drafts');
  }

  /// The saved draft for [conversationId], or null when there is none.
  ///
  /// Null for every failure alike — absent, unreadable, or written by a build this one cannot
  /// read — because the caller does the same thing in all three cases: start with an empty
  /// composer.
  Future<String?> load(String conversationId) async {
    try {
      final file = await _fileFor(conversationId);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final version = decoded['v'];
      if (version is! int || version > chatDraftFormatVersion) return null;
      final text = decoded['text'];
      if (text is! String || text.trim().isEmpty) return null;
      return text;
    } catch (_) {
      return null;
    }
  }

  /// Persists [text], or deletes the draft when it holds nothing but whitespace.
  ///
  /// Saving blank text as a draft would restore a composer that *looks* empty but is not, and
  /// would keep the conversation's file alive forever.
  Future<void> save(String conversationId, String text) async {
    if (text.trim().isEmpty) return delete(conversationId);
    try {
      final file = await _fileFor(conversationId);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'v': chatDraftFormatVersion,
        'text': text.length > maxDraftChars ? text.substring(0, maxDraftChars) : text,
        // Recorded in the file rather than read from the filesystem: an mtime does not reliably
        // survive a device migration or a backup restore, and [pruneStale] depends on it.
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }));
    } catch (_) {
      // Best effort — a draft must never break sending a message.
    }
  }

  /// Forgets the draft for one conversation. Called on a successful send.
  Future<void> delete(String conversationId) async {
    try {
      final file = await _fileFor(conversationId);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Nothing to recover: the draft is stale either way.
    }
  }

  /// Removes every draft. Called on logout and on account deletion.
  ///
  /// Unsent text is the most private thing in this feature — it was never shown to anyone — so
  /// it must not outlive the session that wrote it, least of all on a shared device.
  Future<void> clearAll() async {
    try {
      final dir = await _rootDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Best effort.
    }
  }

  /// Drops drafts untouched for longer than [olderThan].
  ///
  /// Without this, a draft typed into a conversation the user then abandons is kept forever, and
  /// resurfaces months later as a message they have no memory of composing.
  Future<void> pruneStale({Duration olderThan = const Duration(days: 30)}) async {
    try {
      final dir = await _rootDir();
      if (!await dir.exists()) return;
      final cutoff = DateTime.now().toUtc().subtract(olderThan);
      for (final entity in await dir.list().toList()) {
        if (entity is! File) continue;
        if (await _isStale(entity, cutoff)) await entity.delete();
      }
    } catch (_) {
      // Best effort.
    }
  }

  /// A draft is stale when its recorded timestamp is older than [cutoff] — and also when it has
  /// no readable timestamp at all, since there is then no basis for keeping it.
  Future<bool> _isStale(File file, DateTime cutoff) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return true;
      final updatedAt = DateTime.tryParse(decoded['updated_at'] as String? ?? '');
      if (updatedAt == null) return true;
      return updatedAt.toUtc().isBefore(cutoff);
    } catch (_) {
      return true;
    }
  }

  Future<File> _fileFor(String conversationId) async {
    final dir = await _rootDir();
    // Same sanitisation as the message cache: a conversation id reaches this as a path segment.
    final safe = conversationId.replaceAll(RegExp(r'[^\w\-]'), '_');
    return File('${dir.path}/$safe.json');
  }
}

final chatDraftStoreProvider = Provider<ChatDraftStore>((ref) => ChatDraftStore());

/// Runs [ChatDraftStore.pruneStale] once per app launch.
///
/// A provider rather than a call in `main` so it composes with the other startup side effects
/// the app root watches, and so a test can simply not watch it. Fire-and-forget on purpose:
/// nothing waits on housekeeping, and the store swallows its own failures.
final draftPruneProvider = Provider<void>((ref) {
  ref.read(chatDraftStoreProvider).pruneStale();
});
