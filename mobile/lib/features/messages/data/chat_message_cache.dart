import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../providers/messages_provider.dart';

/// Persists the tail of a conversation locally so reopening chat while offline
/// still shows recent history and any unsent/failed optimistic rows.
class ChatMessageCache {
  static const maxMessages = 150;

  final Future<Directory> Function() _rootDir;

  ChatMessageCache({Future<Directory> Function()? rootDir}) : _rootDir = rootDir ?? _defaultRootDir;

  static Future<Directory> _defaultRootDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory('${dir.path}/chat_cache');
  }

  Future<List<ChatMessage>?> load(String conversationId) async {
    try {
      final file = await _fileFor(conversationId);
      if (!await file.exists()) return null;
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      return raw.map((j) => _fromCacheJson(j as Map<String, dynamic>)).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String conversationId, List<ChatMessage> messages) async {
    if (messages.isEmpty) return;
    try {
      final tail = messages.length > maxMessages
          ? messages.sublist(messages.length - maxMessages)
          : messages;
      final file = await _fileFor(conversationId);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(tail.map(_toCacheJson).toList()));
    } catch (_) {
      // Best effort — cache must never break chat.
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
      'status': m.status.name,
      'deleted': m.deleted,
    };

ChatMessage _fromCacheJson(Map<String, dynamic> j) {
  final statusName = j['status'] as String?;
  return ChatMessage(
    id: j['id'] as String,
    matchId: j['match_id'] as String,
    senderId: j['sender_id'] as String,
    clientMessageId: j['client_message_id'] as String?,
    body: j['body'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    readAt: j['read_at'] != null ? DateTime.parse(j['read_at'] as String) : null,
    status: statusName == null
        ? MessageStatus.sent
        : MessageStatus.values.byName(statusName),
    deleted: j['deleted'] as bool? ?? false,
  );
}

final chatMessageCacheProvider = Provider<ChatMessageCache>((ref) => ChatMessageCache());
