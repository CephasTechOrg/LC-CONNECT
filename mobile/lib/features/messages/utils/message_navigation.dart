import 'package:go_router/go_router.dart';

import '../../groups/data/group_models.dart';
import '../providers/messages_provider.dart';

/// Open a conversation from a push/banner using the same routing rules as the inbox.
void openMessageConversation({
  required GoRouter router,
  required String conversationId,
  List<MessageThread>? threads,
}) {
  MessageThread? thread;
  if (threads != null) {
    for (final candidate in threads) {
      if (candidate.addressingId == conversationId) {
        thread = candidate;
        break;
      }
    }
  }

  if (thread != null && thread.isGroup) {
    router.push(
      '/messages/group/${thread.conversationId}',
      extra: GroupChatArgs(
        name: thread.groupName ?? 'Group',
        groupId: thread.groupId,
        avatarUrl: thread.groupAvatarUrl,
      ),
    );
    return;
  }

  router.push('/messages/$conversationId', extra: thread);
}
