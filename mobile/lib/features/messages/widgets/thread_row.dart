part of '../screens/messages_screen.dart';

class _ThreadCard extends ConsumerWidget {
  final MessageThread thread;
  const _ThreadCard({required this.thread});

  static const avatarSize = 48.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = thread.latestMessage;
    final unread = ref.watch(unreadProvider.select((s) => s.countFor(thread.addressingId)));
    // Report #23: the row showed incoming state (an unread bubble, a bold preview) but nothing at
    // all when the last message was mine — so the one place a sender looks to check on a
    // conversation they are waiting on said nothing. Groups are excluded: "delivered" there needs
    // a rule about which members count, which is deliberately out of scope (see the design doc
    // §2.1); they get a "read by" list in the conversation instead.
    final myId = ref.watch(authNotifierProvider).asData?.value?.id;
    final outgoing =
        (!thread.isGroup && latest != null && myId != null && latest.senderId == myId)
            ? latest
            : null;

    return InkWell(
      onTap: () => thread.isGroup
          ? context.push(groupChatPath(thread.conversationId),
              extra: GroupChatArgs(
                  name: thread.groupName ?? 'Group', groupId: thread.groupId, avatarUrl: thread.avatarUrl))
          : context.push(dmChatPath(thread.addressingId), extra: thread),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.gutter,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            AvatarWidget(imageUrl: thread.avatarUrl, size: avatarSize),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _titleRow(latest, hasUnread: unread > 0),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(child: _preview(latest, hasUnread: unread > 0, myId: myId ?? '')),
                      if (outgoing != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        // Compact: the conversation row has no room for a "Retry" label, and
                        // retrying belongs in the conversation anyway.
                        MessageStatusIcon(message: outgoing, compact: true),
                      ],
                      if (thread.muted) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const Icon(Icons.notifications_off_outlined, size: 16, color: AppColors.textMuted),
                      ],
                      if (unread > 0) ...[
                        const SizedBox(width: AppSpacing.sm),
                        _UnreadBubble(count: unread, muted: thread.muted),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Name (+ verified, + a Staff tag) on the left, time on the right.
  ///
  /// The major or position used to follow the name here and was cut off on most rows
  /// ("Computer Scien…", "Campus Safety …") — half a label beside every name. The chat header
  /// shows it in full; the row keeps only what tells conversations apart, and the Staff tag so
  /// a message from an officer or advisor still stands out from a classmate's.
  Widget _titleRow(ChatMessage? latest, {required bool hasUnread}) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  thread.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              if (!thread.isGroup && (thread.partner?.campusVerified ?? false)) ...[
                const SizedBox(width: AppSpacing.xs),
                const VerifiedBadge(size: 14),
              ],
              if (thread.isStaffThread && thread.partnerSubtitle != null) ...[
                const SizedBox(width: 6),
                const StaffTag(),
              ],
            ],
          ),
        ),
        if (latest != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Text(
            _formatThreadTime(latest.createdAt),
            style: AppTypography.caption.copyWith(
              color: hasUnread ? AppColors.primaryText : AppColors.textMuted,
              fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }

  Widget _preview(ChatMessage? latest, {required bool hasUnread, required String myId}) {
    // Typing is live and most salient; everything else is [threadPreview]'s call.
    if (thread.partnerTyping) {
      return Text(
        'typing…',
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.primaryText,
          fontWeight: FontWeight.w600,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    final line = threadPreview(thread, myId);
    return Text(
      line.text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.bodySmall.copyWith(
        // Unread → darker + semibold (WhatsApp-style emphasis).
        color: hasUnread ? AppColors.textDark : (line.italic ? AppColors.textMuted : AppColors.textMid),
        fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
        fontStyle: line.italic ? FontStyle.italic : FontStyle.normal,
      ),
    );
  }
}

// ── Unread count bubble ───────────────────────────────────────────
class _UnreadBubble extends StatelessWidget {
  final int count;

  /// A muted chat's count is greyed, as in WhatsApp — still visible, no longer calling for you.
  final bool muted;
  const _UnreadBubble({required this.count, this.muted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: muted ? AppColors.textMuted : AppColors.primary,
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: AppTypography.caption.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}

// ── Time formatter ────────────────────────────────────────────────
String _formatThreadTime(DateTime dt) {
  final local = dt.toLocal();
  final diff = DateTime.now().difference(local);
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return AppDateFormat.weekday(local);
  return AppDateFormat.dayMonth(local);
}
