part of '../screens/chat_screen.dart';

class _MessageList extends StatelessWidget {
  final List<ChatMessage> messages;
  final String currentUserId;

  /// Null when the server predates reactions — see `kReactionProtocolVersion`.
  final void Function(ChatMessage message, String emoji)? onReact;

  /// Null when the server predates editing.
  final void Function(ChatMessage)? onEdit;
  final String? partnerAvatarUrl;
  final bool isGroup;
  final Map<String, MessageSender> senders;
  final void Function(ChatMessage)? onReport;
  final void Function(ChatMessage)? onDelete;
  final bool iAmGroupAdmin;
  final ScrollController scrollController;
  final void Function(ChatMessage) onRetry;
  const _MessageList({
    required this.messages,
    required this.currentUserId,
    this.partnerAvatarUrl,
    this.isGroup = false,
    this.senders = const {},
    this.onReport,
    this.onDelete,
    this.onReact,
    this.onEdit,
    this.iAmGroupAdmin = false,
    required this.scrollController,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    // Build list with date separators, and mark where each message sits in its run (same
    // sender, same day, close together) so identity, timestamps and the bubble tail appear once
    // per run rather than on every bubble.
    final runs = computeMessageRuns<ChatMessage>(
      messages,
      senderOf: (m) => m.senderId,
      createdAtOf: (m) => m.createdAt,
    );
    final items = <_ListItem>[];
    DateTime? lastDate;
    final actions = _ChatActions.maybeOf(context);

    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      final local = msg.createdAt.toLocal();
      final msgDate = DateTime(local.year, local.month, local.day);
      if (lastDate == null || msgDate != lastDate) {
        items.add(_DateSeparatorItem(msgDate));
        lastDate = msgDate;
      }
      if (msg.id == actions?.unreadDividerBefore) items.add(_UnreadDividerItem(actions!.unreadCount));
      final run = runs[i];
      // Mid-run footers are hidden, except where my tick changes (e.g. read up to here,
      // delivered after) — collapsing that would hide where the receipt boundary is.
      final tickChangesHere = msg.senderId == currentUserId &&
          !run.lastOfRun &&
          OutgoingState.of(msg) != OutgoingState.of(messages[i + 1]);
      items.add(_MessageItem(
        msg,
        firstOfRun: run.firstOfRun,
        lastOfRun: run.lastOfRun,
        showFooter: run.lastOfRun || tickChangesHere,
      ));
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        if (item is _DateSeparatorItem) {
          return _DateSeparator(date: item.date);
        }
        if (item is _UnreadDividerItem) {
          return _UnreadDivider(count: item.count);
        }
        final messageItem = item as _MessageItem;
        final msg = messageItem.message;
        final isMine = msg.senderId == currentUserId;
        final showSenderIdentity = isGroup && !isMine && messageItem.firstOfRun;
        return _BubbleTile(
          message: msg,
          isMine: isMine,
          isGroup: isGroup,
          partnerAvatarUrl: partnerAvatarUrl,
          sender: isGroup ? senders[msg.senderId] : null,
          showSenderIdentity: showSenderIdentity,
          firstOfRun: messageItem.firstOfRun,
          lastOfRun: messageItem.lastOfRun,
          showFooter: messageItem.showFooter,
          onReport: onReport,
          // Delete for everyone: my own messages anywhere, or anyone's when I moderate the group.
          onDelete: (isMine || iAmGroupAdmin) ? onDelete : null,
          onReact: onReact,
          onEdit: onEdit,
          onRetry: onRetry,
        );
      },
    );
  }
}

// ── Scroll-to-bottom FAB ─────────────────────────────────────────
class _ScrollToBottomFab extends StatelessWidget {
  final int newCount;
  final VoidCallback onTap;
  const _ScrollToBottomFab({required this.newCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      shadowColor: Colors.black26,
      color: AppColors.surface,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primary, size: 26),
              if (newCount > 0)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      newCount > 99 ? '99+' : '$newCount',
                      style: AppTypography.micro.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// List item types for interleaving date separators and bubbles
abstract class _ListItem {}

class _DateSeparatorItem extends _ListItem {
  final DateTime date;
  _DateSeparatorItem(this.date);
}

class _UnreadDividerItem extends _ListItem {
  final int count;
  _UnreadDividerItem(this.count);
}

class _MessageItem extends _ListItem {
  final ChatMessage message;
  final bool firstOfRun; // group sender name anchors here
  final bool lastOfRun; // avatar and tail anchor here
  final bool showFooter; // timestamp + tick row
  _MessageItem(
    this.message, {
    required this.firstOfRun,
    required this.lastOfRun,
    required this.showFooter,
  });
}

// ── Date separator ────────────────────────────────────────────────
/// "3 new messages" above the first one you have not read, so opening a busy chat lands where you
/// left off instead of at the bottom.
class _UnreadDivider extends StatelessWidget {
  final int count;
  const _UnreadDivider({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppColors.primarySoft, thickness: 1)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
            child: Text(
              count == 1 ? '1 new message' : '$count new messages',
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.primaryText),
            ),
          ),
          const Expanded(child: Divider(color: AppColors.primarySoft, thickness: 1)),
        ],
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  final DateTime date;
  const _DateSeparator({required this.date});

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    return DateFormat('MMM d').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
          child: Text(
            _label(),
            style: AppTypography.caption.copyWith(
              color: AppColors.textMid,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────
