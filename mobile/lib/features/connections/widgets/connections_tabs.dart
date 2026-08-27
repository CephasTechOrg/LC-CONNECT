part of '../screens/connections_screen.dart';

class _IncomingTab extends ConsumerWidget {
  final List<ConnectionRequest> requests;
  const _IncomingTab({required this.requests});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => ref.refresh(connectionsNotifierProvider.future),
      child: requests.isEmpty
          ? const _EmptyState(
              icon: Icons.inbox_outlined,
              title: 'No incoming requests',
              subtitle:
                  'When someone wants to connect with you, they\'ll appear here.',
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              itemCount: requests.length,
              separatorBuilder: (context, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _IncomingCard(request: requests[i]),
            ),
    );
  }
}

// ── Outgoing tab ──────────────────────────────────────────────────
class _OutgoingTab extends ConsumerWidget {
  final List<ConnectionRequest> requests;
  const _OutgoingTab({required this.requests});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => ref.refresh(connectionsNotifierProvider.future),
      child: requests.isEmpty
          ? const _EmptyState(
              icon: Icons.send_outlined,
              title: 'No pending requests',
              subtitle: 'Requests you\'ve sent that haven\'t been accepted yet.',
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              itemCount: requests.length,
              separatorBuilder: (context, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _OutgoingCard(request: requests[i]),
            ),
    );
  }
}
