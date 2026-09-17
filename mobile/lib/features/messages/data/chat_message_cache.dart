import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../providers/messages_provider.dart';

/// The on-disk format version written by this build.
///
/// Bump it only for a **breaking** change — one where a reader of an older version would
/// mis-parse rather than merely miss a field. Additive fields need no bump: [_fromCacheJson]
/// reads a missing key as its default, which is why the pre-envelope files still load.
const int chatCacheFormatVersion = 1;

/// Persists the tail of a conversation locally so reopening chat while offline
/// still shows recent history and any unsent/failed optimistic rows.
///
/// ## Format
///
/// ```jsonc
/// { "v": 1, "messages": [ … ] }
/// ```
///
/// Earlier builds wrote a bare JSON array with no version marker at all, which meant there was
/// no way to tell a file written by one build from a file written by another, and therefore no
/// way to ever make a breaking change to the row shape. Phase 3 adds fields to [ChatMessage]
/// (delivery state, and later `editedAt` and reactions), so the envelope goes in *before*
/// anything starts writing them.
///
/// The reader is deliberately forgiving in one direction only: a bare array is read as the
/// legacy format, an unknown row field is ignored, and a single unreadable row is skipped. A
/// file stamped with a **newer** version than this build understands is discarded unread —
/// which happens for real on a TestFlight rollback. Dropping the cache costs a network fetch;
/// mis-parsing it shows the user wrong messages, so the two failures are not comparable.
class ChatMessageCache {
  static const maxMessages = 150;

  final Future<Directory> Function() _rootDir;

  ChatMessageCache({Future<Directory> Function()? rootDir}) : _rootDir = rootDir ?? _defaultRootDir;

  static Future<Directory> _defaultRootDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory('${dir.path}/chat_cache');
  }

  /// The cached tail, or null when there is nothing usable on disk.
  ///
  /// Null covers every failure the same way — no file, unreadable file, or a file from a build
  /// this one cannot read — because the caller's response is identical in all three: fetch.
  Future<List<ChatMessage>?> load(String conversationId) async {
    try {
      final file = await _fileFor(conversationId);
      if (!await file.exists()) return null;
      final rows = _rowsOf(jsonDecode(await file.readAsString()));
      if (rows == null) return null;
      return _readRows(rows);
    } catch (_) {
      return null;
    }
  }

  /// The message rows inside a decoded cache file, or null if this build must not read it.
  static List<dynamic>? _rowsOf(dynamic decoded) {
    // Legacy: a bare array, written before the envelope existed. The row shape has not changed,
    // so it is still readable — and reading it means an upgrading user keeps their history
    // instead of staring at a spinner. The next save rewrites it with a version.
    if (decoded is List) return decoded;
    if (decoded is! Map<String, dynamic>) return null;

    final version = decoded['v'];
    // A map with no version is not something any build of this app wrote.
    if (version is! int) return null;
    // Written by a newer build: its rows may mean something different. Discard, do not guess.
    if (version > chatCacheFormatVersion) return null;

    final messages = decoded['messages'];
    return messages is List ? messages : null;
  }

  /// Parses rows, skipping any single row that will not read.
  ///
  /// One malformed row should cost that row, not the whole conversation tail — the failure mode
  /// before this was a `null` return that silently discarded up to [maxMessages] messages.
  static List<ChatMessage> _readRows(List<dynamic> rows) {
    final parsed = <ChatMessage>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      try {
        parsed.add(_fromCacheJson(row));
      } catch (_) {
        continue;
      }
    }
    return parsed;
  }

  Future<void> save(String conversationId, List<ChatMessage> messages) async {
    if (messages.isEmpty) return;
    try {
      final tail = messages.length > maxMessages
          ? messages.sublist(messages.length - maxMessages)
          : messages;
      final file = await _fileFor(conversationId);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'v': chatCacheFormatVersion,
        'messages': tail.map(_toCacheJson).toList(),
      }));
    } catch (_) {
      // Best effort — cache must never break chat.
    }
  }

  /// Removes every cached conversation. Called on logout and on account deletion.
  ///
  /// Cached message bodies are the other user's words as well as this user's, and the app runs on
  /// shared campus devices. Nothing cleared them before: signing out left a full conversation
  /// tail on disk for whoever signed in next.
  Future<void> clearAll() async {
    try {
      final dir = await _rootDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Best effort — a failed cleanup must not block signing out.
    }
  }

  Future<File> _fileFor(String conversationId) async {
    final cacheDir = await _rootDir();
    final safe = conversationId.replaceAll(RegExp(r'[^\w\-]'), '_');
    return File('${cacheDir.path}/$safe.json');
  }
}

Map<String, dynamic> _toCacheJson(ChatMessage m) => {
      'id': m.id,
      'match_id': m.matchId,
      'sender_id': m.senderId,
      'client_message_id': m.clientMessageId,
      'body': m.body,
      'created_at': m.createdAt.toUtc().toIso8601String(),
      'read_at': m.readAt?.toUtc().toIso8601String(),
      'delivered': m.delivered,
      'status': m.status.name,
      'deleted': m.deleted,
    };

ChatMessage _fromCacheJson(Map<String, dynamic> j) {
  return ChatMessage(
    id: j['id'] as String,
    matchId: j['match_id'] as String,
    senderId: j['sender_id'] as String,
    clientMessageId: j['client_message_id'] as String?,
    body: j['body'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    readAt: j['read_at'] != null ? DateTime.parse(j['read_at'] as String) : null,
    // Absent in files written before protocol 2 — an additive field, which is exactly the kind
    // the envelope's version does not need to change for.
    delivered: j['delivered'] as bool? ?? false,
    status: _statusOf(j['status']),
    deleted: j['deleted'] as bool? ?? false,
  );
}

/// A status name this build does not know reads as [MessageStatus.sent].
///
/// `MessageStatus.values.byName` throws on an unknown name, which would have discarded the whole
/// file. That is not hypothetical: Phase 3 adds `delivered`, so any rollback to a build without
/// it would meet a name it cannot resolve. `sent` is the safe reading — it understates the
/// message's progress without ever claiming it failed.
MessageStatus _statusOf(dynamic raw) {
  if (raw is! String) return MessageStatus.sent;
  for (final status in MessageStatus.values) {
    if (status.name == raw) return status;
  }
  return MessageStatus.sent;
}

final chatMessageCacheProvider = Provider<ChatMessageCache>((ref) => ChatMessageCache());
