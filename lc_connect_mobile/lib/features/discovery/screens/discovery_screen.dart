import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../providers/discovery_provider.dart';
import '../../safety/providers/safety_provider.dart';
import '../../safety/widgets/safety_sheet.dart';

// ── Filter definitions ─────────────────────────────────────────────
const _filters = [
  ('all', 'All'),
  ('friendship', 'Friendship'),
  ('study_partner', 'Study Partner'),
  ('language_exchange', 'Language Exchange'),
];

class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _activeFilter = 'all';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<DiscoveryCard> _applyFilters(List<DiscoveryCard> cards) {
    var list = cards;
    if (_activeFilter != 'all') {
      list = list
          .where((c) => c.lookingForCodes.contains(_activeFilter))
          .toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((c) =>
              (c.displayName?.toLowerCase().contains(q) ?? false) ||
              (c.major?.toLowerCase().contains(q) ?? false) ||
              c.interests.any((i) => i.toLowerCase().contains(q)))
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final discoveryState = ref.watch(discoveryNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 14),
            _buildSearchBar(),
            const SizedBox(height: 12),
            _buildFilterRow(),
            const SizedBox(height: 12),
            Expanded(
              child: discoveryState.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => _buildError(),
                data: (cards) {
                  final filtered = _applyFilters(cards);
                  if (filtered.isEmpty) return _buildEmpty();
                  return _buildList(filtered);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              'LC',
              style: GoogleFonts.dmSans(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connect',
                  style: GoogleFonts.dmSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'Discover and connect with students at Livingstone College',
                  style: GoogleFonts.dmSans(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_outlined,
                color: AppColors.textMid),
          ),
        ],
      ),
    );
  }

  // ── Search bar ────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                style: GoogleFonts.dmSans(
                    fontSize: 13.5, color: AppColors.textDark),
                decoration: InputDecoration(
                  hintText: 'Search by name, major, or interests',
                  hintStyle: GoogleFonts.dmSans(
                      fontSize: 13, color: AppColors.textMuted),
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 18, color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.border, width: 1.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.border, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.border, width: 1.5),
            ),
            child: const Icon(Icons.tune_rounded,
                size: 18, color: AppColors.textMid),
          ),
        ],
      ),
    );
  }

  // ── Filter chips ──────────────────────────────────────────────────
  Widget _buildFilterRow() {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: _filters.map((f) {
          final isActive = _activeFilter == f.$1;
          return GestureDetector(
            onTap: () => setState(() => _activeFilter = f.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? AppColors.textDark : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive ? AppColors.textDark : AppColors.border,
                  width: 1.5,
                ),
              ),
              child: Text(
                f.$2,
                style: GoogleFonts.dmSans(
                  fontSize: 12.5,
                  fontWeight:
                      isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? Colors.white : AppColors.textMid,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Card list ─────────────────────────────────────────────────────
  Widget _buildList(List<DiscoveryCard> cards) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      itemCount: cards.length,
      itemBuilder: (ctx, i) {
        final card = cards[i];
        return _StudentCard(
          key: ValueKey(card.profileId),
          card: card,
          onConnect: () => ref
              .read(discoveryNotifierProvider.notifier)
              .connect(card.userId, card.profileId, 'connect'),
          onStudyTogether: () => ref
              .read(discoveryNotifierProvider.notifier)
              .connect(card.userId, card.profileId, 'study_together'),
          onSkip: () => ref
              .read(discoveryNotifierProvider.notifier)
              .skip(card.profileId),
          onMore: () => showSafetySheet(
            context: ctx,
            targetUserId: card.userId,
            targetName: card.displayName ?? 'this student',
            safetyService: ref.read(safetyServiceProvider),
            onBlocked: () => ref
                .read(discoveryNotifierProvider.notifier)
                .skip(card.profileId),
          ),
        );
      },
    );
  }

  // ── Empty state ───────────────────────────────────────────────────
  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.people_outline,
                  size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              _activeFilter == 'all' && _query.isEmpty
                  ? "You've seen everyone!"
                  : 'No students match this filter',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _activeFilter == 'all' && _query.isEmpty
                  ? 'Check back later as more students join LC Connect.'
                  : 'Try a different filter or search term.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: AppColors.textMuted, height: 1.5),
            ),
            if (_activeFilter != 'all' || _query.isNotEmpty) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => setState(() {
                  _activeFilter = 'all';
                  _query = '';
                  _searchCtrl.clear();
                }),
                child: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Error state ───────────────────────────────────────────────────
  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded,
              size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text('Could not load students',
              style:
                  GoogleFonts.dmSans(fontSize: 15, color: AppColors.textMuted)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () =>
                ref.invalidate(discoveryNotifierProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Student card
// ══════════════════════════════════════════════════════════════════

class _StudentCard extends StatefulWidget {
  final DiscoveryCard card;
  final Future<void> Function() onConnect;
  final Future<void> Function() onStudyTogether;
  final VoidCallback onSkip;
  final VoidCallback onMore;

  const _StudentCard({
    super.key,
    required this.card,
    required this.onConnect,
    required this.onStudyTogether,
    required this.onSkip,
    required this.onMore,
  });

  @override
  State<_StudentCard> createState() => _StudentCardState();
}

class _StudentCardState extends State<_StudentCard> {
  bool _isActing = false;

  Future<void> _act(Future<void> Function() action) async {
    if (_isActing) return;
    setState(() => _isActing = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isActing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Something went wrong. Please try again.',
              style: GoogleFonts.dmSans()),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    final primaryCode =
        c.lookingForCodes.isNotEmpty ? c.lookingForCodes[0] : null;
    final primaryLabel =
        c.lookingFor.isNotEmpty ? c.lookingFor[0] : null;
    final matchReason =
        c.matchReasons.isNotEmpty ? c.matchReasons[0] : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: looking-for badge + menu ───────────────────
            Row(
              children: [
                if (primaryCode != null && primaryLabel != null)
                  _LookingForBadge(code: primaryCode, label: primaryLabel),
                const Spacer(),
                IconButton(
                  onPressed: widget.onMore,
                  icon: const Icon(Icons.more_horiz,
                      color: AppColors.textMuted, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Profile row: avatar + info ──────────────────────────
            GestureDetector(
              onTap: () => context.push(
                '/users/${c.profileId}',
                extra: c.displayName,
              ),
              child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(avatarUrl: c.avatarUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.displayName ?? 'Student',
                        style: GoogleFonts.dmSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (c.classYear != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          'Class of ${c.classYear}',
                          style: GoogleFonts.dmSans(
                              fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                      if (c.major != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          c.major!,
                          style: GoogleFonts.dmSans(
                              fontSize: 13, color: AppColors.textMuted),
                        ),
                      ],
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(Icons.location_city_outlined,
                              size: 12, color: AppColors.textMuted),
                          const SizedBox(width: 3),
                          Text(
                            'Livingstone College',
                            style: GoogleFonts.dmSans(
                                fontSize: 11, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              ),
            ),

            // ── Interests ──────────────────────────────────────────
            if (c.interests.isNotEmpty) ...[
              const SizedBox(height: 12),
              _InterestChips(interests: c.interests),
            ],

            // ── Languages ─────────────────────────────────────────
            if (c.languagesSpoken.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.language_outlined,
                      size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    'Speaks ${c.languagesSpoken.join(', ')}',
                    style: GoogleFonts.dmSans(
                        fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ],

            // ── Additional looking-for chips ───────────────────────
            if (c.lookingFor.length > 1) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: c.lookingFor.skip(1).map((label) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryPale,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.primaryLight.withAlpha(80)),
                    ),
                    child: Text(
                      label,
                      style: GoogleFonts.dmSans(
                          fontSize: 11.5,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500),
                    ),
                  );
                }).toList(),
              ),
            ],

            // ── Match reason ───────────────────────────────────────
            if (matchReason != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.people_outline,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        matchReason,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Action buttons ────────────────────────────────────
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'Connect',
                    icon: Icons.person_add_outlined,
                    isLoading: _isActing,
                    onTap: () => _act(widget.onConnect),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    label: 'Study Together',
                    icon: Icons.menu_book_outlined,
                    isLoading: _isActing,
                    onTap: () => _act(widget.onStudyTogether),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // ── Maybe Later ───────────────────────────────────────
            Center(
              child: TextButton(
                onPressed: _isActing ? null : widget.onSkip,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Maybe Later',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: AppColors.textMuted,
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

// ── Avatar ─────────────────────────────────────────────────────────
class _Avatar extends StatelessWidget {
  final String? avatarUrl;
  const _Avatar({this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return AvatarWidget(imageUrl: avatarUrl, size: 70);
  }
}

// ── Looking-for badge (top of card) ───────────────────────────────
class _LookingForBadge extends StatelessWidget {
  final String code;
  final String label;
  const _LookingForBadge({required this.code, required this.label});

  IconData get _icon => switch (code) {
        'study_partner' => Icons.menu_book_outlined,
        'friendship' => Icons.people_outline,
        'language_exchange' => Icons.language_outlined,
        'events' => Icons.event_outlined,
        _ => Icons.connect_without_contact_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 5),
          Text(
            'Wants ${label.toLowerCase()}',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Interest chips (max 3 + overflow) ─────────────────────────────
class _InterestChips extends StatelessWidget {
  final List<String> interests;
  const _InterestChips({required this.interests});

  @override
  Widget build(BuildContext context) {
    final visible = interests.take(3).toList();
    final overflow = interests.length - visible.length;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ...visible.map((name) => Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                name,
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: AppColors.textMid),
              ),
            )),
        if (overflow > 0)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              '+$overflow',
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: AppColors.textMuted),
            ),
          ),
      ],
    );
  }
}

// ── Action button (Connect / Study Together) ───────────────────────
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isLoading;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isLoading ? AppColors.primaryLight : AppColors.primary,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 42,
          alignment: Alignment.center,
          child: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 15, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: GoogleFonts.dmSans(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
