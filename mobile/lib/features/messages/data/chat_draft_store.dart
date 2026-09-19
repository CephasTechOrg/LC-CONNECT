import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'message_limits.dart';

/// The on-disk format version for a draft, for the reasons given in [ChatMessageCache].
const int chatDraftFormatVersion = 1;

/// The longest draft kept.
///
/// Headroom above [kMaxMessageChars] is deliberate: a user who has pasted more than one message's
/// worth and needs to split or trim it must not have the overflow silently eaten when they switch
/// away and come back. The composer itself truncates at the sendable limit.
const int maxDraftChars = kMaxMessageChars * 2;

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
  ChatDraftStore({
    Future<Directory> Function()? rootDir,
    Future<Directory> Function()? legacyRootDir,
  })  : _rootDir = rootDir ?? _defaultRootDir,
        _legacyRoot = legacyRootDir ?? _legacyRootDir;

  final Future<Directory> Function() _rootDir;

  /// Injectable so the migration can be tested without touching the real documents directory.
  final Future<Directory> Function() _legacyRoot;

  /// The cache directory, **not** documents — a deliberate privacy trade (design §9.8).
  ///
  /// Drafts lived under `getApplicationDocumentsDirectory()`, which iOS includes in iCloud
  /// backups and Android in auto-backup. Unsent draft text is the most private content in this
  /// feature — it was never shown to anyone — and it was leaving the device.
  ///
  /// The cost of moving: the OS may purge this directory under storage pressure, so a draft can
  /// vanish without the user deleting it. Acceptable, and arguably already implied — the 30-day
  /// [pruneStale] window says these are transient by design. The message cache stays in documents:
  /// it is disposable by definition and predates this decision.
  static Future<Directory> _defaultRootDir() async {
    final dir = await getApplicationCacheDirectory();
    return Directory('${dir.path}/chat_drafts');
  }

  /// The old, backed-up location, kept only so [migrateOffBackupPath] can empty it.
  static Future<Directory> _legacyRootDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory('${dir.path}/chat_drafts');
  }

  /// Moves any drafts left in the old backed-up location, then removes it.
  ///
  /// Without this, a user mid-way through a message loses it on the update that moves the
  /// directory — and worse, the old files would stay in Documents and keep being backed up,
  /// which is the thing the move exists to stop. Runs once per launch and is a no-op afterwards.
  Future<void> migrateOffBackupPath() async {
    try {
      final legacy = await _legacyRoot();
      if (!await legacy.exists()) return;
      final destination = await _rootDir();
      await destination.create(recursive: true);
      for (final entity in await legacy.list().toList()) {
        if (entity is! File) continue;
        final moved = File('${destination.path}/${entity.uri.pathSegments.last}');
        // Only if the new location does not already have it: a draft written since the update is
        // newer than anything left behind.
        if (!await moved.exists()) {
          await entity.copy(moved.path);
        }
      }
      await legacy.delete(recursive: true);
    } catch (_) {
      // Best effort, like everything else here. A failed migration costs at most some old drafts
      // and must never stop the app starting.
    }
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
  final store = ref.read(chatDraftStoreProvider);
  // Migration first: it moves files the prune would otherwise judge by the wrong directory.
  store.migrateOffBackupPath().then((_) => store.pruneStale());
});
