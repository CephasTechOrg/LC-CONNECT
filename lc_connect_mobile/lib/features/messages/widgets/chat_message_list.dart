part of '../screens/chat_screen.dart';

class _MessageList extends StatelessWidget {
  final List<ChatMessage> messages;
  final String currentUserId;
  final String? partnerAvatarUrl;
  final ScrollController scrollController;
  const _MessageList({
    required this.messages,
    required this.currentUserId,
    this.partnerAvatarUrl,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    // Build list with date separators
    final items = <_ListItem>[];
    DateTime? lastDate;

    for (final msg in messages) {
      final local = msg.createdAt.toLocal();
      final msgDate = DateTime(local.year, local.month, local.day);
      if (lastDate == null || msgDate != lastDate) {
        items.add(_DateSeparatorItem(msgDate));
        lastDate = msgDate;
      }
      items.add(_MessageItem(msg));
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
        final msg = (item as _MessageItem).message;
        final isMine = msg.senderId == currentUserId;
        return _BubbleTile(
          message: msg, 
          isMine: isMine,
          partnerAvatarUrl: partnerAvatarUrl,
        );
      },
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
  _MessageItem(this.message);
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
