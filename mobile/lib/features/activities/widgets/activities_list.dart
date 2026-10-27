part of '../screens/activities_screen.dart';

class _ActivityList extends StatelessWidget {
  final List<Activity> activities;
  const _ActivityList({required this.activities});

  @override
  Widget build(BuildContext context) {
    // Deterministic hero pick (timing / scarcity / participation, with a discovery nudge) rather
    // than "whatever the API returned first" — see `selectFeatured`. Falls back to the first item
    // only if nothing is eligible, which the list's non-empty guard already makes near-impossible.
    final pick = selectFeatured(activities, now: DateTime.now());
    final featured = pick?.activity ?? activities.first;
    final featuredLabel = pick?.label ?? 'Featured';
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

// ── Featured card ─────────────────────────────────────────────────
