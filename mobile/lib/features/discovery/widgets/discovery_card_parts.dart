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
            style: GoogleFonts.dmSans(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Interest chips — max 2 + overflow; full list on the public profile.
class _InterestChips extends StatelessWidget {
  final List<String> interests;
  const _InterestChips({required this.interests});

  @override
  Widget build(BuildContext context) {
    final visible = interests.take(2).toList();
    final overflow = interests.length - visible.length;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ...visible.map((name) => Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                name,
                style: GoogleFonts.dmSans(
                    fontSize: 11.5, color: AppColors.textMid),
              ),
            )),
        if (overflow > 0)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              '+$overflow',
              style: GoogleFonts.dmSans(
                  fontSize: 11.5, color: AppColors.textMuted),
            ),
          ),
      ],
    );
  }
}

/// Cap spoken languages at two on the list card.
class _LanguageLine extends StatelessWidget {
  final List<String> languages;
  const _LanguageLine({required this.languages});

  @override
  Widget build(BuildContext context) {
    final visible = languages.take(2).toList();
    final overflow = languages.length - visible.length;
    final text = overflow > 0
        ? 'Speaks ${visible.join(', ')} +$overflow'
        : 'Speaks ${visible.join(', ')}';
    return Row(
      children: [
        const Icon(Icons.language_outlined,
            size: 12, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.dmSans(
                fontSize: 11.5, color: AppColors.textMuted),
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

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !isLoading,
      label: label,
      child: Material(
        color: isLoading ? AppColors.primaryLight : AppColors.primary,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            child: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 14, color: Colors.white),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        style: GoogleFonts.dmSans(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
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
