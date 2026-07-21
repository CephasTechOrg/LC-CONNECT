import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../providers/discovery_provider.dart';
import '../../safety/providers/safety_provider.dart';
import '../../safety/widgets/safety_sheet.dart';

part '../widgets/discovery_student_card.dart';
part '../widgets/discovery_card_parts.dart';

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
