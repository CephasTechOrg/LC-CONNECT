part of '../screens/connections_screen.dart';

class _Avatar extends StatelessWidget {
  final String? avatarUrl;
  const _Avatar({this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return AvatarWidget(imageUrl: avatarUrl, size: 48);
  }
}

/// The person on a request card: avatar, name with the verified mark, and one muted line.
/// Tapping it opens their profile — shared by the incoming and outgoing cards so the two tabs
/// line up row for row.
class _PersonRow extends StatelessWidget {
  final PartnerProfile? profile;
  final String meta;
  final Widget? trailing;
  const _PersonRow({required this.profile, required this.meta, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final trailing = this.trailing;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: p == null
                ? null
                : () => context.push('/users/${p.profileId}', extra: p.displayName),
            child: Row(
              children: [
                _Avatar(avatarUrl: p?.avatarUrl),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              p?.displayName ?? 'LC Student',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodyLarge.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                              ),
                            ),
                          ),
                          if (p?.campusVerified ?? false) ...[
                            const SizedBox(width: AppSpacing.xs),
                            const VerifiedBadge(size: 14),
                          ],
                        ],
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          trailing,
        ],
      ],
    );
  }
}

/// "Major · 3h ago" — the one muted line under a name. Either half may be missing.
String _metaLine(PartnerProfile? p, String age) =>
    [if (p?.major != null && p!.major!.isNotEmpty) p.major!, age].join(' · ');

/// What the sender asked for, in the same words the profile's "Looking for" uses.
///
/// Null for the plain "connect" intent: Discover sends it for every ordinary request, so a chip
/// saying "Wants to Connect" on a connection request told the reader nothing. The old map also
/// had no entry for `study_partner` or `friendship`, so those printed raw as
/// "Wants to study_partner".
String? _intentLabel(String? intent) => switch (intent) {
  null || '' || 'connect' => null,
  'study_partner' || 'study_together' => 'Study partner',
  'friendship' => 'Friendship',
  'language_exchange' => 'Language exchange',
  final other => _sentenceCase(other.replaceAll('_', ' ')),
};

String _sentenceCase(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';

IconData _intentIcon(String? intent) => switch (intent) {
  'study_partner' || 'study_together' => Icons.menu_book_outlined,
  'language_exchange' => Icons.language_outlined,
  'friendship' => Icons.people_outline,
  _ => Icons.link_rounded,
};

class _IntentChip extends StatelessWidget {
  final String intent;
  final String label;
  const _IntentChip({required this.intent, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: AppRadii.all(AppRadii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_intentIcon(intent), size: 14, color: AppColors.primaryText),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTypography.label.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Accept is the action (blue fill); Decline and Withdraw step back to a flat grey pill — the
/// same two treatments as every join and invite control in the app, on a 48dp target.
class _ActionButton extends StatelessWidget {
  final String label;
  final bool loading;
  final bool filled;
  final VoidCallback onTap;
  const _ActionButton({
    required this.label,
    required this.loading,
    required this.filled,
    required this.onTap,
  });

  static const _quietFill = Color(0xFFEEF2F6);

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? Colors.white : AppColors.textDark;
    return Semantics(
      container: true,
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: loading ? null : onTap,
        child: SizedBox(
          height: kMinInteractiveDimension,
          child: Center(
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: filled ? AppColors.primary : _quietFill,
                borderRadius: AppRadii.all(AppRadii.full),
              ),
              child: loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
                    )
                  : Text(
                      label,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color: foreground,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
