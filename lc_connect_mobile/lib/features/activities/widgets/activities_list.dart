part of '../screens/activities_screen.dart';

class _ActivityList extends StatelessWidget {
  final List<Activity> activities;
  const _ActivityList({required this.activities});

  @override
  Widget build(BuildContext context) {
    final featured = activities.first;
    final rest = activities.skip(1).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      children: [
        _FeaturedCard(activity: featured),
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
