part of '../screens/connections_screen.dart';

// ── Header ────────────────────────────────────────────────────────
// No logo: it belongs to the tab-root headers. A pushed page with a back button, like
// Notifications, leads with its title.
class _Header extends StatelessWidget {
  final VoidCallback onBack;
  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: AppColors.textDark,
            ),
            onPressed: onBack,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connection requests',
                  style: AppTypography.title.copyWith(color: AppColors.textDark),
                ),
                Text(
                  'Manage who you connect with',
                  style: AppTypography.label.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Consumer(
            builder: (context, ref, _) => IconButton(
              tooltip: 'Refresh',
              icon: const Icon(
                Icons.refresh_rounded,
                size: 20,
                color: AppColors.textMuted,
              ),
              onPressed: () => ref.invalidate(connectionsNotifierProvider),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab bar ───────────────────────────────────────────────────────
class _TabBar extends StatelessWidget {
  final TabController controller;
  final int incomingCount;
  final int outgoingCount;
  const _TabBar({
    required this.controller,
    required this.incomingCount,
    required this.outgoingCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: TabBar(
        controller: controller,
        labelColor: AppColors.primaryText,
        unselectedLabelColor: AppColors.textMuted,
        indicatorColor: AppColors.primary,
        indicatorWeight: 2.5,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: AppTypography.body.copyWith(fontWeight: FontWeight.w500),
        tabs: [
          _tab('Incoming', incomingCount),
          _tab('Outgoing', outgoingCount),
        ],
      ),
    );
  }

  Widget _tab(String label, int count) => Tab(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (count > 0) ...[
          const SizedBox(width: 6),
          _CountBadge(count),
        ],
      ],
    ),
  );
}

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge(this.count);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: AppRadii.all(AppRadii.full),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: AppTypography.caption.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.primaryText,
        ),
      ),
    );
  }
}

// ── Incoming tab ──────────────────────────────────────────────────
