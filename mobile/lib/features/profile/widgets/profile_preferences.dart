part of '../screens/profile_screen.dart';

// ── Preferences card ──────────────────────────────────────────────
class _PreferencesCard extends ConsumerWidget {
  final MyProfile profile;
  const _PreferencesCard({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Preferences',
                style: AppTypography.bodyLarge.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              Text(
                'Edit',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.primaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PrefToggle(
            icon: Icons.lock_outline_rounded,
            label: 'Only mutual matches can message me',
            value: profile.allowMessagesFromMatchesOnly,
            onChanged: (v) => ref
                .read(myProfileNotifierProvider.notifier)
                .updatePreference(allowMessagesFromMatchesOnly: v),
          ),
          const SizedBox(height: 12),
          _PrefToggle(
            icon: Icons.verified_outlined,
            label: 'Show my profile to verified students only',
            value: profile.showProfileToVerifiedOnly,
            onChanged: (v) => ref
                .read(myProfileNotifierProvider.notifier)
                .updatePreference(showProfileToVerifiedOnly: v),
          ),
          const SizedBox(height: 12),
          _PrefToggle(
            icon: Icons.circle_outlined,
            label: 'Show online status & last seen',
            hint: "If you turn this off, you won't see other people's either.",
            value: profile.showPresence,
            onChanged: (v) => ref
                .read(myProfileNotifierProvider.notifier)
                .updatePreference(showPresence: v),
          ),
        ],
      ),
    );
  }
}

class _PrefToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _PrefToggle({
    required this.icon,
    required this.label,
    this.hint,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.textMuted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.bodySmall.copyWith(color: AppColors.textMid),
              ),
              if (hint != null)
                Text(
                  hint!,
                  style: AppTypography.label.copyWith(
                      fontWeight: FontWeight.w400, color: AppColors.textMuted),
                ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.primary,
          activeTrackColor: AppColors.primarySoft,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }
}

