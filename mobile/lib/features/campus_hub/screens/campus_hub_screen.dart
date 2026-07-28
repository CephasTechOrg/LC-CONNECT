import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_shell_header.dart';
import '../../../shared/widgets/app_states.dart';
import '../../auth/providers/auth_provider.dart';
import '../../notifications/widgets/notifications_bell_button.dart';
import '../../profile/providers/profile_provider.dart';
import '../models/campus_post.dart';
import '../providers/campus_hub_provider.dart';
import '../providers/campus_publishing_provider.dart';

part '../widgets/urgent_update_banner.dart';
part '../widgets/campus_quick_action.dart';
part '../widgets/campus_post_card.dart';
part '../widgets/campus_hub_sections.dart';

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

String _greetingName({String? displayName, String? email}) {
  final fromProfile = displayName?.trim();
  if (fromProfile != null && fromProfile.isNotEmpty) {
    return fromProfile.split(RegExp(r'\s+')).first;
  }
  if (email == null || email.isEmpty) return 'there';
  final raw = email.split('@').first;
  if (raw.isEmpty) return 'there';
  return raw[0].toUpperCase() + raw.substring(1);
}

class CampusHubScreen extends ConsumerWidget {
  const CampusHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).asData?.value;
    final profile = ref.watch(myProfileNotifierProvider).asData?.value;
    final firstName = _greetingName(displayName: profile?.displayName, email: user?.email);
    final overviewAsync = ref.watch(campusHubOverviewProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => ref.invalidate(campusHubOverviewProvider),
          child: overviewAsync.when(
            loading: () => ListView(
              children: [
                AppShellHeader(
                  title: '${_greeting()}, $firstName',
                  subtitle: 'Campus Hub · Livingstone College',
                  showBottomBorder: false,
                  trailing: const NotificationsBellButton(),
                ),
                const SizedBox(height: 120),
                const Center(child: CircularProgressIndicator()),
              ],
            ),
            error: (_, _) => ListView(
              children: [
                AppShellHeader(
                  title: '${_greeting()}, $firstName',
                  subtitle: 'Campus Hub · Livingstone College',
                  showBottomBorder: false,
                  trailing: const NotificationsBellButton(),
                ),
                AppErrorState(
                  message: 'Could not load campus updates.',
                  onRetry: () => ref.invalidate(campusHubOverviewProvider),
                ),
              ],
            ),
            data: (overview) => ListView(
              children: [
                AppShellHeader(
                  title: '${_greeting()}, $firstName',
                  subtitle: 'Campus Hub · Livingstone College',
                  showBottomBorder: false,
                  trailing: const NotificationsBellButton(),
                ),
                if (overview.urgentPosts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  UrgentUpdateBanner(
                    post: overview.urgentPosts.first,
                    onTap: () => context.push('/home/posts/${overview.urgentPosts.first.id}'),
                  ),
                ],
                const SizedBox(height: 16),
                const _QuickActionsRow(),
                const _PublisherCta(),
                _SectionHeader(
                  title: 'Latest updates',
                  action: 'See all',
                  onAction: () => context.push('/home/updates'),
                ),
                if (overview.latestUpdates.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: AppEmptyState(
                      icon: Icons.campaign_outlined,
                      title: 'No updates yet',
                      subtitle: 'Official campus announcements will appear here.',
                    ),
                  )
                else
                  ...overview.latestUpdates.take(3).map(
                        (post) => CampusPostCard(
                          post: post,
                          onTap: () => context.push('/home/posts/${post.id}'),
                        ),
                      ),
                _SectionHeader(
                  title: 'Important deadlines',
                  action: overview.upcomingDeadlines.isNotEmpty ? 'See all' : null,
                  onAction: overview.upcomingDeadlines.isNotEmpty
                      ? () => context.push('/home/updates?kind=deadline')
                      : null,
                ),
                if (overview.upcomingDeadlines.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'No upcoming deadlines right now.',
                      style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMuted),
                    ),
                  )
                else
                  ...overview.upcomingDeadlines.take(3).map(
                        (post) => CampusPostCard(
                          post: post,
                          onTap: () => context.push('/home/posts/${post.id}'),
                        ),
                      ),
                _SectionHeader(
                  title: 'Campus life',
                  action: 'Activities',
                  onAction: () => context.go('/activities'),
                ),
                const _CampusLifeCta(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
