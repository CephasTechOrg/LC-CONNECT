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
          if (profile.campusVerified) ...[
            _InfoRow(
              icon: Icons.verified_user_outlined,
              iconColor: AppColors.primary,
              title: 'Verified student',
              subtitle: 'Your profile is verified by Livingstone College',
            ),
            _divider(),
          ],
          // Languages Spoken
          if (profile.languagesSpoken.isNotEmpty)
            _InfoRow(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Languages spoken',
              subtitle: profile.languagesSpoken.join(', '),
            ),
          if (profile.languagesSpoken.isNotEmpty) _divider(),
          // Learning
          if (profile.languagesLearning.isNotEmpty)
            _InfoRow(
              icon: Icons.menu_book_outlined,
              title: 'Learning',
              subtitle: profile.languagesLearning.join(', '),
            ),
          if (profile.languagesLearning.isNotEmpty) _divider(),
          // Interests
          if (profile.interests.isNotEmpty)
            _InfoRow(
              icon: Icons.favorite_border_rounded,
              title: 'Interests',
              subtitle: profile.interests.join(', '),
            ),
          // Looking for — a row like the others. It was a separate block of solid blue pills with
          // check marks: the loudest thing on the profile, for a list of preferences, and five
          // pills wrapped into three ragged rows.
          if (profile.lookingFor.isNotEmpty) ...[
            if (profile.interests.isNotEmpty) _divider(),
            _InfoRow(
              icon: Icons.people_outline_rounded,
              title: 'Looking for',
              subtitle: profile.lookingFor.join(', '),
            ),
          ],
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
  const _InfoRow({
    required this.icon,
    this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  // No trailing chevron: these rows are not tappable, and a chevron promised an action that
  // was not there.
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
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

