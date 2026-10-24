part of '../screens/campus_hub_screen.dart';

class _QuickActionsRow extends ConsumerWidget {
  const _QuickActionsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opportunityNew = ref.watch(opportunityNewCountProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.lg,
        AppSpacing.gutter,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CampusQuickAction(
            icon: Icons.badge_outlined,
            label: 'Directory',
            onTap: () => context.push('/home/directory'),
          ),
          CampusQuickAction(
            icon: Icons.menu_book_outlined,
            label: 'Resources',
            onTap: () => context.push('/home/resources'),
          ),
          CampusQuickAction(
            icon: Icons.work_outline,
            label: 'Opportunities',
            badgeCount: opportunityNew,
            onTap: () => context.push('/home/opportunities'),
          ),
        ],
      ),
    );
  }
}

/// A one-line empty state for a dashboard section — a muted icon + line, never the full-screen
/// AppEmptyState (which would swallow the whole dashboard when a section is quiet).
class _SectionEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SectionEmpty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.pagePadding,
      child: AppCard(
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textMuted),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one heading every Home section uses — Latest updates, Upcoming activities, Suggested
/// connections. They used to be three different things: a white 16px title inside a navy panel,
/// a 16px title inside a bordered row when empty, and this 18px header. Same job, same look.
///
/// Owns the gap *above* a section (24dp — wider than any gap inside one), so sections read as
/// groups by proximity rather than needing boxes around them.
class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onAction;

  /// "New since you last looked" — shown as a pill after the action label.
  final int newCount;

  const _SectionHeader({
    required this.title,
    required this.onAction,
    this.newCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      // The 48dp action target pads the row vertically, so the visible gap above the title is
      // ~28dp and below it ~12dp — more space between sections than within one.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.lg,
        AppSpacing.sm,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            // `container` on both: without it the header and the action merge into one node,
            // announced as a header *and* a button with both labels run together.
            child: Semantics(
              container: true,
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.title.copyWith(color: AppColors.textDark),
              ),
            ),
          ),
          _SectionAction(
            label: 'See all',
            title: title,
            newCount: newCount,
            onTap: onAction,
          ),
        ],
      ),
    );
  }
}

class _SectionAction extends StatelessWidget {
  final String label;
  final String title;
  final int newCount;
  final VoidCallback onTap;

  const _SectionAction({
    required this.label,
    required this.title,
    required this.newCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final semantics = newCount > 0
        ? '$label ${title.toLowerCase()}, $newCount new'
        : '$label ${title.toLowerCase()}';
    return Semantics(
      container: true,
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(AppRadii.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (newCount > 0) ...[
                  _NewPill(count: newCount),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Text(
                  label,
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "3 new" in a soft brand pill. Brand, not error red: unread announcements are news, not a
/// problem — red is kept for the things that are (urgent alerts, failed sends).
class _NewPill extends StatelessWidget {
  final int count;
  const _NewPill({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: AppRadii.all(AppRadii.full),
      ),
      child: Text(
        '${count > 99 ? '99+' : count} new',
        style: AppTypography.caption.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

/// Staff/publisher shortcut. Sits with the quick actions it belongs to — it *is* an action —
/// rather than between two content sections.
class _PublisherCta extends ConsumerWidget {
  const _PublisherCta();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(publishingCapabilitiesProvider).asData?.value;
    if (caps == null || !caps.canPublish) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        0,
      ),
      child: AppCard(
        onTap: () => context.push('/home/my-posts'),
        child: Row(
          children: [
            const AppIconTile(icon: Icons.edit_note_outlined),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Publish to campus',
                    style: AppTypography.titleSmall.copyWith(
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Create updates and opportunities. Manage your posts.',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
