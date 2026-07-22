import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/ws_protocol.dart';
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
enum MessageStatus { sending, sent, failed }

class ChatMessage {
  final String id;
  final String matchId;
  final String senderId;
  final String? clientMessageId;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;
  final MessageStatus status;

  const ChatMessage({
    required this.id,
    required this.matchId,
    required this.senderId,
    this.clientMessageId,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.status = MessageStatus.sent,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        matchId: (j['match_id'] ?? j['conversation_id']) as String,
        senderId: j['sender_id'] as String,
        clientMessageId: j['client_message_id'] as String?,
        body: j['body'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        readAt: j['read_at'] != null ? DateTime.parse(j['read_at'] as String) : null,
        status: MessageStatus.sent,
      );

  ChatMessage copyWith({String? id, DateTime? readAt, MessageStatus? status}) => ChatMessage(
        id: id ?? this.id,
        matchId: matchId,
        senderId: senderId,
        clientMessageId: clientMessageId,
        body: body,
        createdAt: createdAt,
        readAt: readAt ?? this.readAt,
        status: status ?? this.status,
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
  StreamSubscription<InboundEvent>? _sub;

  @override
  Future<List<MessageThread>> build() async {
    ref.watch(authNotifierProvider);
    final client = ref.watch(apiClientProvider);
    // Watching the client ensures the socket connects; user-channel
    // `conversation.updated` events keep this list live (no Supabase Realtime).
    final realtime = ref.watch(realtimeClientProvider);
    _sub = realtime.events.listen((event) {
      if (event is ConversationUpdated) _onConversationUpdated(event);
    });
    ref.onDispose(() => _sub?.cancel());

    final response = await client.dio.get('/messages/threads');
    return (response.data as List)
        .map((j) => MessageThread.fromJson(j as Map<String, dynamic>))
        .where((t) => t.partner != null)
        .toList();
  }

  void _onConversationUpdated(ConversationUpdated event) {
    final current = state.asData?.value;
    if (current == null) return;

    final idx = current.indexWhere((t) => t.matchId == event.conversationId);
    if (idx == -1) return; // thread not loaded (e.g. brand-new match) — refreshed on return

    final msg = ChatMessage.fromJson(event.message);
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
