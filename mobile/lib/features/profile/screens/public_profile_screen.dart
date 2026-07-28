import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../auth/providers/auth_provider.dart';
import '../../discovery/providers/discovery_provider.dart';
import '../../messages/providers/messages_provider.dart';
import '../../messages/providers/staff_messaging_provider.dart';
import '../providers/profile_provider.dart';

part '../widgets/public_profile_staff.dart';

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
    final myUserId = ref.watch(authNotifierProvider).asData?.value?.id;

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
        data: (profile) => _PublicBody(
          profile: profile,
          isSelf: myUserId != null && myUserId == profile.userId,
        ),
      ),
    );
  }
}

// ── Full scrollable body ──────────────────────────────────────────

class _PublicBody extends ConsumerStatefulWidget {
  final PublicProfile profile;
  final bool isSelf;
  const _PublicBody({required this.profile, required this.isSelf});

  @override
  ConsumerState<_PublicBody> createState() => _PublicBodyState();
}

class _PublicBodyState extends ConsumerState<_PublicBody> {
  bool _connecting = false;
  bool _requestSent = false;
  bool _messaging = false;

  /// Start (or open) a direct thread with this staff member. A student may message staff because
  /// the staff side is a verified campus position — the backend allows it either way.
  Future<void> _message() async {
    if (_messaging) return;
    setState(() => _messaging = true);
    try {
      final thread =
          await ref.read(staffMessagingServiceProvider).startThread(widget.profile.userId);
      ref.read(threadsNotifierProvider.notifier).upsertThread(thread);
      if (!mounted) return;
      context.push('/messages/${thread.addressingId}', extra: thread);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Couldn't start that conversation", style: GoogleFonts.dmSans()),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _messaging = false);
    }
  }

  Future<void> _connect() async {
    if (_connecting || _requestSent) return;
    setState(() => _connecting = true);
    try {
      await ref.read(discoveryNotifierProvider.notifier).connect(
            widget.profile.userId,
            widget.profile.profileId,
            'connect',
          );
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _requestSent = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Connection request sent',
            style: GoogleFonts.dmSans(),
          ),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _connecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not send request — please try again',
            style: GoogleFonts.dmSans(),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final isStaff = profile.isStaff;
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              _HeroCard(profile: profile),
              const SizedBox(height: 8),
              // Staff: a clean contact block (email / office / availability).
              if (isStaff) ...[
                _StaffContactSection(profile: profile),
                const SizedBox(height: 8),
              ],
              if (profile.languagesSpoken.isNotEmpty ||
                  profile.languagesLearning.isNotEmpty ||
                  profile.interests.isNotEmpty) ...[
                _InfoRows(profile: profile),
                const SizedBox(height: 8),
              ],
              // "Looking for" is student matching intent — never shown for staff.
              if (!isStaff && profile.lookingFor.isNotEmpty) ...[
                _LookingForSection(lookingFor: profile.lookingFor),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
        if (!widget.isSelf)
          isStaff
              ? _StaffMessageBar(loading: _messaging, onMessage: _message)
              : _ConnectBar(
                  loading: _connecting,
                  sent: _requestSent,
                  onConnect: _connect,
                ),
      ],
    );
  }
}

class _ConnectBar extends StatelessWidget {
  final bool loading;
  final bool sent;
  final VoidCallback onConnect;
  const _ConnectBar({
    required this.loading,
    required this.sent,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          onPressed: sent || loading ? null : onConnect,
          icon: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  sent ? Icons.check_rounded : Icons.person_add_alt_1,
                  size: 18,
                ),
          label: Text(
            sent ? 'Request sent' : 'Connect',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: sent ? AppColors.green : AppColors.primary,
            disabledBackgroundColor:
                sent ? AppColors.green : AppColors.primary.withValues(alpha: 0.6),
            disabledForegroundColor: Colors.white,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        ),
      ),
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
          // Staff show their role; students show major + class year.
          if (profile.isStaff) ...[
            if (profile.positionTitle != null)
              _MetaRow(icon: Icons.badge_outlined, text: profile.positionTitle!),
            if (profile.positionDepartment != null) ...[
              const SizedBox(height: 6),
              _MetaRow(icon: Icons.apartment_outlined, text: profile.positionDepartment!),
            ],
          ] else ...[
            if (profile.major != null)
              _MetaRow(icon: Icons.school_outlined, text: profile.major!),
            if (profile.classYear != null) ...[
              const SizedBox(height: 6),
              _MetaRow(
                icon: Icons.calendar_today_outlined,
                text: 'Class of ${profile.classYear}',
              ),
            ],
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
