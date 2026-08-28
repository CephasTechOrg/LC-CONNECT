part of '../screens/chat_screen.dart';

class _MessageList extends StatelessWidget {
  final List<ChatMessage> messages;
  final String currentUserId;
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
    this.iAmGroupAdmin = false,
    required this.scrollController,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    // Build list with date separators. In a group, mark the first message of each run from a
    // given sender (a separator, or a change of sender, starts a new run) so we show the
    // sender's name/avatar once per run — WhatsApp-style — instead of on every bubble.
    final items = <_ListItem>[];
    DateTime? lastDate;
    String? runSenderId;

    for (final msg in messages) {
      final local = msg.createdAt.toLocal();
      final msgDate = DateTime(local.year, local.month, local.day);
      if (lastDate == null || msgDate != lastDate) {
        items.add(_DateSeparatorItem(msgDate));
        lastDate = msgDate;
        runSenderId = null; // a date break restarts the run
      }
      final firstOfRun = msg.senderId != runSenderId;
      runSenderId = msg.senderId;
      items.add(_MessageItem(msg, firstOfRun));
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        if (item is _DateSeparatorItem) {
          return _DateSeparator(date: item.date);
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
          onReport: onReport,
          // Delete for everyone: my own messages anywhere, or anyone's when I moderate the group.
          onDelete: (isMine || iAmGroupAdmin) ? onDelete : null,
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
                      style: GoogleFonts.dmSans(
                        fontSize: 10,
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

class _MessageItem extends _ListItem {
  final ChatMessage message;
  final bool firstOfRun; // first message of a run from this sender (group identity anchor)
  _MessageItem(this.message, this.firstOfRun);
}

// ── Date separator ────────────────────────────────────────────────
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
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppColors.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _label(),
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Expanded(child: Divider(color: AppColors.border)),
        ],
      ),
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────
