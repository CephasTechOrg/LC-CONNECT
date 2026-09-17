part of '../screens/chat_screen.dart';

class _BubbleTile extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final bool isGroup;
  final String? partnerAvatarUrl;
  final MessageSender? sender; // group mode: the message's sender identity
  final bool showSenderIdentity; // first message of a sender's run → show name + avatar
  final void Function(ChatMessage)? onReport;
  final void Function(ChatMessage)? onDelete; // delete-for-everyone (own message, or I moderate)
  final void Function(ChatMessage)? onRetry;
  const _BubbleTile({
    required this.message,
    required this.isMine,
    this.isGroup = false,
    this.partnerAvatarUrl,
    this.sender,
    this.showSenderIdentity = false,
    this.onReport,
    this.onDelete,
    this.onRetry,
  });

  bool get _canReport => !isMine && onReport != null;
  bool get _canDelete => onDelete != null;

  /// Only for my own group messages. In a DM the tick already answers this precisely, and for
  /// someone else's message "who has read it" is not mine to ask.
  bool get _canSeeReadBy => isGroup && isMine && !message.deleted && !message.id.startsWith('local:');
  bool get _hasMenu => !message.deleted && (_canReport || _canDelete);

  @override
  Widget build(BuildContext context) {
    // Leading avatar: DMs show the partner on every incoming bubble; groups show the sender's
    // avatar once per run and reserve the space (an empty gutter) on the follow-ups so bubbles
    // stay aligned.
    final Widget? leading = isMine
        ? null
        : isGroup
            ? (showSenderIdentity
                ? GestureDetector(
                    // Tap a sender's avatar → their profile.
                    onTap: sender?.profileId != null
                        ? () => context.push('/users/${sender!.profileId}', extra: sender!.name)
                        : null,
                    child: AvatarWidget(imageUrl: sender?.avatarUrl, size: 28, cacheScope: message.senderId),
                  )
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
                  onLongPress: _hasMenu ? () => _showOptions(context) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: message.deleted
                          ? AppColors.background
                          : (isMine ? AppColors.primary : AppColors.surface),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMine ? 18 : 4),
                        bottomRight: Radius.circular(isMine ? 4 : 18),
                      ),
                      border: isMine && !message.deleted
                          ? null
                          : Border.all(color: AppColors.border),
                      boxShadow: message.deleted
                          ? null
                          : [
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
                    child: message.deleted
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.block_rounded, size: 13, color: AppColors.textMuted),
                              const SizedBox(width: 6),
                              Text(
                                'This message was deleted',
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          )
                        : Text(
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
                    if (isMine && !message.deleted) ...[const SizedBox(width: 5), _status(context)],
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

  void _showOptions(BuildContext context) {
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
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 8),
            if (_canSeeReadBy)
              ListTile(
                leading: const Icon(Icons.done_all_rounded, color: AppColors.primary),
                title: Text('Read by',
                    style: GoogleFonts.dmSans(fontWeight: FontWeight.w500, color: AppColors.textDark)),
                subtitle: Text('See who has read this message',
                    style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted)),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  showModalBottomSheet<void>(
                    context: context,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (_) => _ReadBySheet(messageId: message.id),
                  );
                },
              ),
            if (_canDelete)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                title: Text('Delete for everyone',
                    style: GoogleFonts.dmSans(fontWeight: FontWeight.w500, color: AppColors.error)),
                subtitle: Text('Removes it for all participants',
                    style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted)),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  onDelete?.call(message);
                },
              ),
            if (_canReport)
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: AppColors.textMid),
                title: Text('Report message',
                    style: GoogleFonts.dmSans(fontWeight: FontWeight.w500, color: AppColors.textDark)),
                subtitle: Text('Flag this message for review',
                    style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted)),
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

  /// See [MessageStatusIcon] — shared with the conversation row so the two can never show
  /// different states for the same message.
  Widget _status(BuildContext context) =>
      MessageStatusIcon(message: message, onRetry: onRetry);
}

// ── Input bar ─────────────────────────────────────────────────────
