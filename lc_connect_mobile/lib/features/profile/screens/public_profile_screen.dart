import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../providers/profile_provider.dart';

class PublicProfileScreen extends ConsumerWidget {
  final String profileId;
  final String? preloadedName;

  const PublicProfileScreen({
    super.key,
    required this.profileId,
    this.preloadedName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(publicProfileProvider(profileId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        
        foregroundColor: AppColors.textDark,
        elevation: 0,
        title: Text(
          async.asData?.value.displayName ?? preloadedName ?? 'Profile',
          style: GoogleFonts.dmSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorBody(
          onRetry: () => ref.invalidate(publicProfileProvider(profileId)),
        ),
        data: (profile) => _PublicBody(profile: profile),
      ),
    );
  }
}

// ── Full scrollable body ──────────────────────────────────────────

class _PublicBody extends StatelessWidget {
  final PublicProfile profile;
  const _PublicBody({required this.profile});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _HeroCard(profile: profile),
        const SizedBox(height: 8),
        if (profile.languagesSpoken.isNotEmpty ||
            profile.languagesLearning.isNotEmpty ||
            profile.interests.isNotEmpty) ...[
          _InfoRows(profile: profile),
          const SizedBox(height: 8),
        ],
        if (profile.lookingFor.isNotEmpty) ...[
          _LookingForSection(lookingFor: profile.lookingFor),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Hero card ─────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final PublicProfile profile;
  const _HeroCard({required this.profile});

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
              AvatarWidget(imageUrl: profile.avatarUrl, size: 80),
              const SizedBox(width: 16),
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
                        if (profile.isVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified_rounded,
                              color: AppColors.primary, size: 18),
                        ],
                      ],
                    ),
                    if (profile.pronouns != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        profile.pronouns!,
                        style: GoogleFonts.dmSans(
                            fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                    if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        profile.bio!,
                        maxLines: 4,
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
          if (profile.major != null)
            _MetaRow(icon: Icons.school_outlined, text: profile.major!),
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
          ] else if (profile.countryState != null) ...[
            const SizedBox(height: 6),
            _MetaRow(
                icon: Icons.location_on_outlined, text: profile.countryState!),
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
          style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMid),
        ),
      ],
    );
  }
}

// ── Info rows ─────────────────────────────────────────────────────

class _InfoRows extends StatelessWidget {
  final PublicProfile profile;
  const _InfoRows({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          if (profile.languagesSpoken.isNotEmpty) ...[
            _InfoRow(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Languages Spoken',
              subtitle: profile.languagesSpoken.join(', '),
            ),
            _divider(),
          ],
          if (profile.languagesLearning.isNotEmpty) ...[
            _InfoRow(
              icon: Icons.menu_book_outlined,
              title: 'Learning',
              subtitle: profile.languagesLearning.join(', '),
            ),
            if (profile.interests.isNotEmpty) _divider(),
          ],
          if (profile.interests.isNotEmpty)
            _InfoRow(
              icon: Icons.favorite_border_rounded,
              title: 'Interests',
              subtitle: profile.interests.join(', '),
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
  final String title;
  final String subtitle;
  const _InfoRow(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textMuted),
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
                .map(
                  (label) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_rounded,
                            color: Colors.white, size: 13),
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
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorBody({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 48, color: AppColors.border),
          const SizedBox(height: 12),
          Text(
            'Could not load profile',
            style: GoogleFonts.dmSans(
                fontSize: 15, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onRetry,
            child: Text('Retry',
                style:
                    GoogleFonts.dmSans(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}
