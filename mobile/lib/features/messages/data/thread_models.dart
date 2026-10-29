/// An inbox row: a DM, staff DM or group, with its latest message and reaction preview.
library;

import 'message_models.dart';

/// The newest reaction worth showing on an inbox row: any reaction in a DM, or one to or by me
/// in a group. Seeded from `GET /messages/threads` and kept live by the reaction frame.
/// [reactedAt] is compared against the thread's latest message, so a newer message still takes
/// the row — a reaction never reorders the inbox.
class ThreadReactionPreview {
  const ThreadReactionPreview({
    required this.emoji,
    required this.actorId,
    required this.reactedAt,
    this.actorName,
    this.messageId,
    this.messageSenderId,
    this.messageSnippet = '',
  });

  final String emoji;
  final String actorId;
  final String? actorName;
  final String? messageId;
  final DateTime reactedAt;

  /// Whose message was reacted to, so the row can say "your message" or quote someone else's.
  final String? messageSenderId;
  final String messageSnippet;

  factory ThreadReactionPreview.fromJson(Map<String, dynamic> j) => ThreadReactionPreview(
        emoji: j['emoji'] as String,
        actorId: j['actor_id'] as String,
        actorName: j['actor_name'] as String?,
        messageId: j['message_id'] as String?,
        reactedAt: DateTime.parse(j['reacted_at'] as String),
        messageSenderId: j['message_sender_id'] as String?,
        messageSnippet: j['message_snippet'] as String? ?? '',
      );

  ThreadReactionPreview copyWith({String? messageSnippet}) => ThreadReactionPreview(
        emoji: emoji,
        actorId: actorId,
        actorName: actorName,
        messageId: messageId,
        reactedAt: reactedAt,
        messageSenderId: messageSenderId,
        messageSnippet: messageSnippet ?? this.messageSnippet,
      );
}

// ── Message thread (DM, staff DM, or group) ────────────────────────
class MessageThread {
  final String conversationId; // always present
  final String kind; // 'dm' | 'staff_dm' | 'group'
  final String? matchId; // dm only
  final MessagePartner? partner; // dm / staff_dm only
  // Staff identity context for the partner (staff_dm; set when they hold a verified
  // campus position) — e.g. "Officer Jane Doe · Campus Security".
  final String? partnerPositionTitle;
  final String? partnerDepartment;
  final String? groupId; // group only
  final String? groupName; // group only
  final String? groupAvatarUrl; // group only
  final ChatMessage? latestMessage;
  // The most recent reaction to one of my messages here, if any. Seeded from REST, kept live by
  // `messages.reaction_activity`. Additive — it never changes thread ordering.
  final ThreadReactionPreview? latestReaction;
  // Whether I muted this chat (no message or reaction pushes). Synced across my devices.
  final bool muted;
  // My own arrangement, synced across my devices: pinned to the top (when), or archived.
  final DateTime? pinnedAt;
  final bool archived;
  // A DM partner who is online now and whom I may see (connections, reciprocal). Kept live by
  // `presence` frames.
  final bool partnerOnline;
  final bool partnerTyping; // transient (live), never from JSON

  const MessageThread({
    required this.conversationId,
    required this.kind,
    this.matchId,
    this.partner,
    this.partnerPositionTitle,
    this.partnerDepartment,
    this.groupId,
    this.groupName,
    this.groupAvatarUrl,
    this.latestMessage,
    this.latestReaction,
    this.muted = false,
    this.pinnedAt,
    this.archived = false,
    this.partnerOnline = false,
    this.partnerTyping = false,
  });

  bool get pinned => pinnedAt != null;

  bool get isGroup => kind == 'group';
  bool get isStaffThread => kind == 'staff_dm';

  /// The id the client addresses this thread by everywhere (open/subscribe/unread/live-match):
  /// the match id for a DM, the conversation id for a group or staff thread. Matches the
  /// server's frame ids.
  String get addressingId => matchId ?? conversationId;

  String get title => isGroup ? (groupName ?? 'Group') : (partner?.displayName ?? 'LC Student');
  String? get avatarUrl => isGroup ? groupAvatarUrl : partner?.avatarUrl;

  /// "Campus Safety Officer · Campus Security" — shown under the partner's name so a student
  /// knows who they're talking to, or null when there's nothing to show.
  String? get partnerSubtitle {
    if (partnerPositionTitle == null && partnerDepartment == null) return null;
    return [partnerPositionTitle, partnerDepartment].whereType<String>().join(' · ');
  }

  /// The line under the name in the chat header: a staff member's position, or a student's
  /// major and class year — so the chat says who you are talking to, as the inbox row does.
  String? get headerSubtitle {
    final staff = partnerSubtitle;
    if (staff != null) return staff;
    final p = partner;
    if (p == null) return null;
    final parts = [
      if (p.major != null && p.major!.trim().isNotEmpty) p.major!.trim(),
      if (p.classYear != null) 'Class of ${p.classYear}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  factory MessageThread.fromJson(Map<String, dynamic> j) {
    final group = j['group'] as Map<String, dynamic>?;
    return MessageThread(
      conversationId: j['conversation_id'] as String,
      kind: (j['kind'] as String?) ?? 'dm',
      matchId: j['match_id'] as String?,
      partner: j['partner'] != null
          ? MessagePartner.fromJson(j['partner'] as Map<String, dynamic>)
          : null,
      partnerPositionTitle: j['partner_position_title'] as String?,
      partnerDepartment: j['partner_department'] as String?,
      groupId: group?['id'] as String?,
      groupName: group?['name'] as String?,
      groupAvatarUrl: group?['avatar_url'] as String?,
      latestMessage: j['latest_message'] != null
          ? ChatMessage.fromJson(j['latest_message'] as Map<String, dynamic>)
          : null,
      latestReaction: j['latest_reaction'] != null
          ? ThreadReactionPreview.fromJson(j['latest_reaction'] as Map<String, dynamic>)
          : null,
      muted: j['muted'] as bool? ?? false,
      pinnedAt: j['pinned_at'] != null ? DateTime.parse(j['pinned_at'] as String) : null,
      archived: j['archived'] as bool? ?? false,
      partnerOnline: j['partner_online'] as bool? ?? false,
    );
  }

  MessageThread copyWith({
    ChatMessage? latestMessage,
    ThreadReactionPreview? latestReaction,
    bool clearLatestReaction = false,
    bool? muted,
    DateTime? pinnedAt,
    bool clearPinnedAt = false,
    bool? archived,
    bool? partnerOnline,
    bool? partnerTyping,
  }) =>
      MessageThread(
        conversationId: conversationId,
        kind: kind,
        matchId: matchId,
        partner: partner,
        partnerPositionTitle: partnerPositionTitle,
        partnerDepartment: partnerDepartment,
        groupId: groupId,
        groupName: groupName,
        groupAvatarUrl: groupAvatarUrl,
        latestMessage: latestMessage ?? this.latestMessage,
        latestReaction: clearLatestReaction ? null : (latestReaction ?? this.latestReaction),
        muted: muted ?? this.muted,
        pinnedAt: clearPinnedAt ? null : (pinnedAt ?? this.pinnedAt),
        archived: archived ?? this.archived,
        partnerOnline: partnerOnline ?? this.partnerOnline,
        partnerTyping: partnerTyping ?? this.partnerTyping,
      );
}
