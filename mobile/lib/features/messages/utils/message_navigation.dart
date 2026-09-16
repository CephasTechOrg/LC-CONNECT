import 'package:go_router/go_router.dart';

import '../../groups/data/group_models.dart';
import '../providers/messages_provider.dart';

/// Open a conversation from a push or an in-app banner, using the same routing rules as the inbox.
///
/// [threads] is the loaded thread list, which is what distinguishes a group conversation from a
/// DM. When it is unavailable the old behaviour was to fall through to the DM route — so a **group**
/// notification opened from a cold start rendered as a direct message: wrong header, no `groupId`,
/// and every group-specific affordance disabled. That was reachable in practice, because the tap
/// used to be handled the instant auth resolved, well before the inbox had loaded.
///
/// Two things address it. The tap is now queued until the app is navigable
/// (`pendingDeepLinkProvider`), so the list has usually loaded by the time this runs; and when it
/// still has not, [onUnresolved] lets the caller fetch the threads and try again rather than
/// guessing. Guessing DM is the one option that produces a visibly broken screen.
void openMessageConversation({
  required GoRouter router,
  required String conversationId,
  List<MessageThread>? threads,
  Future<List<MessageThread>?> Function()? onUnresolved,
}) {
  final thread = _find(threads, conversationId);
  if (thread != null) {
    _push(router, conversationId, thread);
    return;
  }

  if (onUnresolved == null) {
    // No way to resolve the kind. The DM route still handles a conversation id correctly
    // server-side; it is only the group chrome that would be missing.
    router.push('/messages/$conversationId');
    return;
  }

  onUnresolved().then((fetched) {
    _push(router, conversationId, _find(fetched, conversationId));
  });
}

MessageThread? _find(List<MessageThread>? threads, String conversationId) {
  if (threads == null) return null;
  for (final candidate in threads) {
    if (candidate.addressingId == conversationId) return candidate;
  }
  return null;
}

void _push(GoRouter router, String conversationId, MessageThread? thread) {
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
