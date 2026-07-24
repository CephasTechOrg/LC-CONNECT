import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../shared/widgets/app_shell_header.dart';
import '../../../shared/widgets/app_states.dart';
import '../../notifications/widgets/notifications_bell_button.dart';
import '../../auth/providers/auth_provider.dart';
import '../../discovery/providers/discovery_provider.dart';
import '../../activities/providers/activities_provider.dart';
import '../../groups/data/placeholder_groups.dart';
import '../../messages/providers/messages_provider.dart';
import '../../profile/providers/profile_provider.dart';
import '../data/featured_slides.dart';

part '../widgets/home_header.dart';
part '../widgets/home_feed_sections.dart';
part '../widgets/home_hero_banner.dart';
part '../widgets/home_student_card.dart';
part '../widgets/home_activity_list.dart';
part '../widgets/home_match_cards.dart';
part '../widgets/home_groups.dart';

String _categoryEmoji(String category) => switch (category.toLowerCase()) {
      'study' => '📖',
      'sports' => '🏀',
      'social' => '☕',
      'arts' => '🎨',
      'food' => '🍕',
      'music' => '🎵',
      'tech' => '💻',
      _ => '📅',
    };

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  return '${diff.inDays}d';
}

String _studentSub(String? major, int? classYear) {
  if (major != null && classYear != null) {
    return "$major '${classYear % 100}";
  }
  if (major != null) return major;
  if (classYear != null) return 'Class of $classYear';
  return 'LC Student';
}

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// Prefer profile display name; fall back to email local-part only if needed.
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

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Future<void> _connect(DiscoveryCard card) async {
    try {
      await ref.read(discoveryNotifierProvider.notifier).connect(
            card.userId,
            card.profileId,
            'open_connection',
          );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not send request — please try again'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).asData?.value;
    final profile = ref.watch(myProfileNotifierProvider).asData?.value;
    final firstName = _greetingName(
      displayName: profile?.displayName,
      email: user?.email,
    );

    final discoveryAsync = ref.watch(discoveryNotifierProvider);
    final activitiesAsync = ref.watch(activitiesNotifierProvider);
    final threadsAsync = ref.watch(threadsNotifierProvider);

    final allCards = discoveryAsync.asData?.value ?? [];
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    final upcoming = (activitiesAsync.asData?.value ?? [])
        .where((a) => a.startTime.isAfter(cutoff))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final threads = threadsAsync.asData?.value ?? [];
    final recentThread = threads.isNotEmpty ? threads.first : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(discoveryNotifierProvider);
            ref.invalidate(activitiesNotifierProvider);
            ref.invalidate(threadsNotifierProvider);
          },
          child: ListView(
            children: [
              _Header(
                greeting: '${_greeting()}, $firstName',
              ),
              const SizedBox(height: 12),
              const _SearchBar(),
              const SizedBox(height: 16),
              const _HeroBanner(),
              _SectionHeader(
                title: 'Recommended for you',
                action: 'View all',
                onAction: () => context.go('/discover'),
              ),
              _StudentCardsRow(
                cards: allCards.take(5).toList(),
                loading: discoveryAsync.isLoading,
                onConnect: _connect,
              ),
              _SectionHeader(
                title: 'Study Partners',
                action: null,
                onAction: null,
              ),
              const _StudyPartnersCta(),
              _SectionHeader(
                title: 'Upcoming Activities',
                action: 'See all',
                onAction: () => context.go('/activities'),
              ),
              _ActivitiesList(
                activities: upcoming.take(3).toList(),
                loading: activitiesAsync.isLoading,
              ),
              _SectionHeader(
                title: 'Campus Groups',
                action: 'See all',
                onAction: () => context.go('/discover?tab=groups'),
              ),
              const _CampusGroupsRow(),
              _SectionHeader(
                title: 'Messages',
                action: 'View all',
                onAction: () => context.go('/messages'),
              ),
              if (recentThread != null)
                _RecentMatchCard(
                  thread: recentThread,
                  onTap: () => context.go(
                    '/messages/${recentThread.matchId}',
                    extra: recentThread,
                  ),
                )
              else if (threadsAsync.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: LinearProgressIndicator(
                    backgroundColor: AppColors.border,
                    color: AppColors.primary,
                  ),
                )
              else
                const _NoMatchesYet(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
