import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../shared/widgets/app_states.dart';
import '../providers/campus_directory_provider.dart';

class CampusPositionDetailScreen extends ConsumerWidget {
  final String positionId;

  const CampusPositionDetailScreen({super.key, required this.positionId});

  Future<void> _launch(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open $uri');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entryAsync = ref.watch(campusDirectoryEntryProvider(positionId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: entryAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Column(
            children: [
              _DetailHeader(onBack: () => context.pop()),
              Expanded(
                child: AppErrorState(
                  message: 'Could not load this directory entry.',
                  onRetry: () => ref.invalidate(campusDirectoryEntryProvider(positionId)),
                ),
              ),
            ],
          ),
          data: (entry) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailHeader(onBack: () => context.pop()),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    Row(
                      children: [
                        AvatarWidget(
                          imageUrl: entry.avatarUrl,
                          size: 64,
                          cacheScope: entry.userId,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.displayName ?? entry.officialTitle,
                                style: GoogleFonts.dmSans(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textDark,
                                ),
                              ),
                              Text(
                                entry.officialTitle,
                                style: GoogleFonts.dmSans(
                                  fontSize: 14,
                                  color: AppColors.textMid,
                                ),
                              ),
                              Text(
                                entry.department,
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (entry.bio != null && entry.bio!.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        'About',
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        entry.bio!,
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          height: 1.45,
                          color: AppColors.textMid,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      'Contact',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ContactAction(
                      icon: Icons.email_outlined,
                      label: 'Email',
                      value: entry.contactEmail,
                      onTap: () => _launch(Uri(scheme: 'mailto', path: entry.contactEmail)),
                    ),
                    if (entry.phone != null && entry.phone!.isNotEmpty)
                      _ContactAction(
                        icon: Icons.phone_outlined,
                        label: 'Phone',
                        value: entry.phone!,
                        onTap: () => _launch(Uri(scheme: 'tel', path: entry.phone)),
                      ),
                    if (entry.officeLocation != null && entry.officeLocation!.isNotEmpty)
                      _ContactAction(
                        icon: Icons.location_on_outlined,
                        label: 'Office',
                        value: entry.officeLocation!,
                      ),
                    if (entry.availability != null && entry.availability!.isNotEmpty)
                      _ContactAction(
                        icon: Icons.schedule_outlined,
                        label: 'Hours',
                        value: entry.availability!,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _ContactAction({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            const Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.textMuted),
        ],
      ),
    );

    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: child,
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  final VoidCallback onBack;

  const _DetailHeader({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: onBack,
          ),
          Text(
            'Contact',
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}
