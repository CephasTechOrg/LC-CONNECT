part of '../screens/campus_hub_screen.dart';

/// A Home shortcut: a soft tinted tile with the label underneath, no card around it.
///
/// The bordered card that used to wrap each action made three boxes compete with the spotlight
/// directly above them. The tile alone carries the affordance; the whole column is the target.
class CampusQuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Optional "new" count — used by Opportunities (separate from Latest Updates announcements).
  final int badgeCount;

  const CampusQuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeCount = 0,
  });

  static const _tileSize = 56.0;

  @override
  Widget build(BuildContext context) {
    final badge = badgeCount > 99 ? '99+' : '$badgeCount';
    return Expanded(
      child: Semantics(
        button: true,
        label: badgeCount > 0 ? '$label, $badgeCount new' : label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.xl),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: _tileSize,
                  height: _tileSize,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: _tileSize,
                        height: _tileSize,
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(AppRadii.xl),
                        ),
                        child: Icon(icon, color: AppColors.primary, size: 24),
                      ),
                      if (badgeCount > 0)
                        Positioned(
                          top: -6,
                          right: -6,
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 20,
                              minHeight: 20,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              borderRadius: BorderRadius.circular(AppRadii.full),
                              border: Border.all(color: AppColors.background, width: 2),
                            ),
                            child: Text(
                              badge,
                              style: AppTypography.micro.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                // Scale down rather than ellipsize: at 320dp each column is ~90dp wide and
                // "Opportunities" does not fit at full size — a clipped label is worse than a
                // slightly smaller whole word.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: AppTypography.label.copyWith(color: AppColors.textMid),
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
