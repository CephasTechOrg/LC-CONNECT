import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../auth/providers/auth_provider.dart';

// ── Message partner (subset of ProfilePublic) ─────────────────────
class MessagePartner {
  final String profileId;
  final String userId;
  final String? displayName;
  final String? avatarUrl;
  final String? major;
  final int? classYear;
  final List<String> interests;
  final List<String> lookingFor;
  final List<String> languagesSpoken;
  final List<String> languagesLearning;

  const MessagePartner({
    required this.profileId,
    required this.userId,
    this.displayName,
    this.avatarUrl,
    this.major,
    this.classYear,
    required this.interests,
    required this.lookingFor,
    required this.languagesSpoken,
    required this.languagesLearning,
  });

  factory MessagePartner.fromJson(Map<String, dynamic> j) => MessagePartner(
        profileId: j['id'] as String,
        userId: j['user_id'] as String,
        displayName: j['display_name'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        major: j['major'] as String?,
        classYear: j['class_year'] as int?,
        interests: List<String>.from(j['interests'] ?? []),
        lookingFor: List<String>.from(j['looking_for'] ?? []),
        languagesSpoken: List<String>.from(j['languages_spoken'] ?? []),
        languagesLearning: List<String>.from(j['languages_learning'] ?? []),
      );
}

// ── Chat message ──────────────────────────────────────────────────
class ChatMessage {
  final String id;
  final String matchId;
  final String senderId;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  const ChatMessage({
    required this.id,
    required this.matchId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.readAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        matchId: j['match_id'] as String,
        senderId: j['sender_id'] as String,
        body: j['body'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        readAt: j['read_at'] != null
            ? DateTime.parse(j['read_at'] as String)
            : null,
      );
}

// ── Message thread ────────────────────────────────────────────────
class MessageThread {
  final String matchId;
  final MessagePartner partner;
  final ChatMessage? latestMessage;

  const MessageThread({
    required this.matchId,
    required this.partner,
    this.latestMessage,
  });

  factory MessageThread.fromJson(Map<String, dynamic> j) => MessageThread(
        matchId: j['match_id'] as String,
        partner:
            MessagePartner.fromJson(j['partner'] as Map<String, dynamic>),
        latestMessage: j['latest_message'] != null
            ? ChatMessage.fromJson(
                j['latest_message'] as Map<String, dynamic>)
            : null,
      );
}

// ── Thread list provider ──────────────────────────────────────────
final threadsNotifierProvider =
    AsyncNotifierProvider<ThreadsNotifier, List<MessageThread>>(
        ThreadsNotifier.new);

class ThreadsNotifier extends AsyncNotifier<List<MessageThread>> {
  @override
  Future<List<MessageThread>> build() async {
    ref.watch(authNotifierProvider);
    final client = ref.watch(apiClientProvider);
    final response = await client.dio.get('/messages/threads');
    return (response.data as List)
        .map((j) => MessageThread.fromJson(j as Map<String, dynamic>))
        .toList();
  }
}
