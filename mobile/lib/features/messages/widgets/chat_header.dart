part of '../screens/chat_screen.dart';

// ── Chat header ───────────────────────────────────────────────────
// Compact, identity-first: back • avatar • name • action. Tapping the avatar/name opens the
// partner's profile (DM) or the group's info screen (group); no separate identity card below.
class _ChatHeader extends StatelessWidget {
  final String title;
  /// Staff-thread context shown under the name, e.g. "Campus Safety Officer · Campus Security".
  final String? subtitle;
  final String? avatarUrl;
  final bool isGroup;
  /// DM only: shows the checkmark next to their name.
  final bool campusVerified;

  /// Tap the avatar/name → the partner's profile (DM) or the group detail screen (group).
  final VoidCallback? onIdentityTap;

  /// DM only: the ⋯ menu (report / block the partner).
  final VoidCallback? onMenu;

  /// DM only: the partner is typing — replaces the subtitle, so no separate strip is needed.
  final bool partnerTyping;

  const _ChatHeader({
    this.title = 'Messages',
    this.subtitle,
    this.avatarUrl,
    this.isGroup = false,
    this.campusVerified = false,
    this.onIdentityTap,
    this.onMenu,
    this.partnerTyping = false,
  });

  @override
  Widget build(BuildContext context) {
    final showTyping = partnerTyping && !isGroup;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          AppAccessibleIconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.textDark),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: InkWell(
              onTap: onIdentityTap,
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    _HeaderAvatar(url: avatarUrl, isGroup: isGroup),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.titleSmall.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ),
                              if (campusVerified) ...[
                                const SizedBox(width: 4),
                                const VerifiedBadge(size: 15),
                              ],
                            ],
                          ),
                          if (showTyping)
                            Text(
                              'typing…',
                              maxLines: 1,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.primaryText,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else if (subtitle != null)
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isGroup)
            AppAccessibleIconButton(
              tooltip: 'Group info',
              icon: const Icon(Icons.info_outline_rounded, size: 21, color: AppColors.textMid),
              onPressed: onIdentityTap,
            )
          else if (onMenu != null)
            AppAccessibleIconButton(
              tooltip: 'More options',
              icon: const Icon(Icons.more_horiz_rounded, size: 22, color: AppColors.textMid),
              onPressed: onMenu,
            )
          else
            const SizedBox(width: AppSpacing.sm),
        ],
      ),
    );
  }
}

/// The header avatar — the partner's photo (DM) or the group's photo, each with the right
/// fallback icon (person vs group) instead of a generic placeholder.
class _HeaderAvatar extends StatelessWidget {
  final String? url;
  final bool isGroup;
  const _HeaderAvatar({this.url, this.isGroup = false});

  @override
  Widget build(BuildContext context) {
    if (!isGroup) return AvatarWidget(imageUrl: url, size: 38);
    return Container(
      width: 38,
      height: 38,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
      child: url != null
          ? CachedNetworkImage(
              imageUrl: url!,
              width: 38,
              height: 38,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) =>
                  const Icon(Icons.groups_outlined, size: 20, color: AppColors.primary))
          : const Icon(Icons.groups_outlined, size: 20, color: AppColors.primary),
    );
  }
}
