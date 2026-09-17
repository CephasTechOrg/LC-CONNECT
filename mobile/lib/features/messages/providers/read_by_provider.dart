import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../shared/util/caching.dart';

/// One member who has read a message.
class MessageReader {
  const MessageReader({required this.userId, this.displayName, this.avatarUrl});

  final String userId;
  final String? displayName;
  final String? avatarUrl;

  factory MessageReader.fromJson(Map<String, dynamic> j) {
    final profile = j['profile'] as Map<String, dynamic>?;
    return MessageReader(
      userId: j['user_id'] as String,
      displayName: profile?['display_name'] as String?,
      avatarUrl: profile?['avatar_url'] as String?,
    );
  }

  /// Never empty, so a row always renders something: a member whose profile is missing or hidden
  /// still has to appear, or the count silently disagrees with the list.
  String get name => (displayName?.trim().isNotEmpty ?? false) ? displayName!.trim() : 'Member';
}

/// Who has read a given message (report #21).
///
/// A group bubble carries no delivered or read tick — that needs a rule for which members count
/// and every member's boundary held on the client. This is the affordance instead, opened from
/// the message's long-press sheet, and it says more than a tick could.
///
/// Fetched on demand rather than shipped with the message page: a 50-message page would need 50
/// member lists, almost none of which anyone ever looks at.
final messageReadByProvider =
    FutureProvider.autoDispose.family<List<MessageReader>, String>((ref, messageId) async {
  // Briefly cached so reopening the sheet does not refetch, but not held: who has read a message
  // changes on its own, and a stale list here reads as a claim about people.
  cacheFor(ref, const Duration(seconds: 30));
  final response =
      await ref.read(apiClientProvider).dio.get('/messages/$messageId/read-by');
  return [
    for (final row in response.data as List)
      MessageReader.fromJson(Map<String, dynamic>.from(row as Map)),
  ];
});
