import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../connections/providers/connections_provider.dart';

// ── Sample data (matches mockup exactly) ────────────────────────
const _cats = [
  _Cat('Friendship',        Icons.people_outline_rounded),
  _Cat('Study Partner',     Icons.menu_book_outlined),
  _Cat('Language Exchange', Icons.language_outlined),
  _Cat('Events',            Icons.calendar_month_outlined),
  _Cat('Open Connection',   Icons.link_rounded),
];

const _students = [
  _Student('Malik J.',  "Computer Science '26", ['Coding', 'Soccer']),
  _Student('Sophie L.', "Biology '27",           ['Study Buddies', 'Hiking']),
  _Student('Ethan R.',  "Economics '26",         ['Finance', 'Basketball']),
];

const _activities = [
  _Activity('📖', 'Study Session',  'Library, 2nd Floor', 8,  '2:00 PM'),
  _Activity('🏀', 'Basketball Run', 'Recreation Center',  12, '5:00 PM'),
  _Activity('☕', 'Coffee Meetup',  'Campus Cafe',        6,  '7:30 PM'),
];

// ── Screen ───────────────────────────────────────────────────────
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _selectedCat = 'Friendship';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).asData?.value;
    final firstName = user?.email.split('@').first ?? 'there';
    final incomingCount = ref
            .watch(connectionsNotifierProvider)
            .asData
            ?.value
            .incoming
            .length ??
        0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
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
            _StudentCardsRow(),
            const SizedBox(height: 18),
            _SectionHeader(
              title: "Today's activities",
              action: 'View calendar',
              onAction: () => context.go('/activities'),
            ),
            const SizedBox(height: 10),
            _ActivitiesList(),
            const SizedBox(height: 18),
            _SectionHeader(
              title: 'Recent matches',
              action: 'View messages',
              onAction: () => context.go('/messages'),
            ),
            const SizedBox(height: 10),
            _RecentMatchCard(onTap: () => context.go('/messages')),
            const SizedBox(height: 24),
          ],
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

// ── Student cards row (horizontal scroll) ────────────────────────
class _StudentCardsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._students.map((s) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _StudentCard(student: s),
              )),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  final _Student student;
  const _StudentCard({required this.student});

  @override
  Widget build(BuildContext context) {
    return Container(
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
          // Avatar section with school bg
          Stack(
            clipBehavior: Clip.none,
            children: [
              // School bg
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
                      child: Image.asset(
                        'assets/images/headshots.png',
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                      ),
                    ),
                  ),
                ),
              ),
              // Connect badge
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
          // Name + sub
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: [
                Text(
                  student.name,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  student.sub,
                  style: GoogleFonts.dmSans(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Tags
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: student.tags
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
          // Connect button
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
            child: SizedBox(
              width: double.infinity,
              child: Material(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () {},
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
    );
  }
}

// ── Activities list ──────────────────────────────────────────────
class _ActivitiesList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: _activities
            .map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _ActivityItem(activity: a),
                ))
            .toList(),
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final _Activity activity;
  const _ActivityItem({required this.activity});

  @override
  Widget build(BuildContext context) {
    return Container(
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
          // Emoji box
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(activity.emoji, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 11),
          // Name + location
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.name,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  activity.location,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          // Going count
          Row(
            children: [
              const Icon(Icons.people_outline_rounded,
                  size: 13, color: AppColors.textMuted),
              const SizedBox(width: 3),
              Text(
                '${activity.going} going',
                style: GoogleFonts.dmSans(
                    fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(width: 8),
          // Time
          Text(
            activity.time,
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
    );
  }
}

// ── Recent match card ────────────────────────────────────────────
class _RecentMatchCard extends StatelessWidget {
  final VoidCallback onTap;
  const _RecentMatchCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
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
              // Avatar with online dot
              Stack(
                children: [
                  ClipOval(
                    child: Image.asset(
                      'assets/images/headshots.png',
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
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
              // Name + sub + message
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sophie L.',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      "Biology '27",
                      style: GoogleFonts.dmSans(
                          fontSize: 11, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Hey! I'm also taking BIO 201. Want to study together this week?",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                          fontSize: 12, color: AppColors.textMid),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Time + chevron
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '2h ago',
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

// ── Data models ──────────────────────────────────────────────────
class _Cat {
  final String label;
  final IconData icon;
  const _Cat(this.label, this.icon);
}

class _Student {
  final String name;
  final String sub;
  final List<String> tags;
  const _Student(this.name, this.sub, this.tags);
}

class _Activity {
  final String emoji;
  final String name;
  final String location;
  final int going;
  final String time;
  const _Activity(this.emoji, this.name, this.location, this.going, this.time);
}
