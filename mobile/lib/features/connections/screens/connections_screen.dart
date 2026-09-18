import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/util/app_date_format.dart';
import '../../../core/api/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/verified_badge.dart';
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
            // Always present, never `SizedBox.shrink()`. Rendering nothing while loading meant
            // the tab bar *appeared* once the request finished and pushed the whole list down —
            // a layout jump on every visit, and on a slow connection a jump the user was
            // already reading through. The counts are what load; the tabs themselves are known
            // from the start.
            _TabBar(
              controller: _tabs,
              incomingCount: async.value?.incoming.length ?? 0,
              outgoingCount: async.value?.outgoing.length ?? 0,
            ),
            Expanded(
              child: async.when(
                loading: () => const AppListSkeleton(count: 2),
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
// Was a local copy whose `>= 7 days` branch formatted the raw parsed timestamp, so a request
// created late in the local evening showed the wrong calendar day. [AppDateFormat] converts once,
// internally.
String _timeAgo(DateTime dt) => AppDateFormat.relative(dt);
