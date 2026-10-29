/// How the inbox arranges its rows — pure, so the rules are testable.
library;

import 'thread_models.dart';

typedef InboxArrangement = ({List<MessageThread> main, List<MessageThread> archived});

/// Archived chats leave the main list (they get their own row). Pinned chats lead it, most
/// recently pinned first; the rest keep the server's newest-activity order.
InboxArrangement arrangeInbox(List<MessageThread> threads) {
  final pinned = [for (final t in threads) if (t.pinned && !t.archived) t]
    ..sort((a, b) => b.pinnedAt!.compareTo(a.pinnedAt!));
  return (
    main: [
      ...pinned,
      for (final t in threads) if (!t.pinned && !t.archived) t,
    ],
    archived: [for (final t in threads) if (t.archived) t],
  );
}

/// The most chats that can be pinned — the server answers 409 beyond it.
const kMaxPinnedChats = 3;
