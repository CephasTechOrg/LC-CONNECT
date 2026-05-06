import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/profile_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myProfileNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorState(
            onRetry: () => ref.invalidate(myProfileNotifierProvider),
          ),
          data: (profile) => _ProfileBody(profile: profile),
        ),
      ),
    );
  }
}

// ── Full scrollable body ──────────────────────────────────────────
class _ProfileBody extends ConsumerWidget {
  final MyProfile profile;
  const _ProfileBody({required this.profile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        _Header(ref: ref),
        _HeroSection(profile: profile),
        const SizedBox(height: 8),
        _InfoRows(profile: profile),
        const SizedBox(height: 8),
        _LookingForSection(lookingFor: profile.lookingFor),
        const SizedBox(height: 8),
        _PreferencesCard(profile: profile),
        const SizedBox(height: 8),
        _StatsRow(profile: profile),
        const SizedBox(height: 16),
        _EditProfileButton(),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Header bar ────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final WidgetRef ref;
  const _Header({required this.ref});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 14),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              'LC',
              style: GoogleFonts.dmSans(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'LC Connect',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                color: AppColors.textMuted, size: 22),
            onPressed: () => _showSettings(context, ref),
          ),
        ],
      ),
    );
  }

  void _showSettings(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
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
            ListTile(
              leading: const Icon(Icons.logout_rounded,
                  color: AppColors.error),
              title: Text(
                'Sign out',
                style: GoogleFonts.dmSans(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await ref.read(authNotifierProvider.notifier).logout();
                if (context.mounted) context.go('/login');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Hero section ──────────────────────────────────────────────────
class _HeroSection extends StatelessWidget {
  final MyProfile profile;
  const _HeroSection({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              Stack(
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 80,
                      height: 80,
                      child: Image.asset(
                        'assets/images/headshots.png',
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.camera_alt_rounded,
                          color: Colors.white, size: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // Name + bio
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.displayName ?? 'LC Student',
                            style: GoogleFonts.dmSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.verified_rounded,
                            color: AppColors.primary, size: 18),
                      ],
                    ),
                    if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        profile.bio!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Meta rows
          if (profile.major != null)
            _MetaRow(
                icon: Icons.school_outlined, text: profile.major!),
          if (profile.classYear != null) ...[
            const SizedBox(height: 6),
            _MetaRow(
              icon: Icons.calendar_today_outlined,
              text: 'Class of ${profile.classYear}',
            ),
          ],
          if (profile.campus != null) ...[
            const SizedBox(height: 6),
            _MetaRow(
                icon: Icons.location_on_outlined, text: profile.campus!),
          ],
          if (profile.countryState != null &&
              profile.campus == null) ...[
            const SizedBox(height: 6),
            _MetaRow(
                icon: Icons.location_on_outlined,
                text: profile.countryState!),
          ],
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.textMuted),
        const SizedBox(width: 7),
        Text(
          text,
          style: GoogleFonts.dmSans(
              fontSize: 13, color: AppColors.textMid),
        ),
      ],
    );
  }
}

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
          _InfoRow(
            icon: Icons.verified_user_outlined,
            iconColor: AppColors.primary,
            title: 'Verified Student',
            subtitle: 'Your profile is verified by Livingstone College',
            showChevron: true,
          ),
          _divider(),
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

// ── Looking For section ───────────────────────────────────────────
class _LookingForSection extends StatelessWidget {
  final List<String> lookingFor;
  const _LookingForSection({required this.lookingFor});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_outline_rounded,
                  size: 20, color: AppColors.textMuted),
              const SizedBox(width: 14),
              Text(
                'Looking For',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: lookingFor
                .map((label) => _LookingForChip(label: label))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _LookingForChip extends StatelessWidget {
  final String label;
  const _LookingForChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, color: Colors.white, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

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

// ── Stats row ─────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final MyProfile profile;
  const _StatsRow({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          _StatItem(count: profile.connectionCount, label: 'Connections'),
          _StatDivider(),
          _StatItem(count: profile.activityCount, label: 'Joined Activities'),
          _StatDivider(),
          _StatItem(count: profile.messageCount, label: 'Messages'),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final int count;
  final String label;
  const _StatItem({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$count',
            style: GoogleFonts.dmSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
                fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: AppColors.border,
    );
  }
}

// ── Edit Profile button ───────────────────────────────────────────
class _EditProfileButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Edit profile coming soon!')),
            );
          },
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(
            'Edit Profile',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline,
              size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            'Couldn\'t load your profile',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onRetry,
            child: Text(
              'Retry',
              style: GoogleFonts.dmSans(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
