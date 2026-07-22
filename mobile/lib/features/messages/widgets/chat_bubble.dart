part of '../screens/chat_screen.dart';

class _BubbleTile extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final String? partnerAvatarUrl;
  final void Function(ChatMessage)? onRetry;
  const _BubbleTile({
    required this.message,
    required this.isMine,
    this.partnerAvatarUrl,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            AvatarWidget(imageUrl: partnerAvatarUrl, size: 28),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMine ? AppColors.primary : AppColors.surface,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMine ? 18 : 4),
                      bottomRight: Radius.circular(isMine ? 4 : 18),
                    ),
                    border: isMine
                        ? null
                        : Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(10),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.68,
                  ),
                  child: Text(
                    message.body,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      color: isMine ? Colors.white : AppColors.textDark,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('h:mm a').format(message.createdAt.toLocal()),
                      style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.textMuted),
                    ),
                    if (isMine) ...[const SizedBox(width: 5), _status(context)],
                  ],
                ),
              ],
            ),
          ),
          if (isMine) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _status(BuildContext context) {
    switch (message.status) {
      case MessageStatus.sending:
        return const Icon(Icons.schedule_rounded, size: 11, color: AppColors.textMuted);
      case MessageStatus.failed:
        return GestureDetector(
          onTap: () => onRetry?.call(message),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 11, color: AppColors.error),
              const SizedBox(width: 3),
              Text(
                'Retry',
                style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      case MessageStatus.sent:
        final read = message.readAt != null;
        return Icon(
          read ? Icons.done_all_rounded : Icons.check_rounded,
          size: 12,
          color: read ? AppColors.primary : AppColors.textMuted,
        );
    }
  }
}

// ── Input bar ─────────────────────────────────────────────────────
