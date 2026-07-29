import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../shared/widgets/app_states.dart';
import '../../activities/providers/activities_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../discovery/providers/discovery_provider.dart';
import '../../notifications/providers/notifications_provider.dart';
import '../../profile/providers/profile_provider.dart';
import '../data/campus_spotlights.dart';
import '../models/campus_post.dart';
import '../providers/campus_hub_provider.dart';
import '../providers/campus_publishing_provider.dart';

part '../widgets/urgent_update_banner.dart';
part '../widgets/campus_home_header.dart';
part '../widgets/campus_spotlight_carousel.dart';
part '../widgets/campus_quick_action.dart';
part '../widgets/campus_hub_sections.dart';
part '../widgets/campus_updates_panel.dart';
part '../widgets/campus_home_previews.dart';

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
    final isStudent = (user?.role ?? 'student') == 'student';
    final firstName = _greetingName(displayName: profile?.displayName, email: user?.email);
    final greeting = '${_greeting()}, $firstName';
    final overviewAsync = ref.watch(campusHubOverviewProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async => ref.invalidate(campusHubOverviewProvider),
          child: ListView(
            children: [
              _HomeGreetingHeader(greeting: greeting),
              const SizedBox(height: 8),
              const _SpotlightCarousel(),
              const _QuickActionsRow(),
              const _PublisherCta(),
              ...overviewAsync.when(
                loading: () => const [
                  SizedBox(height: 80),
                  Center(child: CircularProgressIndicator()),
                ],
                error: (_, _) => [
                  AppErrorState(
                    message: 'Could not load campus updates.',
                    onRetry: () => ref.invalidate(campusHubOverviewProvider),
                  ),
                ],
                data: (overview) => [
                  if (overview.urgentPosts.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    UrgentUpdateBanner(
                      post: overview.urgentPosts.first,
                      onTap: () => context.push('/home/posts/${overview.urgentPosts.first.id}'),
                    ),
                  ],
                  _LatestUpdatesPanel(updates: overview.latestUpdates),
                ],
              ),
              if (isStudent) ...[
                _SectionHeader(
                  title: 'Upcoming activities',
                  action: 'See all',
                  onAction: () => context.go('/activities'),
                ),
                const _ActivitiesPreview(),
                _SectionHeader(
                  title: 'Suggested connections',
                  action: 'See all',
                  onAction: () => context.go('/discover'),
                ),
                const _SuggestedConnectionsPreview(),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
