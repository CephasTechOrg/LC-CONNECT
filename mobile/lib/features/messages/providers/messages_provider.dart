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

/// Minimal sender identity for a group message bubble (name + avatar), resolved from the
/// group's members. Kept in the messages feature so bubbles don't depend on the groups models.
class MessageSender {
  final String name;
  final String? avatarUrl;
  const MessageSender({required this.name, this.avatarUrl});
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
  final bool deleted;

  const ChatMessage({
    required this.id,
    required this.matchId,
    required this.senderId,
    this.clientMessageId,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.status = MessageStatus.sent,
    this.deleted = false,
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
        deleted: j['deleted'] as bool? ?? false,
      );

  ChatMessage copyWith({String? id, DateTime? readAt, MessageStatus? status, bool? deleted}) => ChatMessage(
        id: id ?? this.id,
        matchId: matchId,
        senderId: senderId,
        clientMessageId: clientMessageId,
        body: body,
        createdAt: createdAt,
        readAt: readAt ?? this.readAt,
        status: status ?? this.status,
        deleted: deleted ?? this.deleted,
      );
}

// ── Message thread (DM or group) ──────────────────────────────────
class MessageThread {
  final String conversationId; // always present
  final String kind; // 'dm' | 'group'
  final String? matchId; // dm only
  final MessagePartner? partner; // dm only
  final String? groupId; // group only
  final String? groupName; // group only
  final String? groupAvatarUrl; // group only
  final ChatMessage? latestMessage;
  final bool partnerTyping; // transient (live), never from JSON

  const MessageThread({
    required this.conversationId,
    required this.kind,
    this.matchId,
    this.partner,
    this.groupId,
    this.groupName,
    this.groupAvatarUrl,
    this.latestMessage,
    this.partnerTyping = false,
  });

  bool get isGroup => kind == 'group';

  /// The id the client addresses this thread by everywhere (open/subscribe/unread/live-match):
  /// the match id for a DM, the conversation id for a group. Matches the server's frame ids.
  String get addressingId => matchId ?? conversationId;

  String get title => isGroup ? (groupName ?? 'Group') : (partner?.displayName ?? 'LC Student');
  String? get avatarUrl => isGroup ? groupAvatarUrl : partner?.avatarUrl;

  factory MessageThread.fromJson(Map<String, dynamic> j) {
    final group = j['group'] as Map<String, dynamic>?;
    return MessageThread(
      conversationId: j['conversation_id'] as String,
      kind: (j['kind'] as String?) ?? 'dm',
      matchId: j['match_id'] as String?,
      partner: j['partner'] != null
          ? MessagePartner.fromJson(j['partner'] as Map<String, dynamic>)
          : null,
      groupId: group?['id'] as String?,
      groupName: group?['name'] as String?,
      groupAvatarUrl: group?['avatar_url'] as String?,
      latestMessage: j['latest_message'] != null
          ? ChatMessage.fromJson(j['latest_message'] as Map<String, dynamic>)
          : null,
    );
  }

  MessageThread copyWith({ChatMessage? latestMessage, bool? partnerTyping}) => MessageThread(
        conversationId: conversationId,
        kind: kind,
        matchId: matchId,
        partner: partner,
        groupId: groupId,
        groupName: groupName,
        groupAvatarUrl: groupAvatarUrl,
        latestMessage: latestMessage ?? this.latestMessage,
        partnerTyping: partnerTyping ?? this.partnerTyping,
      );
}

// ── Thread list provider ──────────────────────────────────────────
final threadsNotifierProvider =
    AsyncNotifierProvider<ThreadsNotifier, List<MessageThread>>(
        ThreadsNotifier.new);

class ThreadsNotifier extends AsyncNotifier<List<MessageThread>> {
  StreamSubscription<InboundEvent>? _sub;
  final _typingTimers = <String, Timer>{};

  @override
  Future<List<MessageThread>> build() async {
    ref.watch(authNotifierProvider);
    final client = ref.watch(apiClientProvider);
    // Watching the client ensures the socket connects; user-channel
    // `conversation.updated` + `typing` events keep this list live.
    final realtime = ref.watch(realtimeClientProvider);
    _sub = realtime.events.listen((event) {
      if (event is ConversationUpdated) {
        _onConversationUpdated(event);
      } else if (event is TypingEvent) {
        _onTyping(event);
      }
    });
    ref.onDispose(() {
      _sub?.cancel();
      for (final t in _typingTimers.values) {
        t.cancel();
      }
    });

    final response = await client.dio.get('/messages/threads');
    return (response.data as List)
        .map((j) => MessageThread.fromJson(j as Map<String, dynamic>))
        .where((t) => t.isGroup || t.partner != null) // keep group + valid DM threads
        .toList();
  }

  void _onConversationUpdated(ConversationUpdated event) {
    final current = state.asData?.value;
    if (current == null) return;

    final idx = current.indexWhere((t) => t.addressingId == event.conversationId);
    if (idx == -1) return; // thread not loaded (e.g. brand-new match) — refreshed on return

    _typingTimers.remove(event.conversationId)?.cancel(); // a new message clears typing
    final msg = ChatMessage.fromJson(event.message);
    final updated = List<MessageThread>.from(current);
    updated[idx] = current[idx].copyWith(latestMessage: msg, partnerTyping: false);
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

  void _onTyping(TypingEvent event) {
    _setThreadTyping(event.conversationId, event.active);
    _typingTimers.remove(event.conversationId)?.cancel();
    if (event.active) {
      _typingTimers[event.conversationId] = Timer(
        const Duration(seconds: 4),
        () => _setThreadTyping(event.conversationId, false),
      );
    }
  }

  void _setThreadTyping(String conversationId, bool typing) {
    final current = state.asData?.value;
    if (current == null) return;
    final idx = current.indexWhere((t) => t.addressingId == conversationId);
    if (idx == -1 || current[idx].partnerTyping == typing) return;
    final updated = List<MessageThread>.from(current);
    updated[idx] = updated[idx].copyWith(partnerTyping: typing);
    state = AsyncData(updated);
  }
}
