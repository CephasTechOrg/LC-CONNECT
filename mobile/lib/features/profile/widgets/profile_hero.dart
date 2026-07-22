part of '../screens/profile_screen.dart';

// ── Hero section ──────────────────────────────────────────────────
class _HeroSection extends StatelessWidget {
  final MyProfile profile;
  final bool uploading;
  final VoidCallback onAvatarTap;
  const _HeroSection({
    required this.profile,
    required this.uploading,
    required this.onAvatarTap,
  });

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
              GestureDetector(
                onTap: uploading ? null : onAvatarTap,
                child: Stack(
                  children: [
                    AvatarWidget(
                      imageUrl: profile.avatarUrl,
                      cacheScope: profile.userId,
                      size: 80,
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
                        child: uploading
                            ? const Padding(
                                padding: EdgeInsets.all(5),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.camera_alt_rounded,
                                color: Colors.white, size: 12),
                      ),
                    ),
                  ],
                ),
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
                        if (profile.isVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified_rounded,
                              color: AppColors.primary, size: 18),
                        ],
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

