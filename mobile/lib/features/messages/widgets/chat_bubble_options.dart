part of '../screens/chat_screen.dart';

/// The long-press / double-tap sheet for a bubble: react, read-by, edit, delete, report.
extension _BubbleOptions on _BubbleTile {
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
            if (_canReact) ...[
              _ReactionPicker(
                chosen: myEmoji(message.reactions),
                onPick: (emoji) {
                  Navigator.of(sheetCtx).pop();
                  onReact!(message, emoji);
                },
              ),
              const Divider(height: 1, color: AppColors.border),
            ],
            if (_ChatActions.maybeOf(context)?.onReply != null && _canReplyTo)
              ListTile(
                leading: const Icon(Icons.reply_rounded, color: AppColors.textMid),
                title: Text('Reply',
                    style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textDark)),
                subtitle: Text('Quote this message in your answer',
                    style: AppTypography.label.copyWith(fontWeight: FontWeight.w400, color: AppColors.textMuted)),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _ChatActions.maybeOf(context)!.onReply!(message);
                },
              ),
            if (_ChatActions.maybeOf(context)?.onShowReactors != null && message.reactions.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.emoji_emotions_outlined, color: AppColors.textMid),
                title: Text('Reactions',
                    style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textDark)),
                subtitle: Text('See who reacted',
                    style: AppTypography.label.copyWith(fontWeight: FontWeight.w400, color: AppColors.textMuted)),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _ChatActions.maybeOf(context)!.onShowReactors!(message);
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: AppColors.textMid),
              title: Text('Copy',
                  style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textDark)),
              subtitle: Text('Copy this message',
                  style: AppTypography.label.copyWith(fontWeight: FontWeight.w400, color: AppColors.textMuted)),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: message.body));
                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Copied'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              },
            ),
            if (_canSeeReadBy)
              ListTile(
                leading: const Icon(Icons.done_all_rounded, color: AppColors.primary),
                title: Text('Read by',
                    style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textDark)),
                subtitle: Text('See who has read this message',
                    style: AppTypography.label.copyWith(fontWeight: FontWeight.w400, color: AppColors.textMuted)),
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
            if (_canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: AppColors.textMid),
                title: Text('Edit message',
                    style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textDark)),
                subtitle: Text('Everyone sees it change, marked as edited',
                    style: AppTypography.label.copyWith(fontWeight: FontWeight.w400, color: AppColors.textMuted)),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  onEdit!(message);
                },
              ),
            if (_canDelete)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                title: Text('Delete for everyone',
                    style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.error)),
                subtitle: Text('Removes it for all participants',
                    style: AppTypography.label.copyWith(fontWeight: FontWeight.w400, color: AppColors.textMuted)),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  onDelete?.call(message);
                },
              ),
            if (_canReport)
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: AppColors.textMid),
                title: Text('Report message',
                    style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textDark)),
                subtitle: Text('Flag this message for review',
                    style: AppTypography.label.copyWith(fontWeight: FontWeight.w400, color: AppColors.textMuted)),
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
}
