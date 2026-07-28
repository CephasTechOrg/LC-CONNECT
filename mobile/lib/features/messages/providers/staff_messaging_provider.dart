import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../auth/providers/auth_provider.dart';
import 'messages_provider.dart';

/// A lightweight match for the "new message" composer — not a full profile.
class RecipientSearchResult {
  final String userId;
  final String? displayName;
  final String? avatarUrl;
  final String role;
  final String? positionTitle;
  final String? department;

  const RecipientSearchResult({
    required this.userId,
    this.displayName,
    this.avatarUrl,
    required this.role,
    this.positionTitle,
    this.department,
  });

  /// "Campus Safety Officer · Campus Security" for a staff result, else null.
  String? get subtitle {
    if (positionTitle == null && department == null) return null;
    return [positionTitle, department].whereType<String>().join(' · ');
  }

  factory RecipientSearchResult.fromJson(Map<String, dynamic> j) => RecipientSearchResult(
        userId: j['user_id'] as String,
        displayName: j['display_name'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        role: j['role'] as String,
        positionTitle: j['position_title'] as String?,
        department: j['department'] as String?,
      );
}

/// Whether this account can start a brand-new conversation with anyone (verified staff).
final canMessageAnyoneProvider = FutureProvider<bool>((ref) async {
  ref.watch(authNotifierProvider);
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/messages/capabilities');
  return response.data['can_message_anyone'] as bool? ?? false;
});

class StaffMessagingService {
  final ApiClient _client;
  StaffMessagingService(this._client);

  Future<List<RecipientSearchResult>> searchRecipients(String query) async {
    if (query.trim().isEmpty) return const [];
    final response = await _client.dio.get(
      '/messages/search-recipients',
      queryParameters: {'q': query.trim()},
    );
    return (response.data as List)
        .map((j) => RecipientSearchResult.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Get-or-create a conversation with `targetUserId`. No connection required as long as
  /// one side is a verified staff messenger.
  Future<MessageThread> startThread(String targetUserId) async {
    final response = await _client.dio.post(
      '/messages/staff-threads',
      data: {'target_user_id': targetUserId},
    );
    return MessageThread.fromJson(response.data as Map<String, dynamic>);
  }
}

final staffMessagingServiceProvider = Provider<StaffMessagingService>(
  (ref) => StaffMessagingService(ref.watch(apiClientProvider)),
);
