part of '../screens/connections_screen.dart';

class _IncomingTab extends StatelessWidget {
  final List<ConnectionRequest> requests;
  const _IncomingTab({required this.requests});

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return _EmptyState(
        icon: Icons.inbox_outlined,
        title: 'No incoming requests',
        subtitle: 'When someone wants to connect with you, they\'ll appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: requests.length,
      separatorBuilder: (context, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _IncomingCard(request: requests[i]),
    );
  }
}

// ── Outgoing tab ──────────────────────────────────────────────────
class _OutgoingTab extends StatelessWidget {
  final List<ConnectionRequest> requests;
  const _OutgoingTab({required this.requests});

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return _EmptyState(
        icon: Icons.send_outlined,
        title: 'No pending requests',
        subtitle: 'Requests you\'ve sent that haven\'t been accepted yet.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: requests.length,
      separatorBuilder: (context, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _OutgoingCard(request: requests[i]),
    );
  }
}

// ── Incoming request card ─────────────────────────────────────────
