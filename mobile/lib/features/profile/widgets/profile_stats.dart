part of '../screens/profile_screen.dart';

// ── Stats row ─────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final MyProfile profile;
  const _StatsRow({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          _StatItem(count: profile.connectionCount, label: 'Connections'),
          _StatDivider(),
          // A cumulative message total stops meaning anything once someone is active — it only
          // ever goes up, and a big number says nothing about the account. Connections and
          // activities describe participation; a message tally just describes volume.
          _StatItem(count: profile.activityCount, label: 'Joined Activities'),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final int count;
  final String label;
  const _StatItem({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$count',
            style: GoogleFonts.dmSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
                fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: AppColors.border,
    );
  }
}

