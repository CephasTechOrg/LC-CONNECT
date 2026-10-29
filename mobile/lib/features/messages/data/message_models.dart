/// The chat message and the small types it is built from. Split out of `messages_provider.dart`
/// (re-exported there, so importers are unchanged) to keep that file about the thread list.
library;

// ── Message partner (subset of ProfilePublic) ─────────────────────
class MessagePartner {
  final String profileId;
  final String userId;
  final String? displayName;
  final String? avatarUrl;
  final String? major;
  final int? classYear;
  final bool campusVerified;
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
    this.campusVerified = false,
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
        campusVerified: j['campus_verified'] as bool? ?? false,
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
  final String? profileId; // for opening their profile from a group bubble
  const MessageSender({required this.name, this.avatarUrl, this.profileId});
}

// ── Chat message ──────────────────────────────────────────────────
enum MessageStatus { sending, sent, failed }

/// One emoji's tally on a message, from this viewer's point of view.
///
/// Aggregated server-side: a popular message would otherwise ship one row per reactor to render a
/// chip that says "12". [reactedByMe] arrives in the same payload, so the client never needs a
/// second request to know whether to fill the chip.
class ReactionSummary {
  const ReactionSummary({
    required this.emoji,
    required this.count,
    required this.reactedByMe,
  });

  final String emoji;
  final int count;
  final bool reactedByMe;

  factory ReactionSummary.fromJson(Map<String, dynamic> j) => ReactionSummary(
        emoji: j['emoji'] as String,
        count: (j['count'] as num?)?.toInt() ?? 0,
        reactedByMe: j['reacted_by_me'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() =>
      {'emoji': emoji, 'count': count, 'reacted_by_me': reactedByMe};

  /// The chip after this viewer toggles [emoji]. Returns null when the chip should disappear —
  /// the last reactor removing theirs.
  ReactionSummary? toggled() {
    if (reactedByMe) {
      return count <= 1
          ? null
          : ReactionSummary(emoji: emoji, count: count - 1, reactedByMe: false);
    }
    return ReactionSummary(emoji: emoji, count: count + 1, reactedByMe: true);
  }
}

/// The message a reply quotes, as the quote block shows it (protocol 5).
///
/// A snippet, not the whole message. [deleted] makes the quote say so instead of showing stale
/// text; [edited] marks that the excerpt is the message's current wording.
class ReplyPreview {
  const ReplyPreview({
    required this.id,
    required this.senderId,
    this.senderName,
    required this.snippet,
    this.deleted = false,
    this.edited = false,
  });

  final String id;
  final String senderId;
  final String? senderName;
  final String snippet;
  final bool deleted;
  final bool edited;

  factory ReplyPreview.fromJson(Map<String, dynamic> j) => ReplyPreview(
        id: j['id'] as String,
        senderId: j['sender_id'] as String,
        senderName: j['sender_name'] as String?,
        snippet: j['body_snippet'] as String? ?? '',
        deleted: j['deleted'] as bool? ?? false,
        edited: j['edited'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sender_id': senderId,
        'sender_name': senderName,
        'body_snippet': snippet,
        'deleted': deleted,
        'edited': edited,
      };

  /// The quote for a message being replied to on this device, before the server answers.
  factory ReplyPreview.of(ChatMessage target, {String? senderName}) => ReplyPreview(
        id: target.id,
        senderId: target.senderId,
        senderName: senderName,
        snippet: oneLine(target.body),
        edited: target.editedAt != null,
      );

  ReplyPreview copyWith({String? snippet, bool? deleted, bool? edited}) => ReplyPreview(
        id: id,
        senderId: senderId,
        senderName: senderName,
        snippet: snippet ?? this.snippet,
        deleted: deleted ?? this.deleted,
        edited: edited ?? this.edited,
      );
}

/// A message body as one short line — the same shape as the server's excerpt.
String oneLine(String body, {int limit = 60}) {
  final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length <= limit) return text;
  return '${text.substring(0, limit).trimRight()}…';
}

class ChatMessage {
  final String id;
  final String matchId;
  final String senderId;
  final String? clientMessageId;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  /// Whether the recipient's device has acknowledged receipt (protocol 2).
  ///
  /// A boolean, not a timestamp. Delivery is recorded server-side as a per-member *boundary*,
  /// which does not store when it passed any particular older message — so a `deliveredAt` would
  /// be a fabricated time for every message but the newest. `readAt` can be a timestamp because
  /// `messages.read_at` is a real per-row column.
  ///
  /// False also covers "not knowable": on a protocol 1 server nothing sends the acknowledgement.
  /// That reads as "sent", understating progress rather than claiming something untrue.
  final bool delivered;
  final MessageStatus status;
  final bool deleted;

  /// Aggregated reactions, in the server's order (the picker's order), so the chip strip does not
  /// reshuffle between requests. Empty for the overwhelming majority of messages.
  final List<ReactionSummary> reactions;

  /// When the sender last edited this, or null. Drives the small "edited" label; the record of
  /// *what* changed lives server-side and is never sent to clients.
  final DateTime? editedAt;

  /// The message this one replies to, as its quote shows it; null when it is not a reply.
  final ReplyPreview? replyTo;

  const ChatMessage({
    required this.id,
    required this.matchId,
    required this.senderId,
    this.clientMessageId,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.delivered = false,
    this.status = MessageStatus.sent,
    this.deleted = false,
    this.reactions = const [],
    this.editedAt,
    this.replyTo,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        matchId: (j['match_id'] ?? j['conversation_id']) as String,
        senderId: j['sender_id'] as String,
        clientMessageId: j['client_message_id'] as String?,
        body: j['body'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        readAt: j['read_at'] != null ? DateTime.parse(j['read_at'] as String) : null,
        // `delivered` comes from the server's per-page delivery cursor. A read message was
        // necessarily received, so `read_at` also implies it — which matters because the server
        // computes `delivered` as "every other member has acknowledged", and a member who
        // acknowledges nothing (an older client) would otherwise hold it at false forever.
        delivered: (j['delivered'] as bool? ?? false) || j['read_at'] != null,
        status: MessageStatus.sent,
        deleted: j['deleted'] as bool? ?? false,
        reactions: [
          for (final r in (j['reactions'] as List? ?? const []))
            ReactionSummary.fromJson(Map<String, dynamic>.from(r as Map)),
        ],
        editedAt: j['edited_at'] != null ? DateTime.parse(j['edited_at'] as String) : null,
        replyTo: j['reply_to'] != null
            ? ReplyPreview.fromJson(Map<String, dynamic>.from(j['reply_to'] as Map))
            : null,
      );

  ChatMessage copyWith({
    String? id,
    DateTime? readAt,
    bool? delivered,
    MessageStatus? status,
    bool? deleted,
    List<ReactionSummary>? reactions,
    String? body,
    DateTime? editedAt,
    ReplyPreview? replyTo,
    bool clearReplyTo = false,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        matchId: matchId,
        senderId: senderId,
        clientMessageId: clientMessageId,
        body: body ?? this.body,
        createdAt: createdAt,
        readAt: readAt ?? this.readAt,
        delivered: delivered ?? this.delivered,
        status: status ?? this.status,
        deleted: deleted ?? this.deleted,
        reactions: reactions ?? this.reactions,
        editedAt: editedAt ?? this.editedAt,
        replyTo: clearReplyTo ? null : (replyTo ?? this.replyTo),
      );
}
