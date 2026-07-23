import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../shared/widgets/app_states.dart';
import '../providers/connections_provider.dart';

part '../widgets/connections_header.dart';
part '../widgets/connections_tabs.dart';
part '../widgets/connections_incoming_card.dart';
part '../widgets/connections_outgoing_card.dart';
part '../widgets/connections_card_parts.dart';
part '../widgets/connections_states.dart';

class ConnectionsScreen extends ConsumerStatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  ConsumerState<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends ConsumerState<ConnectionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(connectionsNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onBack: () => Navigator.of(context).pop()),
            async.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => const SizedBox.shrink(),
              data: (s) => _TabBar(
                controller: _tabs,
                incomingCount: s.incoming.length,
                outgoingCount: s.outgoing.length,
              ),
            ),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorState(
                  onRetry: () =>
                      ref.invalidate(connectionsNotifierProvider),
                ),
                data: (s) => TabBarView(
                  controller: _tabs,
                  children: [
                    _IncomingTab(requests: s.incoming),
                    _OutgoingTab(requests: s.outgoing),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// ── Helpers ───────────────────────────────────────────────────────
String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('MMM d').format(dt);
}
