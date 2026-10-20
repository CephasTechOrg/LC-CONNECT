part of '../screens/discovery_screen.dart';

class _Avatar extends StatelessWidget {
  final String? avatarUrl;
  const _Avatar({this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return AvatarWidget(imageUrl: avatarUrl, size: 52);
  }
}

/// Looking-for chip — same label language as profile (“Study partner”), not “Wants …”.
class _LookingForBadge extends StatelessWidget {
  final String code;
  final String label;
  const _LookingForBadge({required this.code, required this.label});

  IconData get _icon => switch (code) {
    'study_partner' => Icons.menu_book_outlined,
    'friendship' => Icons.people_outline,
    'language_exchange' => Icons.language_outlined,
    'events' => Icons.event_outlined,
    _ => Icons.connect_without_contact_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 12, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// One brief interests + languages line for the list card.
///
/// Replaces the two stacked rows (interest chips, then a languages line) that
/// made every card four text rows tall. Caps mirror the old widgets - two
/// interests, two languages, overflow counted - and the full lists still live
/// on the public profile. [prioritizeLanguage] puts "Speaks ..." first because
/// for language-exchange seekers it is the reason to connect.
class _InterestLanguageLine extends StatelessWidget {
  final List<String> interests;
  final List<String> languages;
  final bool prioritizeLanguage;

  const _InterestLanguageLine({
    required this.interests,
    required this.languages,
    this.prioritizeLanguage = false,
  });

  @override
  Widget build(BuildContext context) {
    final visibleInterests = interests.take(2).join(' \u00b7 ');
    final interestOverflow = interests.length - 2;
    final interestText = interests.isEmpty
        ? null
        : (interestOverflow > 0
              ? '$visibleInterests \u00b7 +$interestOverflow'
              : visibleInterests);
    final visibleLanguages = languages.take(2).join(', ');
    final languageOverflow = languages.length - 2;
    final languageText = languages.isEmpty
        ? null
        : (languageOverflow > 0
              ? 'Speaks $visibleLanguages +$languageOverflow'
              : 'Speaks $visibleLanguages');
    final segments = prioritizeLanguage
        ? [languageText, interestText]
        : [interestText, languageText];
    final text = segments.whereType<String>().join('  \u00b7  ');
    if (text.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(
          prioritizeLanguage
              ? Icons.language_outlined
              : Icons.interests_outlined,
          size: 12,
          color: AppColors.textMuted,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(color: AppColors.textMid),
          ),
        ),
      ],
    );
  }
}

// ── Action button (Connect / Study Together) ───────────────────────
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isLoading;
  final VoidCallback onTap;

  /// Secondary actions (Study Together) get an outlined treatment so a card
  /// has exactly one filled primary — Connect. Two identical filled buttons
  /// made both read as "the" action and doubled the visual weight.
  final bool secondary;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.isLoading,
    required this.onTap,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = secondary ? AppColors.primary : Colors.white;
    return Semantics(
      button: true,
      enabled: !isLoading,
      label: label,
      child: Material(
        color: secondary
            ? AppColors.surface
            : (isLoading ? AppColors.primaryLight : AppColors.primary),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            // 48dp: the app's own minimum touch target. Was 40dp.
            height: kMinTouchTarget,
            alignment: Alignment.center,
            decoration: secondary
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary, width: 1.5),
                  )
                : null,
            child: isLoading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: foreground,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: foreground),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.label.copyWith(
                            color: foreground,
                          ),
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
