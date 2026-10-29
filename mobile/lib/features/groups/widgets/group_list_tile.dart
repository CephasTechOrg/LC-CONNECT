import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_card.dart';
import '../data/group_models.dart';

String _members(int n) => n == 1 ? '1 member' : '$n members';

IconData _iconFor(String category) => switch (category) {
  'housing' => Icons.home_outlined,
  'class' => Icons.school_outlined,
  'club' => Icons.groups_outlined,
  _ => Icons.favorite_border_rounded,
};

/// A Discover row: the group, what kind it is, how big, and the join control.
class GroupListTile extends StatelessWidget {
  final GroupSummary group;
  final bool busy;
  final VoidCallback onAction;
  final VoidCallback? onOpen;
  const GroupListTile({
    super.key,
    required this.group,
    required this.busy,
    required this.onAction,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    // The shared card surface (borderless, soft shadow), same as Home and Activities.
    return AppCard(
      onTap: group.isMember ? onOpen : null, // members tap to open the group chat
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: AppRadii.all(AppRadii.lg),
            ),
            alignment: Alignment.center,
            clipBehavior: Clip.antiAlias,
            child: group.avatarUrl != null
                ? CachedNetworkImage(
                    imageUrl: group.avatarUrl!,
                    fit: BoxFit.cover,
                    width: 44,
                    height: 44,
                    errorWidget: (_, _, _) =>
                        Icon(_iconFor(group.category), size: 20, color: AppColors.primaryText),
                  )
                : Icon(_iconFor(group.category), size: 20, color: AppColors.primaryText),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${groupCategoryLabel(group.category)} · ${_members(group.memberCount)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          _GroupActionBtn(
            label: group.actionLabel,
            enabled: group.actionEnabled,
            joined: group.isMember,
            busy: busy,
            groupName: group.name,
            onTap: onAction,
          ),
        ],
      ),
    );
  }
}

/// The join control on a group row, on the same rule as the Activities RSVP pill: a blue fill
/// when there is something to do (Join, Request), soft blue once you are in (Joined), flat grey
/// when there is nothing to do (Pending, Invite only). It used to be five treatments — a filled
/// button, a blue outline, and three grey outlines — for one control.
class _GroupActionBtn extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool joined;
  final bool busy;
  final String groupName;
  final VoidCallback onTap;
  const _GroupActionBtn({
    required this.label,
    required this.enabled,
    required this.joined,
    required this.busy,
    required this.groupName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = enabled
        ? (AppColors.primary, Colors.white)
        : joined
            ? (AppColors.primarySoft, AppColors.primaryText)
            : (AppColors.quiet, AppColors.textMuted);

    return Semantics(
      container: true,
      button: enabled,
      enabled: enabled,
      label: enabled ? '$label $groupName' : '$groupName: $label',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled && !busy ? onTap : null,
        // 48dp tall target around a 34dp pill.
        child: SizedBox(
          height: kMinInteractiveDimension,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 2),
              decoration: BoxDecoration(
                color: background,
                borderRadius: AppRadii.all(AppRadii.full),
              ),
              alignment: Alignment.center,
              child: busy
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (joined) ...[
                          Icon(Icons.check_rounded, size: 15, color: foreground),
                          const SizedBox(width: AppSpacing.xs),
                        ],
                        Text(
                          label,
                          style: AppTypography.bodySmall.copyWith(
                            fontWeight: FontWeight.w700,
                            color: foreground,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
