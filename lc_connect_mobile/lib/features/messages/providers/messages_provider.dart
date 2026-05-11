import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  final MessagePartner? partner;
  final ChatMessage? latestMessage;

  const MessageThread({
    required this.matchId,
    this.partner,
    this.latestMessage,
  });

  factory MessageThread.fromJson(Map<String, dynamic> j) => MessageThread(
        matchId: j['match_id'] as String,
        partner: j['partner'] != null
            ? MessagePartner.fromJson(j['partner'] as Map<String, dynamic>)
            : null,
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
  RealtimeChannel? _channel;

  @override
  Future<List<MessageThread>> build() async {
    ref.watch(authNotifierProvider);
    final client = ref.watch(apiClientProvider);
    final response = await client.dio.get('/messages/threads');
    final threads = (response.data as List)
        .map((j) => MessageThread.fromJson(j as Map<String, dynamic>))
        .where((t) => t.partner != null)
        .toList();

    _subscribeToNewMessages();
    ref.onDispose(() {
      _channel?.unsubscribe();
      _channel = null;
    });

    return threads;
  }

  void _subscribeToNewMessages() {
    _channel?.unsubscribe();
    _channel = null;
    try {
      _channel = Supabase.instance.client
          .channel('thread_list_messages')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            callback: (payload) => _onNewMessage(payload.newRecord),
          )
          .subscribe();
    } catch (_) {}
  }

  void _onNewMessage(Map<String, dynamic> record) {
    final current = state.asData?.value;
    if (current == null) return;

    final msg = ChatMessage.fromJson(record);
    final idx = current.indexWhere((t) => t.matchId == msg.matchId);
    if (idx == -1) return;

    final updated = List<MessageThread>.from(current);
    updated[idx] = MessageThread(
      matchId: current[idx].matchId,
      partner: current[idx].partner,
      latestMessage: msg,
    );
    updated.sort((a, b) {
      final aTime = a.latestMessage?.createdAt;
      final bTime = b.latestMessage?.createdAt;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    state = AsyncData(updated);
  }
}
