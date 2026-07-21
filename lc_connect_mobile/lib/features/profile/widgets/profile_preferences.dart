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
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              Text(
                'Edit',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: AppColors.primary,
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
        ],
      ),
    );
  }
}

class _PrefToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _PrefToggle({
    required this.icon,
    required this.label,
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
          child: Text(
            label,
            style: GoogleFonts.dmSans(
                fontSize: 13, color: AppColors.textMid),
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

