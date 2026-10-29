/// The second line of an inbox row — pure, so the WhatsApp-style rules are testable.
library;

import 'message_models.dart';
import 'thread_models.dart';

/// What the row says under the name, and whether it reads as a quiet note (italic).
typedef ThreadPreviewLine = ({String text, bool italic});

/// In order: a reaction newer than the latest message ("Ama reacted 👍 to “see you at 5”"),
/// a deleted latest message, my own latest message ("You: …"), anyone else's, or an empty chat.
/// Typing is decided by the row itself, since it is live rather than data.
ThreadPreviewLine threadPreview(MessageThread thread, String myId) {
  final latest = thread.latestMessage;
  final reaction = thread.latestReaction;
  if (reaction != null && (latest == null || reaction.reactedAt.isAfter(latest.createdAt))) {
    return (text: reactionLine(thread, reaction, myId), italic: false);
  }
  if (latest == null) return (text: 'No messages yet — say hello', italic: true);
  if (latest.deleted) {
    return (
      text: latest.senderId == myId ? 'You deleted this message' : 'This message was deleted',
      italic: true,
    );
  }
  if (latest.senderId == myId) return (text: 'You: ${oneLine(latest.body)}', italic: false);
  return (text: oneLine(latest.body), italic: false);
}

/// "You reacted ❤️ to “…”" / "Ama reacted 👍 to your message" / "Ama reacted 👍 to “…”".
String reactionLine(MessageThread thread, ThreadReactionPreview r, String myId) {
  final who = r.actorId == myId ? 'You' : _actorName(thread, r);
  final quoted = r.messageSnippet.isEmpty ? null : '“${r.messageSnippet}”';
  // No sender id means an older server, whose previews were only ever of reactions to my messages.
  final mine = r.messageSenderId == null || r.messageSenderId == myId;
  final target = mine && who != 'You'
      ? (quoted == null ? 'your message' : 'your message $quoted')
      : (quoted ?? 'a message');
  return '$who reacted ${r.emoji} to $target';
}

String _actorName(MessageThread thread, ThreadReactionPreview r) {
  final name = r.actorName ?? (thread.isGroup ? null : thread.partner?.displayName);
  if (name == null || name.trim().isEmpty) return 'Someone';
  // First name only in a busy row, as WhatsApp does.
  return name.trim().split(RegExp(r'\s+')).first;
}
