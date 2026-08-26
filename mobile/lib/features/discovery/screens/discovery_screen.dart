import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/api/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../shared/widgets/app_filter_chip.dart';
import '../../../shared/widgets/app_shell_header.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/verified_badge.dart';
import '../../notifications/widgets/notifications_bell_button.dart';
import '../../auth/providers/auth_provider.dart';
import '../../campus_hub/widgets/staff_student_directory.dart';
import '../../connections/widgets/connection_requests_button.dart';
import '../../groups/widgets/groups_panel.dart';
import '../providers/discovery_provider.dart';
import '../../safety/providers/safety_provider.dart';
import '../../safety/widgets/safety_sheet.dart';

part '../widgets/discovery_student_card.dart';
part '../widgets/discovery_card_parts.dart';

const _filters = [
  ('all', 'All'),
  ('friendship', 'Friendship'),
  ('study_partner', 'Study Partner'),
  ('language_exchange', 'Language Exchange'),
  ('events', 'Events'),
  ('open_connection', 'Open Connection'),
];

const _tabs = ['Students', 'Study Partners', 'Groups'];

class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _activeFilter = 'all';
  String _tab = 'Students';
  String? _lastQueryTab;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _syncTabFromRoute(BuildContext context) {
    final tabParam =
        GoRouterState.of(context).uri.queryParameters['tab']?.toLowerCase();
    if (tabParam == _lastQueryTab) return;
    _lastQueryTab = tabParam;
    final next = switch (tabParam) {
      'groups' => 'Groups',
      'study' || 'study_partners' || 'studypartners' => 'Study Partners',
      'students' => 'Students',
      _ => null,
    };
    if (next != null && next != _tab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _tab = next;
          if (next == 'Study Partners') {
            _activeFilter = 'study_partner';
          }
        });
      });
    }
  }

  List<DiscoveryCard> _applyFilters(List<DiscoveryCard> cards) {
    var list = cards;
    if (_tab == 'Study Partners') {
      list = list
          .where((c) => c.lookingForCodes.contains('study_partner'))
          .toList();
    }
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
    _syncTabFromRoute(context);
    final role = ref.watch(authNotifierProvider).asData?.value?.role ?? 'student';
    if (role != 'student') {
      // Staff don't match with students — they browse and message them.
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(child: StaffStudentDirectory()),
      );
    }

    final discoveryState = ref.watch(discoveryNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildSegmentTabs(),
            if (_tab == 'Groups')
              const Expanded(child: GroupsPanel())
            else ...[
              const SizedBox(height: 12),
              _buildSearchBar(),
              const SizedBox(height: 12),
              _buildFilterRow(),
              const SizedBox(height: 12),
              Expanded(
                child: discoveryState.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _buildError(),
                  data: (cards) {
                    final filtered = _applyFilters(cards);
                    if (filtered.isEmpty) return _buildEmpty();
                    return _buildList(filtered);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return AppShellHeader(
      title: 'Connect',
      subtitle: 'Students, study partners & groups at Livingstone',
      trailing: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConnectionRequestsButton(),
          NotificationsBellButton(),
        ],
      ),
    );
  }

  Widget _buildSegmentTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: _tabs.map((t) {
          final on = _tab == t;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Material(
                color: on ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: () => setState(() {
                    _tab = t;
                    if (t == 'Study Partners') {
                      _activeFilter = 'study_partner';
                    } else if (t == 'Students') {
                      _activeFilter = 'all';
                    }
                  }),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Text(
                      t,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: on ? Colors.white : AppColors.textMid,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSearchBar() {
    // Filters live in `_buildFilterRow` below — no separate tune control (that
    // icon was a dead affordance with no handler).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textDark),
        decoration: InputDecoration(
          hintText: 'Search by name, major, or interests',
          hintStyle: GoogleFonts.dmSans(
              fontSize: 14, color: const Color(0xFF9CA3AF)),
          prefixIcon: const Icon(Icons.search_rounded,
              size: 16, color: AppColors.textMuted),
          filled: true,
          fillColor: AppColors.background,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
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
                const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: _filters
            .map(
              (f) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AppFilterChip(
                  label: f.$2,
                  selected: _activeFilter == f.$1,
                  onTap: () => setState(() => _activeFilter = f.$1),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildList(List<DiscoveryCard> cards) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      itemCount: cards.length,
      itemBuilder: (ctx, i) {
        final card = cards[i];
        Future<void> connect(String intent) async {
          try {
            await ref
                .read(discoveryNotifierProvider.notifier)
                .connect(card.userId, card.profileId, intent);
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text(apiErrorMessage(e, fallback: 'Could not send request — try again')),
              ));
            }
          }
        }

        return _StudentCard(
          key: ValueKey(card.profileId),
          card: card,
          onConnect: () => connect('connect'),
          onStudyTogether: () => connect('study_together'),
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

  Widget _buildEmpty() {
    return AppEmptyState(
      icon: Icons.people_outline,
      title: _activeFilter == 'all' && _query.isEmpty
          ? "You've seen everyone!"
          : 'No students match this filter',
      subtitle: _activeFilter == 'all' && _query.isEmpty
          ? 'Check back later as more students join LC Connect.'
          : 'Try a different filter or search term.',
    );
  }

  Widget _buildError() {
    return AppErrorState(
      message: 'Could not load students',
      icon: Icons.wifi_off_rounded,
      onRetry: () => ref.invalidate(discoveryNotifierProvider),
    );
  }
}
