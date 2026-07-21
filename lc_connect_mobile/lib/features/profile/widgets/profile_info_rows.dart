part of '../screens/profile_screen.dart';

// ── Info rows ─────────────────────────────────────────────────────
class _InfoRows extends StatelessWidget {
  final MyProfile profile;
  const _InfoRows({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          // Verified Student
          if (profile.isVerified) ...[
            _InfoRow(
              icon: Icons.verified_user_outlined,
              iconColor: AppColors.primary,
              title: 'Verified Student',
              subtitle: 'Your profile is verified by Livingstone College',
              showChevron: true,
            ),
            _divider(),
          ],
          // Languages Spoken
          if (profile.languagesSpoken.isNotEmpty)
            _InfoRow(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Languages Spoken',
              subtitle: profile.languagesSpoken.join(', '),
              showChevron: true,
            ),
          if (profile.languagesSpoken.isNotEmpty) _divider(),
          // Learning
          if (profile.languagesLearning.isNotEmpty)
            _InfoRow(
              icon: Icons.menu_book_outlined,
              title: 'Learning',
              subtitle: profile.languagesLearning.join(', '),
              showChevron: true,
            ),
          if (profile.languagesLearning.isNotEmpty) _divider(),
          // Interests
          if (profile.interests.isNotEmpty)
            _InfoRow(
              icon: Icons.favorite_border_rounded,
              title: 'Interests',
              subtitle: profile.interests.join(', '),
              showChevron: true,
            ),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(
        height: 1,
        indent: 52,
        endIndent: 20,
        color: AppColors.border,
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final bool showChevron;
  const _InfoRow({
    required this.icon,
    this.iconColor,
    required this.title,
    required this.subtitle,
    this.showChevron = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Icon(icon,
              size: 20, color: iconColor ?? AppColors.textMuted),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          if (showChevron)
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.border),
        ],
      ),
    );
  }
}

