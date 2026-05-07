import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../connections/providers/connections_provider.dart';
import '../../discovery/providers/discovery_provider.dart';
import '../../activities/providers/activities_provider.dart';
import '../../messages/providers/messages_provider.dart';

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

Widget _avatarImage(String? url, {double size = 50}) {
  final fallback = Image.asset(
    'assets/images/headshots.png',
    width: size,
    height: size,
    fit: BoxFit.cover,
    alignment: Alignment.topCenter,
  );
  if (url == null || url.isEmpty) return fallback;
  return Image.network(
    url,
    width: size,
    height: size,
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => fallback,
  );
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

// ── Header ───────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String firstName;
  final int incomingCount;
  const _Header({required this.firstName, required this.incomingCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        children: [
          _LCBadge(size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hi, $firstName',
                  style: GoogleFonts.dmSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                    height: 1.2,
                  ),
                ),
                Text(
                  'Ready to connect on campus?',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => context.push('/connections'),
            child: _BellIcon(badgeCount: incomingCount),
          ),
        ],
      ),
    );
  }
}

class _LCBadge extends StatelessWidget {
  final double size;
  const _LCBadge({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      alignment: Alignment.center,
      child: Text(
        'LC',
        style: GoogleFonts.dmSans(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BellIcon extends StatelessWidget {
  final int badgeCount;
  const _BellIcon({this.badgeCount = 0});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.notifications_outlined,
            color: AppColors.textMuted, size: 24),
        if (badgeCount > 0)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                badgeCount > 9 ? '9+' : '$badgeCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Search bar ───────────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () => context.go('/discover'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 18),
              const SizedBox(width: 8),
              Text(
                'Search people, interests, or activities',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  color: const Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Category chips ───────────────────────────────────────────────
class _CategoryChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _CategoryChips({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          ..._cats.map((cat) {
            final on = selected == cat.label;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () => onSelect(cat.label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  constraints: const BoxConstraints(minWidth: 72),
                  decoration: BoxDecoration(
                    color: on ? AppColors.primarySoft : AppColors.surface,
                    border: Border.all(
                      color: on ? AppColors.primary : AppColors.border,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        cat.icon,
                        size: 20,
                        color: on ? AppColors.primary : AppColors.textMuted,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        cat.label,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(
                          fontSize: 10,
                          fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                          color: on ? AppColors.primary : AppColors.textMuted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ── Section header ───────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final String action;
  final VoidCallback onAction;
  const _SectionHeader({
    required this.title,
    required this.action,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          GestureDetector(
            onTap: onAction,
            child: Text(
              action,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Student cards row ─────────────────────────────────────────────
class _StudentCardsRow extends StatelessWidget {
  final List<DiscoveryCard> cards;
  final bool loading;
  final ValueChanged<DiscoveryCard> onConnect;
  const _StudentCardsRow({
    required this.cards,
    required this.loading,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && cards.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (cards.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Text(
          'No matches for this category yet.\nTry another or check back later.',
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMuted),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...cards.map((card) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _StudentCard(card: card, onConnect: onConnect),
              )),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  final DiscoveryCard card;
  final ValueChanged<DiscoveryCard> onConnect;
  const _StudentCard({required this.card, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final tags = card.interests.take(2).toList();
    final sub = _studentSub(card.major, card.classYear);

    return GestureDetector(
      onTap: () => context.push(
        '/users/${card.profileId}',
        extra: card.displayName,
      ),
      child: Container(
        width: 132,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                // School background
                Container(
                  height: 90,
                  width: double.infinity,
                  color: AppColors.primaryPale,
                  child: Image.asset(
                    'assets/images/school.png',
                    fit: BoxFit.cover,
                    color: Colors.white.withAlpha(140),
                    colorBlendMode: BlendMode.lighten,
                    opacity: const AlwaysStoppedAnimation(0.45),
                  ),
                ),
                // Avatar overlapping below
                Positioned(
                  bottom: -22,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1F000000),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: _avatarImage(card.avatarUrl, size: 50),
                      ),
                    ),
                  ),
                ),
                // Match score badge
                Positioned(
                  bottom: -18,
                  right: 12,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.people_rounded,
                      color: Colors.white,
                      size: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                children: [
                  Text(
                    card.displayName ?? 'LC Student',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    sub,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: tags
                      .map((t) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primarySoft,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              t,
                              style: GoogleFonts.dmSans(
                                fontSize: 10,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: SizedBox(
                width: double.infinity,
                child: Material(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: () => onConnect(card),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Text(
                        'Connect',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Activities list ──────────────────────────────────────────────
class _ActivitiesList extends StatelessWidget {
  final List<Activity> activities;
  final bool loading;
  const _ActivitiesList({required this.activities, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading && activities.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: LinearProgressIndicator(
          backgroundColor: AppColors.border,
          color: AppColors.primary,
        ),
      );
    }
    if (activities.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Text(
          'No upcoming activities today.',
          style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMuted),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: activities
            .map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _ActivityItem(
                    activity: a,
                    onTap: () => context.go(
                      '/activities/${a.id}',
                      extra: a,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final Activity activity;
  final VoidCallback onTap;
  const _ActivityItem({required this.activity, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final timeLabel = DateFormat('h:mm a').format(activity.startTime.toLocal());
    final emoji = _categoryEmoji(activity.category);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                  Text(
                    activity.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                const Icon(Icons.people_outline_rounded,
                    size: 13, color: AppColors.textMuted),
                const SizedBox(width: 3),
                Text(
                  '${activity.participantCount} going',
                  style: GoogleFonts.dmSans(
                      fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Text(
              timeLabel,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                size: 16, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ── Recent match card ─────────────────────────────────────────────
class _RecentMatchCard extends StatelessWidget {
  final MessageThread thread;
  final VoidCallback onTap;
  const _RecentMatchCard({required this.thread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final partner = thread.partner;
    final latest = thread.latestMessage;
    final sub = _studentSub(partner.major, partner.classYear);
    final previewText = latest?.body ?? 'New match — say hello!';
    final timeText = latest != null ? _timeAgo(latest.createdAt) : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  ClipOval(
                    child: _avatarImage(partner.avatarUrl, size: 44),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner.displayName ?? 'LC Student',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      sub,
                      style: GoogleFonts.dmSans(
                          fontSize: 11, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      previewText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                          fontSize: 12, color: AppColors.textMid),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (timeText.isNotEmpty)
                    Text(
                      timeText,
                      style: GoogleFonts.dmSans(
                          fontSize: 10, color: AppColors.textMuted),
                    ),
                  const SizedBox(height: 4),
                  const Icon(Icons.chevron_right_rounded,
                      size: 16, color: AppColors.textMuted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── No matches yet ────────────────────────────────────────────────
class _NoMatchesYet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Text(
        'No matches yet. Accept a connection request to start chatting.',
        textAlign: TextAlign.center,
        style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMuted),
      ),
    );
  }
}
