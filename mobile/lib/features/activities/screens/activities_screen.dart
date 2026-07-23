import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_filter_chip.dart';
import '../../../shared/widgets/app_shell_header.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/connections_bell_button.dart';
import '../providers/activities_provider.dart';

// ── Filter definitions ───────────────────────────────────────────
part '../widgets/activities_header.dart';
part '../widgets/activities_filters.dart';
part '../widgets/activities_list.dart';
part '../widgets/activities_featured_card.dart';
part '../widgets/activities_compact_card.dart';
part '../widgets/activities_join_buttons.dart';
part '../widgets/activities_states.dart';

const _filters = [
  ('all', 'All'),
  ('study', 'Study'),
  ('sports', 'Sports'),
  ('social', 'Social'),
  ('culture', 'Culture'),
];

// ── Screen ───────────────────────────────────────────────────────
class ActivitiesScreen extends ConsumerWidget {
  const ActivitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(activitiesFilterProvider);
    final async = ref.watch(activitiesNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/activities/create'),
        backgroundColor: AppColors.primary,
        elevation: 3,
        child: const Icon(Icons.add, color: Colors.white, size: 26),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Header(),
            const SizedBox(height: 4),
            _FilterChips(
              selected: filter,
              onSelect: (f) =>
                  ref.read(activitiesFilterProvider.notifier).set(f),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorState(
                  onRetry: () =>
                      ref.invalidate(activitiesNotifierProvider),
                ),
                data: (activities) => activities.isEmpty
                    ? _EmptyState(
                        hasFilter: filter != 'all',
                        onClear: () => ref
                            .read(activitiesFilterProvider.notifier)
                            .set('all'),
                      )
                    : _ActivityList(activities: activities),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// ── Date/time helpers ─────────────────────────────────────────────
String _formatDate(DateTime dt) => DateFormat('EEE, MMM d').format(dt);

String _formatTimeRange(DateTime start, DateTime? end) {
  final s = DateFormat('h:mm a').format(start);
  if (end == null) return s;
  return '$s – ${DateFormat('h:mm a').format(end)}';
}
