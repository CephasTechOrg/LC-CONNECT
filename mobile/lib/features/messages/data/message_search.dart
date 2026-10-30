/// One message found by `GET /messages/search`, with enough of its chat to show and open it.
library;

class MessageSearchHit {
  const MessageSearchHit({
    required this.messageId,
    required this.threadId,
    required this.kind,
    required this.title,
    required this.senderId,
    required this.snippet,
    required this.createdAt,
    this.avatarUrl,
    this.groupId,
  });

  final String messageId;

  /// The addressing id the chat is opened by.
  final String threadId;
  final String kind; // dm | staff_dm | group
  final String title;
  final String? avatarUrl;
  final String? groupId;
  final String senderId;
  final String snippet;
  final DateTime createdAt;

  bool get isGroup => kind == 'group';

  factory MessageSearchHit.fromJson(Map<String, dynamic> j) => MessageSearchHit(
        messageId: j['message_id'] as String,
        threadId: j['thread_id'] as String,
        kind: j['kind'] as String? ?? 'dm',
        title: j['title'] as String? ?? 'Chat',
        avatarUrl: j['avatar_url'] as String?,
        groupId: j['group_id'] as String?,
        senderId: j['sender_id'] as String,
        snippet: j['snippet'] as String? ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
