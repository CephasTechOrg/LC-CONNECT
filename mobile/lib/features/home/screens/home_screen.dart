import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../auth/providers/auth_provider.dart';
import '../../connections/providers/connections_provider.dart';
import '../../discovery/providers/discovery_provider.dart';
import '../../activities/providers/activities_provider.dart';
import '../../messages/providers/messages_provider.dart';

part '../widgets/home_header.dart';
part '../widgets/home_feed_sections.dart';
part '../widgets/home_student_card.dart';
part '../widgets/home_activity_list.dart';
part '../widgets/home_match_cards.dart';

// ── Category definitions ──────────────────────────────────────────
class _Cat {
  final String label;
  final IconData icon;
  final String? code; // null = show all
  const _Cat(this.label, this.icon, this.code);
}

const _cats = [
  _Cat('Friendship',        Icons.people_outline_rounded,  'friendship'),
  _Cat('Study Partner',     Icons.menu_book_outlined,      'study_partner'),
  _Cat('Language Exchange', Icons.language_outlined,       'language_exchange'),
  _Cat('Events',            Icons.calendar_month_outlined, null),
  _Cat('Open Connection',   Icons.link_rounded,            'open_connection'),
];

// ── Helpers ───────────────────────────────────────────────────────
String _categoryEmoji(String category) => switch (category.toLowerCase()) {
      'study'   => '📖',
      'sports'  => '🏃',
      'social'  => '☕',
      'arts'    => '🎨',
      'food'    => '🍕',
      'music'   => '🎵',
      'tech'    => '💻',
      _         => '📅',
    };

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

String _studentSub(String? major, int? classYear) {
  if (major != null && classYear != null) {
    return "$major '${classYear % 100}";
  }
  if (major != null) return major;
  if (classYear != null) return 'Class of $classYear';
  return 'LC Student';
}

// ── Screen ────────────────────────────────────────────────────────
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _selectedCat = 'Friendship';

  Future<void> _connect(DiscoveryCard card, String? intent) async {
    try {
      await ref.read(discoveryNotifierProvider.notifier).connect(
            card.userId, card.profileId, intent ?? 'open_connection');
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
    final firstName = user?.email.split('@').first ?? 'there';
    final incomingCount =
        ref.watch(connectionsNotifierProvider).asData?.value.incoming.length ?? 0;

    final discoveryAsync = ref.watch(discoveryNotifierProvider);
    final activitiesAsync = ref.watch(activitiesNotifierProvider);
    final threadsAsync = ref.watch(threadsNotifierProvider);

    final selectedCat = _cats.firstWhere((c) => c.label == _selectedCat);
    final allCards = discoveryAsync.asData?.value ?? [];
    final filteredCards = selectedCat.code == null
        ? allCards
        : allCards.where((c) => c.lookingForCodes.contains(selectedCat.code)).toList();

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
              _Header(firstName: firstName, incomingCount: incomingCount),
              const SizedBox(height: 12),
              _SearchBar(),
              const SizedBox(height: 12),
              _CategoryChips(
                selected: _selectedCat,
                onSelect: (c) => setState(() => _selectedCat = c),
              ),
              const SizedBox(height: 4),
              _SectionHeader(
                title: 'Recommended for you',
                action: 'View all',
                onAction: () => context.go('/discover'),
              ),
              const SizedBox(height: 10),
              _StudentCardsRow(
                cards: filteredCards.take(5).toList(),
                loading: discoveryAsync.isLoading,
                onConnect: (card) => _connect(card, selectedCat.code),
              ),
              const SizedBox(height: 18),
              _SectionHeader(
                title: "Today's activities",
                action: 'View calendar',
                onAction: () => context.go('/activities'),
              ),
              const SizedBox(height: 10),
              _ActivitiesList(
                activities: upcoming.take(3).toList(),
                loading: activitiesAsync.isLoading,
              ),
              const SizedBox(height: 18),
              _SectionHeader(
                title: 'Recent matches',
                action: 'View messages',
                onAction: () => context.go('/messages'),
              ),
              const SizedBox(height: 10),
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
                _NoMatchesYet(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
