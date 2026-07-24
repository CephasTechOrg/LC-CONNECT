part of '../screens/chat_screen.dart';

class _BubbleTile extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final bool isGroup;
  final String? partnerAvatarUrl;
  final MessageSender? sender; // group mode: the message's sender identity
  final bool showSenderIdentity; // first message of a sender's run → show name + avatar
  final void Function(ChatMessage)? onReport;
  final void Function(ChatMessage)? onRetry;
  const _BubbleTile({
    required this.message,
    required this.isMine,
    this.isGroup = false,
    this.partnerAvatarUrl,
    this.sender,
    this.showSenderIdentity = false,
    this.onReport,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    // Leading avatar: DMs show the partner on every incoming bubble; groups show the sender's
    // avatar once per run and reserve the space (an empty gutter) on the follow-ups so bubbles
    // stay aligned.
    final Widget? leading = isMine
        ? null
        : isGroup
            ? (showSenderIdentity
                ? AvatarWidget(imageUrl: sender?.avatarUrl, size: 28, cacheScope: message.senderId)
                : const SizedBox(width: 28))
            : AvatarWidget(imageUrl: partnerAvatarUrl, size: 28);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (leading != null) ...[
            leading,
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (showSenderIdentity && sender != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      sender!.name,
                      style: GoogleFonts.dmSans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                GestureDetector(
                  onLongPress: (!isMine && onReport != null)
                      ? () => _showReportOption(context)
                      : null,
                  child: Container(
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

  void _showReportOption(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: AppColors.textMid),
              title: Text(
                'Report message',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w500, color: AppColors.textDark),
              ),
              subtitle: Text(
                'Flag this message for review',
                style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted),
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                onReport?.call(message);
              },
            ),
          ],
        ),
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
