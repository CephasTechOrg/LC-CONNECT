part of '../screens/campus_hub_screen.dart';

/// The one red surface on Home. Red is reserved for this, so it never has to compete with
/// routine content for attention.
class UrgentUpdateBanner extends StatelessWidget {
  final CampusPostSummary post;
  final VoidCallback onTap;

  const UrgentUpdateBanner({
    super.key,
    required this.post,
    required this.onTap,
  });

  static const _tint = Color(0xFFFFF1F2);
  static const _edge = Color(0xFFFECACA);

  /// Darker than [AppColors.error]: that red on this tint is ~3.5:1, under AA for 11px text.
  static const _alertText = AppColors.errorText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
        0,
      ),
      child: AppCard(
        onTap: onTap,
        color: _tint,
        borderColor: _edge,
        child: Row(
          children: [
            const AppIconTile(
              icon: Icons.warning_amber_rounded,
              color: AppColors.error,
              background: AppColors.surface,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Urgent campus alert',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _alertText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
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
