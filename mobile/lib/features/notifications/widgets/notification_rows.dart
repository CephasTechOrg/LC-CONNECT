part of '../screens/notifications_screen.dart';

/// A calendar-day heading over that day's card.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.xl,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Text(
        label,
        style: AppTypography.label.copyWith(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One day's notifications in a single card, rows split by hairlines inset to the text — the
/// same grouped-list shape as the group settings sections, so a long history reads as a few
/// blocks rather than one edge-to-edge run of rows.
class _DayCard extends StatelessWidget {
  const _DayCard({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: _textInset,
                color: AppColors.border,
              ),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// Where a row's text starts: padding + 40dp avatar + gap.
const double _textInset = AppSpacing.lg + 40 + AppSpacing.md;

/// Pinned entry to the Connections screen, with a live count of pending incoming requests.
class _ConnectionRequestsCard extends ConsumerWidget {
  const _ConnectionRequestsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count =
        ref.watch(connectionsNotifierProvider).asData?.value.incoming.length ??
        0;
    return AppCard(
      onTap: () => context.push('/connections'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          const AppIconTile(
            icon: Icons.people_alt_outlined,
            color: AppColors.primaryText,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connection requests',
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count > 0 ? '$count waiting for you' : 'View sent and received',
                  style: AppTypography.bodySmall.copyWith(
                    color: count > 0 ? AppColors.primaryText : AppColors.textMuted,
                    fontWeight: count > 0 ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;

  /// Supplied by the screen from its entry snapshot, not derived from `notification.read` — see
  /// [NotificationsScreen].
  final bool unread;
  final VoidCallback? onOpen;
  const _NotificationTile({
    required this.notification,
    this.unread = false,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final route = notification.route;
    return Semantics(
      // Unread is otherwise signalled only by a tint and a dot — both colour, neither available
      // to a screen reader.
      label: unread ? 'Unread. ${notification.message}' : notification.message,
      child: _tile(context, route),
    );
  }

  void _showExactTime(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppDateFormat.dateTime(notification.createdAt)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _tile(BuildContext context, String? route) {
    // No chevron: the whole row opens, and a column of identical arrows down the card was the
    // loudest thing on the page while saying nothing about any one row. The dot is the only
    // trailing mark, so it is the one the eye finds.
    return ListTile(
      onTap: onOpen ?? (route != null ? () => context.push(route) : null),
      // The row shows a relative stamp ("3d"), which is right for scanning and useless for
      // "when exactly?". Long-press answers that without spending a second line on every row.
      onLongPress: () => _showExactTime(context),
      tileColor: unread ? AppColors.primarySoft.withValues(alpha: 0.5) : null,
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      horizontalTitleGap: AppSpacing.md,
      minVerticalPadding: AppSpacing.md,
      leading: notification.isActorCentric
          ? AvatarWidget(
              imageUrl: notification.actorAvatarUrl,
              size: 40,
              // The actor's id, not their display name. Scoping an image cache by name meant
              // two people called "Alex M." shared one cache entry — and a rename silently
              // invalidated an avatar that had not changed.
              cacheScope: notification.actorId,
            )
          : CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primarySoft,
              child: Icon(
                _iconFor(notification.type),
                size: 20,
                color: AppColors.primaryText,
              ),
            ),
      title: Text(
        notification.message,
        style: AppTypography.body.copyWith(
          fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
          color: AppColors.textDark,
          height: 1.35,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Which message the reaction was on — "reacted 👍 to your message" alone left the
            // reader guessing.
            if (notification.snippet != null && notification.snippet!.isNotEmpty)
              Text(
                '“${notification.snippet}”',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(color: AppColors.textMid),
              ),
            Text(
              _timeAgo(notification.createdAt),
              style: AppTypography.label.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
      trailing: unread
          ? Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }
}

IconData _iconFor(String type) => switch (type) {
  'group_invite' => Icons.mark_email_unread_outlined,
  'group_request_approved' => Icons.check_circle_outline_rounded,
  'group_request_rejected' => Icons.cancel_outlined,
  'group_made_admin' => Icons.shield_outlined,
  'group_removed_admin' => Icons.remove_moderator_outlined,
  'group_removed' => Icons.person_remove_outlined,
  'group_join_request' => Icons.group_add_outlined,
  'connection_request' => Icons.person_add_alt_1_outlined,
  'connection_accepted' => Icons.how_to_reg_outlined,
  'admin_membership_invited' => Icons.admin_panel_settings_outlined,
  'program_membership_verified' => Icons.workspace_premium_outlined,
  'scholar_profile_approved' => Icons.workspace_premium_outlined,
  'scholar_profile_changes_requested' => Icons.edit_note_outlined,
  'scholar_profile_revoked' => Icons.visibility_off_outlined,
  // Only reached when the actor has no avatar — a reaction row is actor-centric and
  // normally shows their face.
  'message_reaction' => Icons.emoji_emotions_outlined,
  _ => Icons.notifications_outlined,
};

String _timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time.toLocal());
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${(diff.inDays / 7).floor()}w ago';
}
