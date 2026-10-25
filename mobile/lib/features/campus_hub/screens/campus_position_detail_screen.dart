import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_states.dart';
import '../../auth/providers/auth_provider.dart';
import '../../messages/providers/messages_provider.dart';
import '../../messages/providers/staff_messaging_provider.dart';
import '../providers/campus_directory_provider.dart';
import '../widgets/campus_subpage_header.dart';
import '../../messages/utils/chat_routes.dart';
import '../../../shared/widgets/app_skeleton.dart';

class CampusPositionDetailScreen extends ConsumerStatefulWidget {
  final String positionId;

  const CampusPositionDetailScreen({super.key, required this.positionId});

  @override
  ConsumerState<CampusPositionDetailScreen> createState() => _CampusPositionDetailScreenState();
}

class _CampusPositionDetailScreenState extends ConsumerState<CampusPositionDetailScreen> {
  bool _messaging = false;

  Future<void> _launch(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open $uri');
    }
  }

  Future<void> _message(DirectoryEntry entry) async {
    if (_messaging) return;
    setState(() => _messaging = true);
    try {
      final thread = await ref.read(staffMessagingServiceProvider).startThread(entry.userId);
      ref.read(threadsNotifierProvider.notifier).upsertThread(thread);
      if (!mounted) return;
      // This detail route lives outside the shell navigator, so enter the messages branch with
      // `go` to avoid cross-navigator push locking during transition.
      context.go(dmChatPath(thread.addressingId), extra: thread);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Couldn't start that conversation"),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _messaging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entryAsync = ref.watch(campusDirectoryEntryProvider(widget.positionId));
    final myId = ref.watch(authNotifierProvider).asData?.value?.id;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: entryAsync.when(
          loading: () => const AppProfileSkeleton(),
          error: (_, _) => Column(
            children: [
              CampusSubpageHeader(title: 'Contact', onBack: () => context.pop()),
              Expanded(
                child: AppErrorState(
                  message: 'Could not load this directory entry.',
                  onRetry: () => ref.invalidate(campusDirectoryEntryProvider(widget.positionId)),
                ),
              ),
            ],
          ),
          data: (entry) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CampusSubpageHeader(title: 'Contact', onBack: () => context.pop()),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.sm,
                    AppSpacing.gutter,
                    AppSpacing.xxl,
                  ),
                  children: [
                    Row(
                      children: [
                        AvatarWidget(imageUrl: entry.avatarUrl, size: 64, cacheScope: entry.userId),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.displayName ?? entry.officialTitle,
                                style: AppTypography.title.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textDark,
                                ),
                              ),
                              Text(
                                entry.officialTitle,
                                style: AppTypography.body.copyWith(color: AppColors.textMid),
                              ),
                              Text(
                                entry.department,
                                style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (myId != entry.userId)
                      // The theme's pill, like every other primary action.
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _messaging ? null : () => _message(entry),
                          icon: _messaging
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 18,
                                  color: Colors.white,
                                ),
                          label: const Text('Message'),
                        ),
                      ),
                    if (entry.bio != null && entry.bio!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxl),
                      const _SectionHeading('About'),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        entry.bio!,
                        style: AppTypography.body.copyWith(
                          height: 1.45,
                          color: AppColors.textMid,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xxl),
                    const _SectionHeading('Contact'),
                    const SizedBox(height: AppSpacing.sm),
                    _ContactCard(rows: [
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
                    ]),
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

class _SectionHeading extends StatelessWidget {
  final String text;
  const _SectionHeading(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppTypography.titleSmall.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.textDark,
        ),
      );
}

/// All the ways to reach this person in one card, split by hairlines — not one outlined box per
/// row, which read as four separate buttons.
class _ContactCard extends StatelessWidget {
  final List<Widget> rows;
  const _ContactCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                color: AppColors.border,
                indent: AppSpacing.lg + 20 + AppSpacing.md,
              ),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _ContactAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _ContactAction({required this.icon, required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primaryText, size: 20),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.label.copyWith(
                    fontWeight: FontWeight.w400,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  value,
                  style: AppTypography.body.copyWith(
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
    final tap = onTap;
    return tap == null ? row : InkWell(onTap: tap, child: row);
  }
}
