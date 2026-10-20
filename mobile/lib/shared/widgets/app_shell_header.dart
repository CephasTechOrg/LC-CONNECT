import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// Standard tab/shell header: LC logo + title (+ optional subtitle) + trailing.
///
/// Sits directly on the page background, like the Home greeting header, so every tab opens
/// with the same top edge instead of Home floating and the rest in a white bordered bar.
class AppShellHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// Opt-in hairline for screens whose content scrolls directly under the header.
  final bool showBottomBorder;

  const AppShellHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.showBottomBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        border: showBottomBorder
            ? const Border(bottom: BorderSide(color: AppColors.border))
            : null,
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/images/lclogo.webp',
            width: 40,
            height: 40,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.display.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                    height: 1.15,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Notification bell with optional unread dot.
class AppBellIcon extends StatelessWidget {
  final int badgeCount;
  const AppBellIcon({super.key, this.badgeCount = 0});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.notifications_outlined,
            color: AppColors.textMuted, size: 22),
        if (badgeCount > 0)
          Positioned(
            top: -5,
            right: -6,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: badgeCount > 9 ? 4 : 0),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                badgeCount > 99 ? '99+' : '$badgeCount',
                style: GoogleFonts.dmSans(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
