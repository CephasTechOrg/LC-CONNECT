part of '../screens/messages_screen.dart';

/// "Messages" — search hits across every chat, below the chats whose names match. Tapping one opens
/// the chat at that message and highlights it.
class _MessageSearchResults extends StatelessWidget {
  final List<MessageSearchHit> hits;
  final List<MessageThread> threads;
  const _MessageSearchResults({required this.hits, required this.threads});

  void _open(BuildContext context, MessageSearchHit hit) {
    final at = '?m=${Uri.encodeQueryComponent(hit.messageId)}';
    if (hit.isGroup) {
      context.push(
        '${groupChatPath(hit.threadId)}$at',
        extra: GroupChatArgs(name: hit.title, groupId: hit.groupId, avatarUrl: hit.avatarUrl),
      );
      return;
    }
    final thread = threads.where((t) => t.addressingId == hit.threadId).firstOrNull;
    context.push('${dmChatPath(hit.threadId)}$at', extra: thread);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, AppSpacing.xs),
          child: Text(
            'Messages',
            style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w700, color: AppColors.textMid),
          ),
        ),
        for (final hit in hits)
          InkWell(
            onTap: () => _open(context, hit),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  AvatarWidget(imageUrl: hit.avatarUrl, size: 40),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                hit.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.body.copyWith(fontWeight: FontWeight.w700, color: AppColors.textDark),
                              ),
                            ),
                            Text(
                              _formatThreadTime(hit.createdAt),
                              style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                            ),
                          ],
                        ),
                        Text(
                          hit.snippet,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall.copyWith(color: AppColors.textMid),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
