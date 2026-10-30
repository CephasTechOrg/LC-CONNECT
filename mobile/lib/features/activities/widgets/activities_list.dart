part of '../screens/activities_screen.dart';

class _ActivityList extends ConsumerWidget {
  final List<Activity> activities;
  final String filter;
  const _ActivityList({required this.activities, required this.filter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (featured, featuredLabel) = heroFor(
      activities,
      server: ref.watch(featuredActivityProvider).value,
      filter: filter,
      now: DateTime.now(),
    );
    final rest = activities.where((a) => a.id != featured.id).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      children: [
        _FeaturedCard(activity: featured, label: featuredLabel),
        const SizedBox(height: 16),
        ...rest.map((a) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CompactCard(activity: a),
            )),
      ],
    );
  }
}

/// The hero of the Activities tab and its badge.
///
/// The server's pick, so every student sees the same one — as long as it fits the selected
/// category (an unrelated hero over a filtered list reads as a mistake). The list's own copy is
/// used when it has one, so its RSVP state stays live. Otherwise, and on an older server, the
/// local scorer chooses from what is listed — see `selectFeatured`.
(Activity, String) heroFor(
  List<Activity> activities, {
  required ServerFeatured? server,
  required String filter,
  required DateTime now,
}) {
  if (server != null && (filter == 'all' || server.activity.category == filter)) {
    final listed = activities.where((a) => a.id == server.activity.id).firstOrNull;
    return (listed ?? server.activity, server.label);
  }
  final pick = selectFeatured(activities, now: now);
  return (pick?.activity ?? activities.first, pick?.label ?? 'Featured');
}

// ── Featured card ─────────────────────────────────────────────────
