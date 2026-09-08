import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/api/api_client.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/ws_protocol.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/campus_post.dart';

/// Secure-storage key for the opportunities last-seen cursor — scoped per user so account
/// switch never inherits another student's badge baseline.
String opportunitiesLastSeenKey(String userId) =>
    'campus_hub.opportunities_last_seen.$userId';

/// Pure count used by the badge notifier and unit tests.
///
/// When [lastSeen] is null the caller should baseline to "now" and return 0 (first visit),
/// so this function treats null as zero new items.
int countNewOpportunities({
  required DateTime? lastSeen,
  required Iterable<DateTime> publishAts,
}) {
  if (lastSeen == null) return 0;
  final cursor = lastSeen.toUtc();
  return publishAts.where((at) => at.toUtc().isAfter(cursor)).length;
}

bool opportunityAudienceApplies(String audience, String role) {
  switch (audience) {
    case 'students':
      return role == 'student';
    case 'staff':
      return role != 'student';
    default: // 'all'
      return true;
  }
}

/// Client-side "new opportunities" badge for the Campus Hub quick action.
///
/// Deliberately separate from Latest Updates / announcement unread:
/// - Latest Updates = announcements only (server unread + WS ping)
/// - Opportunities = this cursor — posts published after the student last opened Opportunities
///
/// No server unread table yet; a local last-seen timestamp is enough for the hub affordance.
final opportunityNewCountProvider =
    NotifierProvider<OpportunityNewCountNotifier, int>(OpportunityNewCountNotifier.new);

class OpportunityNewCountNotifier extends Notifier<int> {
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  StreamSubscription<InboundEvent>? _eventsSub;
  StreamSubscription<void>? _reconnectSub;
  _OpportunityResumeObserver? _resumeObserver;
  String _role = 'student';

  @override
  int build() {
    final userId = ref.watch(authNotifierProvider.select((a) => a.asData?.value?.id));
    _role = ref.watch(authNotifierProvider.select((a) => a.asData?.value?.role)) ?? 'student';
    ref.keepAlive();

    if (userId == null) {
      // Logged out / switched away — never show a stale badge from the previous session.
      return 0;
    }

    try {
      final realtime = ref.watch(realtimeClientProvider);
      _eventsSub = realtime.events.listen(_onEvent);
      _reconnectSub = realtime.reconnected.listen((_) => refresh());
    } catch (_) {
      // Realtime unavailable in widget tests — badge still works via refresh()/markSeen().
    }

    _resumeObserver = _OpportunityResumeObserver(refresh);
    WidgetsBinding.instance.addObserver(_resumeObserver!);
    ref.onDispose(() {
      _eventsSub?.cancel();
      _reconnectSub?.cancel();
      if (_resumeObserver != null) {
        WidgetsBinding.instance.removeObserver(_resumeObserver!);
      }
    });

    Future.microtask(refresh);
    return 0;
  }

  void _onEvent(InboundEvent event) {
    if (event is OpportunityEvent && opportunityAudienceApplies(event.audience, _role)) {
      // Live publish while the app is open — same snappy +1 as announcements.
      state = state + 1;
    }
  }

  Future<void> refresh() async {
    final userId = ref.read(authNotifierProvider).asData?.value?.id;
    if (userId == null) {
      state = 0;
      return;
    }
    final key = opportunitiesLastSeenKey(userId);
    try {
      final raw = await _storage.read(key: key);
      if (raw == null) {
        // First visit for this user: baseline to now so historical opportunities don't all light up.
        await _storage.write(
          key: key,
          value: DateTime.now().toUtc().toIso8601String(),
        );
        state = 0;
        return;
      }
      final lastSeen = DateTime.parse(raw).toUtc();
      final client = ref.read(apiClientProvider);
      final response = await client.dio.get(
        '/campus-hub/posts',
        queryParameters: {'kind': 'opportunity'},
      );
      final posts = (response.data as List)
          .map((j) => CampusPostSummary.fromJson(j as Map<String, dynamic>))
          .toList();
      state = countNewOpportunities(
        lastSeen: lastSeen,
        publishAts: posts.map((p) => p.publishAt),
      );
    } catch (_) {
      /* keep current; next resume/refresh retries */
    }
  }

  /// Opening the Opportunities list clears the badge (same mental model as "I've seen these").
  Future<void> markSeen() async {
    final userId = ref.read(authNotifierProvider).asData?.value?.id;
    if (userId == null) {
      state = 0;
      return;
    }
    await _storage.write(
      key: opportunitiesLastSeenKey(userId),
      value: DateTime.now().toUtc().toIso8601String(),
    );
    state = 0;
  }
}

class _OpportunityResumeObserver extends WidgetsBindingObserver {
  final VoidCallback onResume;
  _OpportunityResumeObserver(this.onResume);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
