import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../shared/util/caching.dart';

/// Someone who reacted to a message, and with what.
class MessageReactor {
  const MessageReactor({
    required this.userId,
    required this.emoji,
    this.displayName,
    this.avatarUrl,
  });

  final String userId;
  final String emoji;
  final String? displayName;
  final String? avatarUrl;

  factory MessageReactor.fromJson(Map<String, dynamic> j) => MessageReactor(
        userId: j['user_id'] as String,
        emoji: j['emoji'] as String,
        displayName: j['display_name'] as String?,
        avatarUrl: j['avatar_url'] as String?,
      );

  String get name => (displayName?.trim().isNotEmpty ?? false) ? displayName!.trim() : 'Member';
}

/// Who reacted to a message, newest first, including me (protocol 5).
///
/// Fetched when the "Reacted by" sheet opens, not with every page: almost nobody opens it, and a
/// page of messages would otherwise carry a list of people per reacted message. Briefly cached so
/// reopening is instant, and invalidated by the chat when a live reaction for this message lands.
final messageReactorsProvider =
    FutureProvider.autoDispose.family<List<MessageReactor>, String>((ref, messageId) async {
  cacheFor(ref, const Duration(seconds: 10));
  final response = await ref.read(apiClientProvider).dio.get('/messages/$messageId/reactions');
  return [
    for (final row in response.data as List)
      MessageReactor.fromJson(Map<String, dynamic>.from(row as Map)),
  ];
});
