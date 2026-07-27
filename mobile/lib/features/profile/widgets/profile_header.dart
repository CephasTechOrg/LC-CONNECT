part of '../screens/profile_screen.dart';

// ── Header bar ────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final WidgetRef ref;
  const _Header({required this.ref});

  @override
  Widget build(BuildContext context) {
    return AppShellHeader(
      title: 'Profile',
      trailing: IconButton(
        icon: const Icon(Icons.settings_outlined,
            color: AppColors.textMuted, size: 22),
        onPressed: () => _showSettings(context, ref),
      ),
    );
  }

  void _showSettings(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Settings',
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: AppColors.textMid),
                title: Text('Edit Profile', style: GoogleFonts.dmSans(color: AppColors.textDark, fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.border),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/profile/edit');
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock_reset_rounded, color: AppColors.textMid),
                title: Text('Reset Password', style: GoogleFonts.dmSans(color: AppColors.textDark, fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.border),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/forgot-password');
                },
              ),
              ListTile(
                leading: const Icon(Icons.notifications_outlined, color: AppColors.textMid),
                title: Text('Notifications', style: GoogleFonts.dmSans(color: AppColors.textDark, fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.border),
                onTap: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notifications settings coming soon')));
                },
              ),
              ListTile(
                leading: const Icon(Icons.shield_outlined, color: AppColors.textMid),
                title: Text('Privacy Policy', style: GoogleFonts.dmSans(color: AppColors.textDark, fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.border),
                onTap: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Privacy policy coming soon')));
                },
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined, color: AppColors.textMid),
                title: Text('Terms of Service', style: GoogleFonts.dmSans(color: AppColors.textDark, fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.border),
                onTap: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Terms of service coming soon')));
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined, color: AppColors.error),
                title: Text(
                  'Delete account',
                  style: GoogleFonts.dmSans(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _showDeleteAccountFlow(context, ref);
                },
              ),
              const Divider(color: AppColors.border, indent: 20, endIndent: 20),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: AppColors.error),
                title: Text(
                  'Sign out',
                  style: GoogleFonts.dmSans(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  ref.invalidate(myProfileNotifierProvider);
                  await ref.read(authNotifierProvider.notifier).logout();
                  if (context.mounted) context.go('/login');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

