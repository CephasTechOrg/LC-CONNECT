part of '../screens/messages_screen.dart';

/// "Archived (3)" at the top of the inbox — archived chats leave the main list but stay one tap
/// away, and keep counting unread messages here.
class _ArchivedRow extends ConsumerWidget {
  final List<MessageThread> archived;
  const _ArchivedRow({required this.archived});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(
      unreadProvider.select((s) => archived.fold<int>(0, (n, t) => n + s.countFor(t.addressingId))),
    );
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _ArchivedChatsScreen())),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter, vertical: AppSpacing.md),
        child: Row(
          children: [
            const SizedBox(
              width: _ThreadCard.avatarSize,
              child: Icon(Icons.archive_outlined, color: AppColors.textMid),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'Archived',
                style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.textDark),
              ),
            ),
            Text(
              unread > 0 ? '$unread' : '${archived.length}',
              style: AppTypography.caption.copyWith(
                fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500,
                color: unread > 0 ? AppColors.primaryText : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchivedChatsScreen extends ConsumerWidget {
  const _ArchivedChatsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads = arrangeInbox(ref.watch(threadsNotifierProvider).value ?? const []).archived;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: Text('Archived', style: AppTypography.title.copyWith(fontWeight: FontWeight.w700)),
      ),
      body: threads.isEmpty
          ? const AppScrollableEmptyState(
              icon: Icons.archive_outlined,
              title: 'No archived chats',
              subtitle: 'Long-press a chat in your inbox to archive it.',
              topFraction: 0.2,
            )
          : _ThreadList(threads: threads),
    );
  }
}
